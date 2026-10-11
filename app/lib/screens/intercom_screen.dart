import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

class IntercomScreen extends StatefulWidget {
  const IntercomScreen({super.key});

  @override
  State<IntercomScreen> createState() => _IntercomScreenState();
}

class _IntercomScreenState extends State<IntercomScreen> {
  final SignalingService _signaling = SignalingService();
  late final WebRTCService _webrtc;
  final TextEditingController _ipController = TextEditingController();

  List<String> _myIpAddresses = [];
  bool _isHosting = false;
  bool _isConnecting = false;
  bool _isInCall = false;
  String _statusMessage = '待機中';

  CallQualityMetrics _metrics = CallQualityMetrics();
  StreamSubscription? _metricsSub;
  StreamSubscription? _callStateSub;
  StreamSubscription? _signalingStateSub;

  @override
  void initState() {
    super.initState();
    _webrtc = WebRTCService(signaling: _signaling);
    _requestPermissions();
    _loadMyIpAddresses();

    _callStateSub = _webrtc.onCallStateChanged.listen((state) {
      setState(() {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _isInCall = true;
          _isConnecting = false;
          _statusMessage = '通話中（P2P接続完了）';
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _isInCall = false;
          _isConnecting = false;
          _statusMessage = state == RTCPeerConnectionState.RTCPeerConnectionStateFailed
              ? '接続失敗'
              : '切断されました';
        }
      });
    });

    _signalingStateSub = _signaling.onConnectedStateChanged.listen((connected) {
      if (connected && _isHosting && !_isInCall) {
        // 相手がWebSocketに接続してきたらホストから通話開始
        setState(() {
          _statusMessage = '相手と接続中...';
        });
        _webrtc.startCallAsHost();
      }
    });

    _metricsSub = _webrtc.onMetrics.listen((metrics) {
      setState(() {
        _metrics = metrics;
      });
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.bluetoothConnect,
    ].request();
    await _webrtc.initAudio();
  }

