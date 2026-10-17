import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_service.dart';

/// 通信品質（requirements Q-02〜Q-04）と音声レベル。
class CallQualityMetrics {
  const CallQualityMetrics({
    this.rttMs = 0.0,
    this.lossPercentage = 0.0,
    this.jitterMs = 0.0,
    this.audioLevel = 0.0,
    this.localAudioLevel = 0.0,
    this.isGateOpen = true,
  });

  final double rttMs;
  final double lossPercentage;
  final double jitterMs;

  /// 相手の声のレベル（0.0〜1.0）。話者表示に使う。
  final double audioLevel;

  /// 自分のマイクのレベル（0.0〜1.0）。
  final double localAudioLevel;

  /// ノイズゲートが開いているか（送信中か）。
  final bool isGateOpen;
}

/// 1対1の音声P2P接続（M3でメッシュに拡張予定）。
class WebRTCService {
  WebRTCService({required this.signaling}) {
    _sub = signaling.onMessage.listen((msg) {
      // 非同期処理の追い越し（offer処理中にcandidateが先に処理される等）を防ぐため直列化する
      _queue = _queue.then((_) => _handleSignalingMessage(msg)).catchError((Object e) {
        debugPrint('[webrtc] signaling handling error: $e');
      });
    });
  }

  final SignalingService signaling;
  late final StreamSubscription<SignalingMessage> _sub;
  Future<void> _queue = Future.value();

  /// 通話相手のシグナリング接続ID。null の間はWebRTCメッセージを無視する。
  int? remoteConnId;

  RTCPeerConnection? _peerConnection;
  RTCRtpSender? _audioSender;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? get remoteStream => _remoteStream;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isSpeakerOn = true;
  bool get isSpeakerOn => _isSpeakerOn;

  // 音声処理・ノイズゲート設定（F-32, F-33）
  bool noiseSuppression = true;
  bool echoCancellation = true;
  bool autoGainControl = true;
  bool noiseGateEnabled = true;
  double noiseGateThreshold = 0.04;

  bool _gateOpen = true;
  int _gateHoldTicks = 0;

  Timer? _statsTimer;
  final _metricsController = StreamController<CallQualityMetrics>.broadcast();
  Stream<CallQualityMetrics> get onMetrics => _metricsController.stream;

  final _callStateController = StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get onCallStateChanged => _callStateController.stream;

  int _prevPacketsLost = 0;
  int _prevPacketsReceived = 0;

