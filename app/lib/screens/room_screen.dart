import 'package:flutter/material.dart';

import '../services/audio_device_service.dart';
import '../services/call_controller.dart';
import 'settings_screen.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key, required this.controller});

  final CallController controller;

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'bluetooth':
        return Icons.bluetooth_audio;
      case 'wired':
        return Icons.headset;
      case 'earpiece':
        return Icons.phone_in_talk;
      case 'speaker':
      default:
        return Icons.volume_up;
    }
  }

  String _shortLabelForOutput(AudioOutputOption opt) {
    switch (opt.kind) {
      case 'bluetooth':
        return 'Bluetooth';
      case 'wired':
        return 'イヤホン';
      case 'earpiece':
        return '受話口';
      case 'speaker':
      default:
        return 'スピーカー';
    }
  }

  Future<void> _showAudioOutputSheet(BuildContext context) async {
    await controller.audioDevices.refreshOutputs();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2B2D31),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ListenableBuilder(
          listenable: controller.audioDevices,
          builder: (context, _) {
            final outputs = controller.audioDevices.outputs;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Text(
                        '音声の出力先を選択 (F-20)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final o in outputs)
                      ListTile(
                        leading: Icon(
                          _iconForKind(o.kind),
                          color: o.active ? const Color(0xFF23A55A) : Colors.white70,
                        ),
                        title: Text(
                          o.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: o.active ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: o.active
                            ? const Icon(Icons.check_circle, color: Color(0xFF23A55A))
                            : null,
                        onTap: () {
                          controller.selectAudioOutput(o.kind);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final peer = controller.remotePeer;
        final isInCall = controller.phase == CallPhase.inCall;
        final count = peer != null ? 2 : 1;
        final activeOut = controller.audioDevices.activeOutput;
        final mySpeaking = !controller.isMuted &&
            controller.metrics.isGateOpen &&
            controller.metrics.localAudioLevel > controller.noiseGateThreshold;

        return Scaffold(
          backgroundColor: const Color(0xFF1E1F22),
          appBar: AppBar(
            backgroundColor: const Color(0xFF2B2D31),
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: Color(0xFF23A55A), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.roomName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1F22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count/2人',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: '音声・ノイズ設定',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(controller: controller),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusBanner(isInCall),
                  if (controller.isHost && controller.myIps.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildHostAddressBanner(),
                  ],
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildMemberTile(
                                    name: '${controller.profile.name} (自分)',
                                    color: controller.profile.color,
                                    speaking: mySpeaking,
                                    muted: controller.isMuted,
                                    roleBadge: controller.isHost ? 'ホスト' : '参加者',
                                    subStatus: isInCall && controller.noiseGateEnabled && !controller.isMuted
                                        ? (controller.metrics.isGateOpen ? '🟢 送信中' : '🛡️ ノイズ遮断中')
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: peer != null
                                      ? _buildMemberTile(
                                          name: peer.name,
                                          color: peer.color,
                                          speaking: !controller.remoteMuted &&
                                              controller.metrics.audioLevel > 0.04,
                                          muted: controller.remoteMuted,
                                          roleBadge: !controller.isHost ? 'ホスト' : '⭐記憶済',
                                        )
                                      : _buildWaitingTile(),
                                ),
                              ],
                            ),
                            if (isInCall) ...[
                              const SizedBox(height: 24),
                              _buildMetricsCard(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBottomControls(context, activeOut),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBanner(bool isInCall) {
    final Color color = isInCall
        ? const Color(0xFF23A55A)
        : const Color(0xFFF0B232);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isInCall ? Icons.graphic_eq : Icons.wifi_tethering,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              controller.statusMessage,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostAddressBanner() {
    final port = controller.hostPort ?? 47800;
    final addrText = controller.myIps.map((ip) => '$ip:$port').join(' / ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.router, color: Colors.white54, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              '手動接続用アドレス: $addrText',
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile({
    required String name,
    required int color,
    required bool speaking,
    required bool muted,
    String? roleBadge,
    String? subStatus,
  }) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: speaking ? const Color(0xFF23A55A) : const Color(0xFF35373C),
          width: speaking ? 2.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: speaking ? const Color(0xFF23A55A) : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 40,
                backgroundColor: Color(color),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (muted)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Color(0xFFED4245),
                    child: Icon(Icons.mic_off, size: 17, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          if (roleBadge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1F22),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                roleBadge,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          if (subStatus != null) ...[
            const SizedBox(height: 6),
            Text(
              subStatus,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaitingTile() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF35373C)),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Color(0xFF1E1F22),
              child: Icon(Icons.person_add_alt_1, size: 34, color: Colors.white38),
            ),
          ),
          SizedBox(height: 12),
          Text(
            '参加者待ち',
            style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            '自動検出で公開中',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard() {
    final m = controller.metrics;
    Color rttColor = const Color(0xFF23A55A);
    if (m.rttMs > 150) {
      rttColor = const Color(0xFFED4245);
    } else if (m.rttMs > 50) {
      rttColor = const Color(0xFFF0B232);
    }

    Color lossColor = const Color(0xFF23A55A);
    if (m.lossPercentage > 5.0) {
      lossColor = const Color(0xFFED4245);
    } else if (m.lossPercentage > 1.0) {
      lossColor = const Color(0xFFF0B232);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF35373C)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metricItem('往復遅延 (RTT)', '${m.rttMs.toStringAsFixed(0)} ms', rttColor),
          _metricItem('欠落率 (Loss)', '${m.lossPercentage.toStringAsFixed(1)} %', lossColor),
          _metricItem('ジッター', '${m.jitterMs.toStringAsFixed(0)} ms', Colors.white),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _buildBottomControls(BuildContext context, AudioOutputOption activeOut) {
    final isBtOrWired = activeOut.kind == 'bluetooth' || activeOut.kind == 'wired';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bigButton(
            icon: controller.isMuted ? Icons.mic_off : Icons.mic,
            label: controller.isMuted ? 'ミュート中' : 'マイクON',
            color: controller.isMuted ? const Color(0xFFED4245) : const Color(0xFF4E5058),
            onTap: controller.toggleMute,
          ),
          _bigButton(
            icon: _iconForKind(activeOut.kind),
            label: '${_shortLabelForOutput(activeOut)} ▲',
            color: isBtOrWired ? const Color(0xFF5865F2) : const Color(0xFF4E5058),
            onTap: () => _showAudioOutputSheet(context),
          ),
          _bigButton(
            icon: Icons.call_end,
            label: controller.isHost ? 'ルーム終了' : '退出',
            color: const Color(0xFFED4245),
            onTap: () => controller.leaveRoom(byUser: true),
          ),
        ],
      ),
    );
  }

  Widget _bigButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