  Future<void> _loadMyIpAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          ips.add('${iface.name}: ${addr.address}');
        }
      }
      setState(() {
        _myIpAddresses = ips;
      });
    } catch (_) {}
  }

  Future<void> _startHost() async {
    setState(() {
      _isHosting = true;
      _isConnecting = true;
      _statusMessage = 'ホスト待機中（ポート: 47800）... 相手の接続を待っています';
    });
    try {
      await _signaling.startHost();
    } catch (e) {
      setState(() {
        _isHosting = false;
        _isConnecting = false;
        _statusMessage = 'ホスト起動エラー: $e';
      });
    }
  }

  Future<void> _connectToHost() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相手のIPアドレスを入力してください')),
      );
      return;
    }

    setState(() {
      _isHosting = false;
      _isConnecting = true;
      _statusMessage = '$ip に接続中...';
    });

    try {
      await _signaling.connectToHost(ip);
      setState(() {
        _statusMessage = 'WebSocket接続完了、音声確立待ち...';
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = '接続エラー: $e';
      });
    }
  }

  Future<void> _hangUp() async {
    await _webrtc.hangUp();
    await _signaling.close();
    setState(() {
      _isHosting = false;
      _isConnecting = false;
      _isInCall = false;
      _statusMessage = '待機中';
      _metrics = CallQualityMetrics();
    });
  }

  @override
  void dispose() {
    _metricsSub?.cancel();
    _callStateSub?.cancel();
    _signalingStateSub?.cancel();
    _webrtc.dispose();
    _signaling.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1F22), // Discord dark
      appBar: AppBar(
        backgroundColor: const Color(0xFF2B2D31),
        title: const Text('🏍️ Intercom P2P (M1)', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'IP再読込',
            onPressed: _loadMyIpAddresses,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 端末IPカード
              _buildIpCard(),
              const SizedBox(height: 16),

              // ステータス表示
              _buildStatusCard(),
              const SizedBox(height: 16),

              // 通話操作カード
              if (!_isInCall && !_isConnecting) ...[
                _buildSetupCard(),
              ] else ...[
                _buildActiveCallCard(),
              ],

              const SizedBox(height: 16),

              // 通信品質メトリクス (Q-01〜Q-04)
              if (_isInCall) _buildMetricsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIpCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF35373C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wifi, color: Color(0xFF5865F2), size: 20),
              SizedBox(width: 8),
              Text(
                'この端末のIPアドレス',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_myIpAddresses.isEmpty)
            const Text('取得中またはネットワーク未接続', style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            ..._myIpAddresses.map(
              (ip) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: SelectableText(
                  ip,
                  style: const TextStyle(
                    color: Color(0xFF23A55A),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    Color statusColor = Colors.grey;
    if (_isInCall) {
      statusColor = const Color(0xFF23A55A); // Discord Green
    } else if (_isConnecting) {
      statusColor = const Color(0xFFFEE75C); // Yellow
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            _isInCall
                ? Icons.phone_in_talk
                : _isConnecting
                    ? Icons.hourglass_top
                    : Icons.info_outline,
            color: statusColor,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '1. ホストとして待機する',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pixel 8a などテザリング親機側で「待機開始」を押してください。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5865F2), // Discord Blurple
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.hub),
            label: const Text('ホスト待機を開始', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _startHost,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(color: Color(0xFF3F4147)),
          ),
          const Text(
            '2. 相手のホストに接続する',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'もう片方の端末で、相手に表示されているIPアドレスを入力して参加します。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ipController,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: '例: 192.168.43.1',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1E1F22),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixIcon: const Icon(Icons.arrow_forward, color: Colors.white54),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF23A55A), // Green
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.login),
            label: const Text('ホストに接続して通話', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _connectToHost,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCallCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // 話者アバター（Discord風）
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _metrics.audioLevel > 0.05
                        ? const Color(0xFF23A55A) // 話している時に緑に光る
                        : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 44,
                backgroundColor: const Color(0xFF5865F2),
                child: Icon(
                  _isInCall ? Icons.person : Icons.hourglass_top,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              if (_webrtc.isMuted)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFDA373C),
                    child: Icon(Icons.mic_off, size: 18, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _isInCall ? 'P2P通話中' : '接続処理中...',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // コントロールボタン群（グローブでも押しやすい大きめサイズ 64dp+）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // ミュートボタン
              _buildControlButton(
                icon: _webrtc.isMuted ? Icons.mic_off : Icons.mic,
                label: _webrtc.isMuted ? 'ミュート中' : 'マイクON',
                color: _webrtc.isMuted ? const Color(0xFFDA373C) : const Color(0xFF4E5058),
                onTap: () {
                  setState(() {
                    _webrtc.toggleMute();
                  });
                },
              ),

              // スピーカー切替
              _buildControlButton(
                icon: _webrtc.isSpeakerOn ? Icons.volume_up : Icons.phone_in_talk,
                label: _webrtc.isSpeakerOn ? 'スピーカー' : '受話口',
                color: const Color(0xFF4E5058),
                onTap: () {
                  setState(() {
                    _webrtc.toggleSpeaker();
                  });
                },
              ),

              // 切断ボタン
              _buildControlButton(
                icon: Icons.call_end,
                label: '切断',
                color: const Color(0xFFDA373C),
                onTap: _hangUp,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMetricsCard() {
    Color rttColor = const Color(0xFF23A55A);
    if (_metrics.rttMs > 150) {
      rttColor = const Color(0xFFDA373C);
    } else if (_metrics.rttMs > 50) {
      rttColor = const Color(0xFFFEE75C);
    }

    Color lossColor = const Color(0xFF23A55A);
    if (_metrics.lossPercentage > 5.0) {
      lossColor = const Color(0xFFDA373C);
    } else if (_metrics.lossPercentage > 1.0) {
      lossColor = const Color(0xFFFEE75C);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF35373C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.speed, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'リアルタイム通信品質 (Q-01〜Q-04)',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem('往復遅延 (RTT)', '${_metrics.rttMs.toStringAsFixed(0)} ms', rttColor),
              _buildMetricItem('欠落率 (Loss)', '${_metrics.lossPercentage.toStringAsFixed(1)} %', lossColor),
              _buildMetricItem('ジッター', '${_metrics.jitterMs.toStringAsFixed(0)} ms', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}