  /// マイクを取得する（何度呼んでもよい）。
  Future<void> initAudio({bool forceReinit = false}) async {
    if (_localStream != null && !forceReinit) return;
    final oldStream = _localStream;
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': echoCancellation,
        'noiseSuppression': noiseSuppression,
        'autoGainControl': autoGainControl,
      },
      'video': false,
    };
    final newStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (final t in newStream.getAudioTracks()) {
      t.enabled = !_isMuted;
    }
    _localStream = newStream;
    if (_audioSender != null && newStream.getAudioTracks().isNotEmpty) {
      try {
        await _audioSender!.replaceTrack(newStream.getAudioTracks().first);
      } catch (_) {}
    }
    await oldStream?.dispose();
  }

  /// ホスト側から接続を開始する（offerを送る）。
  Future<void> startCallAsHost() async {
    await _createPeerConnection();
    final rawOffer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    final offer = RTCSessionDescription(_tuneOpusSdp(rawOffer.sdp), rawOffer.type);
    await _peerConnection!.setLocalDescription(offer);
    _send('offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  /// Opusパラメータ（FEC・DTX・32kbpsモノラル）をSDPに付与する（architecture.md §6.2）。
  String? _tuneOpusSdp(String? sdp) {
    if (sdp == null) return null;
    return sdp.replaceAllMapped(
      RegExp(r'a=fmtp:(\d+) minptime=10;useinbandfec=1'),
      (m) =>
          'a=fmtp:${m[1]} minptime=10;useinbandfec=1;usedtx=1;stereo=0;maxaveragebitrate=32000',
    );
  }

  void _send(String type, Map<String, dynamic> data) {
    signaling.send(SignalingMessage(type: type, data: data), to: remoteConnId);
  }

  Future<void> _createPeerConnection() async {
    await _closePeerConnection();

    final Map<String, dynamic> configuration = {
      'iceServers': [], // LAN内P2P：STUN/TURNは使わない
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(configuration);
    _peerConnection = pc;

    pc.onConnectionState = (state) {
      if (_callStateController.isClosed) return;
      _callStateController.add(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _startStatsCollector();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _stopStatsCollector();
      }
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _send('candidate', {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
    };

    final local = _localStream;
    if (local != null) {
      for (final track in local.getAudioTracks()) {
        _audioSender = await pc.addTrack(track, local);
      }
    }
  }

  Future<void> _handleSignalingMessage(SignalingMessage msg) async {
    if (remoteConnId == null || msg.connId != remoteConnId) return;

    switch (msg.type) {
      case 'offer':
        await _createPeerConnection();
        final pc = _peerConnection!;
        await pc.setRemoteDescription(
          RTCSessionDescription(msg.data['sdp'] as String?, msg.data['type'] as String?),
        );
        final rawAnswer = await pc.createAnswer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 0,
        });
        final answer = RTCSessionDescription(_tuneOpusSdp(rawAnswer.sdp), rawAnswer.type);
        await pc.setLocalDescription(answer);
        _send('answer', {'sdp': answer.sdp, 'type': answer.type});
      case 'answer':
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(msg.data['sdp'] as String?, msg.data['type'] as String?),
        );
      case 'candidate':
        await _peerConnection?.addCandidate(RTCIceCandidate(
          msg.data['candidate'] as String?,
          msg.data['sdpMid'] as String?,
          msg.data['sdpMLineIndex'] as int?,
        ));
      case 'hangup':
        await resetPeer();
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    for (final t in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !_isMuted;
    }
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _startStatsCollector() {
    _stopStatsCollector();
    _prevPacketsLost = 0;
    _prevPacketsReceived = 0;
    _gateOpen = true;
    _gateHoldTicks = 0;
    _statsTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _collectStats());
  }

  Future<void> _collectStats() async {
    final pc = _peerConnection;
    if (pc == null || _metricsController.isClosed) return;
    try {
      final stats = await pc.getStats();
      double rtt = 0.0;
      double lossPct = 0.0;
      double jitter = 0.0;
      double audioLevel = 0.0;
      double localLevel = 0.0;

      double? num(Object? v) => v == null ? null : double.tryParse(v.toString());

      for (final report in stats) {
        final v = report.values;
        switch (report.type) {
          case 'candidate-pair':
            if (v['state'] == 'succeeded' && v['currentRoundTripTime'] != null) {
              rtt = (num(v['currentRoundTripTime']) ?? 0.0) * 1000; // 秒 → ms
            }
          case 'inbound-rtp':
            if (v['kind'] == 'audio' || v['mediaType'] == 'audio') {
              final lost = num(v['packetsLost'])?.toInt() ?? 0;
              final received = num(v['packetsReceived'])?.toInt() ?? 0;
              final dLost = lost - _prevPacketsLost;
              final dRecv = received - _prevPacketsReceived;
              if (dLost >= 0 && dLost + dRecv > 0) {
                lossPct = dLost / (dLost + dRecv) * 100;
              }
              _prevPacketsLost = lost;
              _prevPacketsReceived = received;
              jitter = (num(v['jitter']) ?? 0.0) * 1000;
              audioLevel = num(v['audioLevel']) ?? 0.0;
            }
          case 'media-source':
            if (v['kind'] == 'audio') {
              localLevel = num(v['audioLevel']) ?? 0.0;
            }
        }
      }

      final effectiveLocal = _isMuted ? 0.0 : localLevel;

      // ノイズゲート判定（F-33）
      bool nextGateOpen = true;
      if (_isMuted) {
        nextGateOpen = false;
      } else if (!noiseGateEnabled) {
        nextGateOpen = true;
      } else if (effectiveLocal >= noiseGateThreshold) {
        _gateHoldTicks = 2; // 600ms 保持
        nextGateOpen = true;
      } else if (_gateHoldTicks > 0) {
        _gateHoldTicks--;
        nextGateOpen = true;
      } else {
        nextGateOpen = false;
      }

      if (nextGateOpen != _gateOpen) {
        _gateOpen = nextGateOpen;
        await _applySenderGate(_gateOpen);
      }

      if (_metricsController.isClosed) return;
      _metricsController.add(CallQualityMetrics(
        rttMs: rtt,
        lossPercentage: lossPct,
        jitterMs: jitter,
        audioLevel: audioLevel,
        localAudioLevel: effectiveLocal,
        isGateOpen: _gateOpen,
      ));
    } catch (_) {}
  }

  Future<void> _applySenderGate(bool open) async {
    final sender = _audioSender;
    if (sender == null) return;
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings != null && encodings.isNotEmpty) {
        encodings.first.active = open;
        await sender.setParameters(params);
      }
    } catch (_) {}
  }

  void _stopStatsCollector() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _closePeerConnection() async {
    final pc = _peerConnection;
    _peerConnection = null;
    _audioSender = null;
    _remoteStream = null;
    await pc?.close();
  }

  /// 相手との接続だけを閉じる（マイクは保持。ホストが次の参加者を待つとき用）。
  Future<void> resetPeer() async {
    _stopStatsCollector();
    await _closePeerConnection();
  }

  /// 通話を完全に終了する（マイクも解放）。
  Future<void> hangUp() async {
    remoteConnId = null;
    await resetPeer();
    await _localStream?.dispose();
    _localStream = null;
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await hangUp();
    await _metricsController.close();
    await _callStateController.close();
  }
}
