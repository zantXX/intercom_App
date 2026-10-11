import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class CallQualityMetrics {
  final double rttMs;
  final double lossPercentage;
  final double jitterMs;
  final double audioLevel;

  CallQualityMetrics({
    this.rttMs = 0.0,
    this.lossPercentage = 0.0,
    this.jitterMs = 0.0,
    this.audioLevel = 0.0,
  });
}

class WebRTCService {
  final SignalingService signaling;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? get remoteStream => _remoteStream;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isSpeakerOn = true;
  bool get isSpeakerOn => _isSpeakerOn;

  Timer? _statsTimer;
  final _metricsController = StreamController<CallQualityMetrics>.broadcast();
  Stream<CallQualityMetrics> get onMetrics => _metricsController.stream;

  final _callStateController = StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get onCallStateChanged => _callStateController.stream;

  int _prevPacketsLost = 0;
  int _prevPacketsReceived = 0;

  WebRTCService({required this.signaling}) {
    signaling.onMessage.listen(_handleSignalingMessage);
  }

  Future<void> initAudio() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  Future<void> startCallAsHost() async {
    await _createPeerConnection();

    // ホストから Offer 作成
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    signaling.send(SignalingMessage(
      type: 'offer',
      data: {'sdp': offer.sdp, 'type': offer.type},
    ));
  }

  Future<void> _createPeerConnection() async {
    final Map<String, dynamic> configuration = {
      'iceServers': [], // LAN P2P: STUN/TURN不要
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onConnectionState = (state) {
      _callStateController.add(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _startStatsCollector();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _stopStatsCollector();
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        signaling.send(SignalingMessage(
          type: 'candidate',
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ));
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'audio') {
        _remoteStream = event.streams[0];
      }
    };

    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }
  }

  Future<void> _handleSignalingMessage(SignalingMessage msg) async {
    if (msg.type == 'offer') {
      await _createPeerConnection();
      final sdp = msg.data['sdp'] as String;
      final type = msg.data['type'] as String;
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      signaling.send(SignalingMessage(
        type: 'answer',
        data: {'sdp': answer.sdp, 'type': answer.type},
      ));
    } else if (msg.type == 'answer') {
      final sdp = msg.data['sdp'] as String;
      final type = msg.data['type'] as String;
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
    } else if (msg.type == 'candidate') {
      final candidate = RTCIceCandidate(
        msg.data['candidate'] as String,
        msg.data['sdpMid'] as String,
        msg.data['sdpMLineIndex'] as int,
      );
      await _peerConnection?.addCandidate(candidate);
    } else if (msg.type == 'hangup') {
      await hangUp();
    }
  }

  void toggleMute() {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      _isMuted = !_isMuted;
      _localStream!.getAudioTracks().first.enabled = !_isMuted;
    }
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  void _startStatsCollector() {
    _stopStatsCollector();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_peerConnection == null) return;
      try {
        final stats = await _peerConnection!.getStats();
        double rtt = 0.0;
        double lossPct = 0.0;
        double jitter = 0.0;
        double audioLevel = 0.0;

        for (final report in stats) {
          if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
            final rawRtt = report.values['currentRoundTripTime'];
            if (rawRtt != null) {
              rtt = (double.tryParse(rawRtt.toString()) ?? 0.0) * 1000; // sec -> ms
            }
          }
          if (report.type == 'inbound-rtp' && report.values['mediaType'] == 'audio') {
            final lost = int.tryParse(report.values['packetsLost']?.toString() ?? '') ?? 0;
            final received = int.tryParse(report.values['packetsReceived']?.toString() ?? '') ?? 0;
            final deltaLost = lost - _prevPacketsLost;
            final deltaRecv = received - _prevPacketsReceived;
            final total = deltaLost + deltaRecv;
            if (total > 0 && deltaLost >= 0) {
              lossPct = (deltaLost / total) * 100;
            }
            _prevPacketsLost = lost;
            _prevPacketsReceived = received;

            final rawJitter = report.values['jitter'];
            if (rawJitter != null) {
              jitter = (double.tryParse(rawJitter.toString()) ?? 0.0) * 1000;
            }
            final rawAudio = report.values['audioLevel'];
            if (rawAudio != null) {
              audioLevel = double.tryParse(rawAudio.toString()) ?? 0.0;
            }
          }
        }

        _metricsController.add(CallQualityMetrics(
          rttMs: rtt,
          lossPercentage: lossPct,
          jitterMs: jitter,
          audioLevel: audioLevel,
        ));
      } catch (_) {}
    });
  }

  void _stopStatsCollector() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> hangUp() async {
    _stopStatsCollector();
    await _peerConnection?.close();
    _peerConnection = null;
    await _localStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _callStateController.add(RTCPeerConnectionState.RTCPeerConnectionStateClosed);
  }

  void dispose() {
    hangUp();
    _metricsController.close();
    _callStateController.close();
  }
}
