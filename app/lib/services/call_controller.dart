import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/peer.dart';
import '../models/profile.dart';
import '../models/room.dart';
import 'audio_device_service.dart';
import 'discovery_service.dart';
import 'network_info.dart';
import 'signaling_service.dart';
import 'storage_service.dart';
import 'webrtc_service.dart';

enum CallPhase {
  idle,
  hosting, // ホストとして参加者待ち
  joining, // 参加処理中（ハンドシェイク・P2P確立待ち）
  inCall,  // 音声P2P確立済み
}

/// ルーム作成・参加・ハンドシェイク（hello/welcome/reject）・相手の記憶・自動参加を統括する。
class CallController extends ChangeNotifier {
  CallController({
    required this.storage,
    required this.discovery,
  }) {
    _webrtc = WebRTCService(signaling: _signaling);
    _syncAudioSettingsToWebRTC();
    _msgSub = _signaling.onMessage.listen(_onSignalingMessage);
    _clientDiscSub = _signaling.onClientDisconnected.listen(_onClientDisconnected);
    _hostDiscSub = _signaling.onHostDisconnected.listen((_) => _onHostDisconnected());
    _callStateSub = _webrtc.onCallStateChanged.listen(_onCallStateChanged);
    _metricsSub = _webrtc.onMetrics.listen(_onMetrics);
    discovery.addListener(_onDiscoveryChanged);
    audioDevices.addListener(notifyListeners);
  }

  final StorageService storage;
  final DiscoveryService discovery;
  final AudioDeviceService audioDevices = AudioDeviceService();

  final SignalingService _signaling = SignalingService();
  late final WebRTCService _webrtc;

  late final StreamSubscription<SignalingMessage> _msgSub;
  late final StreamSubscription<int> _clientDiscSub;
  late final StreamSubscription<void> _hostDiscSub;
  late final StreamSubscription<RTCPeerConnectionState> _callStateSub;
  late final StreamSubscription<CallQualityMetrics> _metricsSub;

  CallPhase _phase = CallPhase.idle;
  bool _isHost = false;
  String? _roomId;
  String _roomName = '';
  String? _connectingHost;
  int? _connectingPort;
  PeerInfo? _remotePeer;
  bool _remoteMuted = false;
  CallQualityMetrics _metrics = const CallQualityMetrics();
  String _statusMessage = '待機中';
  String? _pendingNotice;
  List<String> _myIps = const [];
  Timer? _handshakeTimer;

  /// 自分で退出したルームID（F-09：手動退出直後に同じルームへ自動再参加しないため）。
  String? _dismissedRoomId;
  bool _autoJoinBusy = false;

  // ---- 公開ゲッター ----
  Profile get profile => storage.profile;
  List<KnownPeer> get knownPeers => storage.knownPeers;
  bool get autoJoin => storage.autoJoin;

  bool get noiseSuppression => storage.noiseSuppression;
  bool get echoCancellation => storage.echoCancellation;
  bool get autoGainControl => storage.autoGainControl;
  bool get noiseGateEnabled => storage.noiseGateEnabled;
  double get noiseGateThreshold => storage.noiseGateThreshold;

  CallPhase get phase => _phase;
  bool get inRoom => _phase != CallPhase.idle;
  bool get isHost => _isHost;
  String? get roomId => _roomId;
  String get roomName => _roomName;
  int? get hostPort => _signaling.port;
  List<String> get myIps => _myIps;
  String? get connectedAddress =>
      _connectingHost != null ? '$_connectingHost:${_connectingPort ?? SignalingService.defaultPort}' : null;

  PeerInfo? get remotePeer => _remotePeer;
  bool get remoteMuted => _remoteMuted;
  bool get isMuted => _webrtc.isMuted;
  bool get isSpeakerOn => audioDevices.activeKind == 'speaker';
  CallQualityMetrics get metrics => _metrics;
  String get statusMessage => _statusMessage;

  void _syncAudioSettingsToWebRTC() {
    _webrtc.noiseSuppression = storage.noiseSuppression;
    _webrtc.echoCancellation = storage.echoCancellation;
    _webrtc.autoGainControl = storage.autoGainControl;
    _webrtc.noiseGateEnabled = storage.noiseGateEnabled;
    _webrtc.noiseGateThreshold = storage.noiseGateThreshold;
  }

  /// 画面側でSnackBar等に表示するための通知を取り出す（1回読むと消える）。
  String? consumeNotice() {
    final n = _pendingNotice;
    _pendingNotice = null;
    return n;
  }

  void _setNotice(String msg) {
    _pendingNotice = msg;
    notifyListeners();
  }

  /// 初期化：IP取得とmDNS検出開始。
  Future<void> init() async {
    await audioDevices.refreshOutputs();
    await refreshNetwork();
  }

  Future<void> refreshNetwork() async {
    _myIps = await localIPv4Addresses();
    notifyListeners();
    if (_phase == CallPhase.idle) {
      await discovery.stopBrowsing();
      await discovery.startBrowsing(profile.deviceId);
    }
  }

  Future<void> _ensurePermissionsAndAudio() async {
    await [
      Permission.microphone,
      Permission.bluetoothConnect,
    ].request();
    await audioDevices.stopMicTest();
    await audioDevices.stopPlayback();
    _syncAudioSettingsToWebRTC();
    await _webrtc.initAudio();
    await audioDevices.applyInitialCallRoute();
  }

  // ---- プロフィール・設定操作 ----
  Future<void> updateProfile({required String name, required int color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await storage.saveProfile(profile.copyWith(name: trimmed, color: color));
    notifyListeners();
  }

  Future<void> setAutoJoin(bool value) async {
    await storage.setAutoJoin(value);
    if (value) {
      _dismissedRoomId = null;
    }
    notifyListeners();
    if (value) {
      _checkAutoJoin();
    }
  }

  Future<void> setNoiseSuppression(bool value) async {
    await storage.setNoiseSuppression(value);
    _syncAudioSettingsToWebRTC();
    if (inRoom) await _webrtc.initAudio(forceReinit: true);
    notifyListeners();
  }

  Future<void> setEchoCancellation(bool value) async {
    await storage.setEchoCancellation(value);
    _syncAudioSettingsToWebRTC();
    if (inRoom) await _webrtc.initAudio(forceReinit: true);
    notifyListeners();
  }

  Future<void> setAutoGainControl(bool value) async {
    await storage.setAutoGainControl(value);
    _syncAudioSettingsToWebRTC();
    if (inRoom) await _webrtc.initAudio(forceReinit: true);
    notifyListeners();
  }

  Future<void> setNoiseGateEnabled(bool value) async {
    await storage.setNoiseGateEnabled(value);
    _syncAudioSettingsToWebRTC();
    await audioDevices.updateMicTestGate(
      noiseGateEnabled: value,
      noiseGateThreshold: storage.noiseGateThreshold,
    );
    notifyListeners();
  }

  Future<void> setNoiseGateThreshold(double value) async {
    await storage.setNoiseGateThreshold(value);
    _syncAudioSettingsToWebRTC();
    await audioDevices.updateMicTestGate(
      noiseGateEnabled: storage.noiseGateEnabled,
      noiseGateThreshold: storage.noiseGateThreshold,
    );
    notifyListeners();
  }

  Future<void> removeKnownPeer(String deviceId) async {
    await storage.removeKnownPeer(deviceId);
    notifyListeners();
  }

  Future<void> clearKnownPeers() async {
    await storage.clearKnownPeers();
    notifyListeners();
  }

  // ---- ルーム一覧（⭐記憶済み優先ソート） ----
  List<RoomInfo> get sortedRooms {
    final list = List<RoomInfo>.of(discovery.rooms);
    list.sort((a, b) {
      final aKnown = storage.isKnown(a.hostDeviceId) ? 0 : 1;
      final bKnown = storage.isKnown(b.hostDeviceId) ? 0 : 1;
      if (aKnown != bKnown) return aKnown.compareTo(bKnown);
      return a.roomName.compareTo(b.roomName);
    });
    return list;
  }

  bool isKnownHost(String deviceId) => storage.isKnown(deviceId);

  void _onDiscoveryChanged() {
    notifyListeners();
    _checkAutoJoin();
  }

  void _checkAutoJoin() {
    if (!storage.autoJoin || _phase != CallPhase.idle || _autoJoinBusy) return;
    for (final room in discovery.rooms) {
      if (room.isFull) continue;
      if (!storage.isKnown(room.hostDeviceId)) continue;
      if (room.roomId == _dismissedRoomId) continue;

      _autoJoinBusy = true;
      Future.microtask(() async {
        try {
          if (_phase == CallPhase.idle) {
            await joinRoom(room, isAutoJoin: true);
          }
        } finally {
          _autoJoinBusy = false;
        }
      });
      break;
    }
  }

  // ---- ホスト：ルーム作成 ----
  Future<void> createRoom({String? customRoomName}) async {
    if (_phase != CallPhase.idle) return;
    final rName = (customRoomName?.trim().isNotEmpty ?? false)
        ? customRoomName!.trim()
        : '${profile.name}のルーム';
    final rId = randomHex(4);

    _isHost = true;
    _roomId = rId;
    _roomName = rName;
    _remotePeer = null;
    _remoteMuted = false;
    _metrics = const CallQualityMetrics();
    _phase = CallPhase.hosting;
    _statusMessage = 'ルーム準備中...';
    notifyListeners();

    try {
      await discovery.stopBrowsing();
      await _ensurePermissionsAndAudio();
      _myIps = await localIPv4Addresses();
      final port = await _signaling.startHost();
      await discovery.advertise(RoomAdvert(
        roomId: rId,
        roomName: rName,
        host: profile,
        port: port,
        count: 1,
        max: 2,
      ));
      _statusMessage = '参加者を待っています...';
      notifyListeners();
    } catch (e) {
      _setNotice('ルーム作成に失敗しました: $e');
      await leaveRoom(byUser: false);
    }
  }

  // ---- クライアント：ルーム参加 ----
  Future<void> joinRoom(RoomInfo room, {bool isAutoJoin = false}) async {
    if (!isAutoJoin) {
      _dismissedRoomId = null;
    }
    _roomId = room.roomId;
    await _connectInternal(
      host: room.host,
      port: room.port,
      initialRoomName: room.roomName,
      initialPeer: PeerInfo(
        deviceId: room.hostDeviceId,
        name: room.hostName,
        color: room.hostColor,
      ),
    );
  }

  /// 「最近の接続」からワンタップ参加。mDNSで見つかっていればそのルームへ、なければ前回IPへ接続を試す。
  Future<void> joinKnownPeer(KnownPeer peer) async {
    _dismissedRoomId = null;
    for (final room in discovery.rooms) {
      if (room.hostDeviceId == peer.deviceId) {
        await joinRoom(room);
        return;
      }
    }
    if (peer.lastHost != null && peer.lastHost!.isNotEmpty) {
      await _connectInternal(
        host: peer.lastHost!,
        port: peer.lastPort ?? SignalingService.defaultPort,
        initialRoomName: '${peer.name}のルーム',
        initialPeer: PeerInfo(
          deviceId: peer.deviceId,
          name: peer.name,
          color: peer.color,
        ),
      );
      return;
    }
    _setNotice('${peer.name} のルームが近くに見つかりません（相手がルームを作成しているか確認してください）');
  }

  /// IPアドレス（または `IP:ポート`）手入力での参加。
  Future<void> joinByIpInput(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      _setNotice('IPアドレスを入力してください');
      return;
    }
    String host = trimmed;
    int port = SignalingService.defaultPort;
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      host = parts.first.trim();
      port = int.tryParse(parts.last.trim()) ?? SignalingService.defaultPort;
    }
    _dismissedRoomId = null;
    await _connectInternal(
      host: host,
      port: port,
      initialRoomName: '$host のルーム',
    );
  }

  Future<void> _connectInternal({
    required String host,
    required int port,
    required String initialRoomName,
    PeerInfo? initialPeer,
  }) async {
    if (_phase != CallPhase.idle) return;

    _isHost = false;
    _roomName = initialRoomName;
    _connectingHost = host;
    _connectingPort = port;
    _remotePeer = initialPeer;
    _remoteMuted = false;
    _metrics = const CallQualityMetrics();
    _phase = CallPhase.joining;
    _statusMessage = '$host:$port に接続中...';
    notifyListeners();

    try {
      await discovery.stopBrowsing();
      await _ensurePermissionsAndAudio();
      _webrtc.remoteConnId = 0;
      await _signaling.connectToHost(host, port: port);

      _statusMessage = 'ルームに入室要求中...';
      notifyListeners();

      _signaling.send(SignalingMessage(
        type: 'hello',
        data: {
          'v': kProtocolVersion,
          'peer': profile.toPeerJson(),
          'muted': _webrtc.isMuted,
        },
      ));

      _handshakeTimer?.cancel();
      _handshakeTimer = Timer(const Duration(seconds: 8), () {
        if (_phase == CallPhase.joining && !_isHost) {
          _setNotice('ホストからの応答がタイムアウトしました');
          leaveRoom(byUser: false);
        }
      });
    } catch (e) {
      _setNotice('接続できませんでした ($host:$port)');
      await leaveRoom(byUser: false);
    }
  }

  // ---- シグナリング受信処理 ----
  Future<void> _onSignalingMessage(SignalingMessage msg) async {
    if (_isHost) {
      await _handleHostSignaling(msg);
    } else {
      await _handleClientSignaling(msg);
    }
  }

  Future<void> _handleHostSignaling(SignalingMessage msg) async {
    switch (msg.type) {
      case 'hello':
        // すでに別の相手と通話中なら満員として拒否する
        final currentConn = _webrtc.remoteConnId;
        if (currentConn != null && currentConn != msg.connId) {
          _signaling.send(
            SignalingMessage(
              type: 'reject',
              data: {'reason': 'full', 'message': 'このルームは満員です（2/2）'},
            ),
            to: msg.connId,
          );
          await _signaling.disconnectClient(msg.connId);
          return;
        }

        final peer = PeerInfo.fromJson(msg.data['peer']);
        if (peer == null) {
          await _signaling.disconnectClient(msg.connId);
          return;
        }

        _remotePeer = peer;
        _remoteMuted = msg.data['muted'] == true;
        _webrtc.remoteConnId = msg.connId;
        _phase = CallPhase.joining;
        _statusMessage = '${peer.name} と音声接続中...';
        notifyListeners();

        // 相手を記憶する（F-07）
        await storage.upsertKnownPeer(KnownPeer(
          deviceId: peer.deviceId,
          name: peer.name,
          color: peer.color,
          lastSeen: DateTime.now(),
        ));
        notifyListeners();

        await discovery.updateAdvertCount(2);

        _signaling.send(
          SignalingMessage(
            type: 'welcome',
            data: {
              'roomId': _roomId,
              'roomName': _roomName,
              'host': profile.toPeerJson(),
              'hostMuted': _webrtc.isMuted,
            },
          ),
          to: msg.connId,
        );

        await _webrtc.startCallAsHost();

      case 'state':
        if (msg.connId == _webrtc.remoteConnId) {
          _remoteMuted = msg.data['muted'] == true;
          notifyListeners();
        }

      case 'leave':
        if (msg.connId == _webrtc.remoteConnId) {
          await _handlePeerLeftOnHost();
        }
    }
  }

  Future<void> _handleClientSignaling(SignalingMessage msg) async {
    switch (msg.type) {
      case 'welcome':
        _handshakeTimer?.cancel();
        _roomId = msg.data['roomId'] as String? ?? _roomId;
        _roomName = msg.data['roomName'] as String? ?? _roomName;
        final hostPeer = PeerInfo.fromJson(msg.data['host']);
        if (hostPeer != null) {
          _remotePeer = hostPeer;
          // ホストの端末情報と接続先IP/ポートを記憶する（F-07）
          await storage.upsertKnownPeer(KnownPeer(
            deviceId: hostPeer.deviceId,
            name: hostPeer.name,
            color: hostPeer.color,
            lastSeen: DateTime.now(),
            lastHost: _connectingHost,
            lastPort: _connectingPort,
          ));
        }
        _remoteMuted = msg.data['hostMuted'] == true;
        _statusMessage = '${_remotePeer?.name ?? "ホスト"} と音声接続中...';
        notifyListeners();

      case 'reject':
        _handshakeTimer?.cancel();
        final reason = msg.data['message'] as String? ?? 'ルームに参加できませんでした';
        _setNotice(reason);
        await leaveRoom(byUser: false);

      case 'state':
        _remoteMuted = msg.data['muted'] == true;
        notifyListeners();

      case 'room-closed':
        _handshakeTimer?.cancel();
        _setNotice('ホストがルームを終了しました');
        await leaveRoom(byUser: false);
    }
  }

  Future<void> _onClientDisconnected(int connId) async {
    if (_isHost && connId == _webrtc.remoteConnId) {
      await _handlePeerLeftOnHost();
    }
  }

  Future<void> _handlePeerLeftOnHost() async {
    final leftName = _remotePeer?.name ?? '相手';
    _webrtc.remoteConnId = null;
    await _webrtc.resetPeer();
    _remotePeer = null;
    _remoteMuted = false;
    _metrics = const CallQualityMetrics();
    if (_phase != CallPhase.idle) {
      _phase = CallPhase.hosting;
      _statusMessage = '$leftName が退出しました。参加者を待っています...';
      await discovery.updateAdvertCount(1);
      notifyListeners();
    }
  }

  Future<void> _onHostDisconnected() async {
    if (!_isHost && _phase != CallPhase.idle) {
      _handshakeTimer?.cancel();
      _setNotice('ホストとの接続が切断されました');
      await leaveRoom(byUser: false);
    }
  }

  void _onCallStateChanged(RTCPeerConnectionState state) {
    if (_phase == CallPhase.idle) return;
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _phase = CallPhase.inCall;
      _statusMessage = '通話中';
      notifyListeners();
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _statusMessage = '音声接続に失敗しました';
      notifyListeners();
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      _statusMessage = '通信が不安定です...';
      notifyListeners();
    }
  }

  void _onMetrics(CallQualityMetrics m) {
    _metrics = m;
    notifyListeners();
  }

  // ---- 通話中の操作 ----
  void toggleMute() {
    _webrtc.toggleMute();
    if (_phase != CallPhase.idle) {
      _signaling.send(
        SignalingMessage(type: 'state', data: {'muted': _webrtc.isMuted}),
        to: _isHost ? _webrtc.remoteConnId : null,
      );
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    final nextKind = audioDevices.activeKind == 'speaker' ? 'earpiece' : 'speaker';
    await audioDevices.selectOutput(nextKind);
  }

  Future<void> selectAudioOutput(String kind) async {
    await audioDevices.selectOutput(kind);
  }

  /// ルームから退出（ホストならルーム終了）。
  Future<void> leaveRoom({bool byUser = true}) async {
    _handshakeTimer?.cancel();
    _handshakeTimer = null;

    if (byUser && _roomId != null) {
      _dismissedRoomId = _roomId;
    }

    if (_phase != CallPhase.idle) {
      try {
        if (_isHost) {
          _signaling.send(SignalingMessage(type: 'room-closed', data: {'reason': 'host-left'}));
          await discovery.stopAdvertising();
        } else {
          _signaling.send(SignalingMessage(type: 'leave'));
        }
      } catch (_) {}
    }

    await _webrtc.hangUp();
    await _signaling.close();

    _phase = CallPhase.idle;
    _isHost = false;
    _roomId = null;
    _roomName = '';
    _connectingHost = null;
    _connectingPort = null;
    _remotePeer = null;
    _remoteMuted = false;
    _metrics = const CallQualityMetrics();
    _statusMessage = '待機中';
    notifyListeners();

    await discovery.startBrowsing(profile.deviceId);
  }

  @override
  void dispose() {
    _handshakeTimer?.cancel();
    discovery.removeListener(_onDiscoveryChanged);
    audioDevices.removeListener(notifyListeners);
    _msgSub.cancel();
    _clientDiscSub.cancel();
    _hostDiscSub.cancel();
    _callStateSub.cancel();
    _metricsSub.cancel();
    _webrtc.dispose();
    _signaling.dispose();
    super.dispose();
  }
}
