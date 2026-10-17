import 'package:flutter/material.dart';

import '../models/peer.dart';
import '../models/profile.dart';
import '../services/call_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final CallController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late int _selectedColor;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.controller.profile.name);
    _selectedColor = widget.controller.profile.color;
    widget.controller.audioDevices.refreshOutputs();
  }

  @override
  void dispose() {
    widget.controller.audioDevices.stopMicTest();
    widget.controller.audioDevices.stopPlayback();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('表示名を入力してください')),
      );
      return;
    }
    await widget.controller.updateProfile(name: name, color: _selectedColor);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('プロフィールを保存しました')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final peers = widget.controller.knownPeers;
        final ips = widget.controller.myIps;

        return Scaffold(
          backgroundColor: const Color(0xFF1E1F22),
          appBar: AppBar(
            backgroundColor: const Color(0xFF2B2D31),
            title: const Text('設定・音声テスト', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildProfileSection(),
                const SizedBox(height: 16),
                _buildAudioOutputSection(),
                const SizedBox(height: 16),
                _buildNoiseAndGateSection(),
                const SizedBox(height: 16),
                _buildMicAndRecordTestSection(),
                const SizedBox(height: 16),
                _buildAutoJoinSection(),
                const SizedBox(height: 16),
                _buildKnownPeersSection(peers),
                const SizedBox(height: 16),
                _buildDeviceInfoSection(ips),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileSection() {
    final previewName = _nameController.text.trim().isEmpty ? '?' : _nameController.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'プロフィール (F-30)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Color(_selectedColor),
                child: Text(
                  previewName.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: '表示名',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF1E1F22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'アイコン色',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in avatarPalette)
                GestureDetector(
                  onTap: () => setState(() => _selectedColor = c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedColor == c ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: _selectedColor == c
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.save),
              label: const Text('プロフィールを保存', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _saveProfile,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioOutputSection() {
    final outputs = widget.controller.audioDevices.outputs;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.headphones, color: Color(0xFF5865F2), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '音声出力デバイス (F-20)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                tooltip: '再検出',
                onPressed: () => widget.controller.audioDevices.refreshOutputs(),
              ),
            ],
          ),
          const Text(
            'Bluetoothヘッドセット（インカム）や有線イヤホンを接続すると自動で切り替わります。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in outputs)
                ChoiceChip(
                  label: Text(o.name),
                  selected: o.active,
                  selectedColor: const Color(0xFF5865F2),
                  backgroundColor: const Color(0xFF1E1F22),
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontWeight: o.active ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => widget.controller.selectAudioOutput(o.kind),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoiseAndGateSection() {
    final thresholdPct = (widget.controller.noiseGateThreshold * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.air, color: Color(0xFF23A55A), size: 20),
              SizedBox(width: 8),
              Text(
                '走行風・ノイズ対策 (F-32, F-33)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: const Color(0xFF23A55A),
            title: const Text('ノイズ抑制 (NS)', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
              '定常的な走行風・エンジン音を抑えます（推奨: ON）',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: widget.controller.noiseSuppression,
            onChanged: (v) => widget.controller.setNoiseSuppression(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: const Color(0xFF23A55A),
            title: const Text('エコー除去 (AEC)', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
              'スピーカーからの音の回り込みを防ぎます',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: widget.controller.echoCancellation,
            onChanged: (v) => widget.controller.setEchoCancellation(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: const Color(0xFF23A55A),
            title: const Text('自動ゲイン調整 (AGC)', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text(
              '声の大きさを自動で一定に揃えます',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: widget.controller.autoGainControl,
            onChanged: (v) => widget.controller.setAutoGainControl(v),
          ),
          const Divider(color: Color(0xFF35373C)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: const Color(0xFF23A55A),
            title: const Text(
              'ノイズゲート（入力感度しきい値）',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text(
              'しきい値より小さい音（話していないときの風切り音など）を送らないように遮断します',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: widget.controller.noiseGateEnabled,
            onChanged: (v) => widget.controller.setNoiseGateEnabled(v),
          ),
          if (widget.controller.noiseGateEnabled) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ゲートしきい値（高いほど強い風音を遮断）',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '$thresholdPct %',
                  style: const TextStyle(
                    color: Color(0xFF23A55A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Slider(
              value: widget.controller.noiseGateThreshold.clamp(0.01, 0.35),
              min: 0.01,
              max: 0.35,
              divisions: 34,
              activeColor: const Color(0xFF23A55A),
              onChanged: (v) => widget.controller.setNoiseGateThreshold(v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMicAndRecordTestSection() {
    final audio = widget.controller.audioDevices;
    final inCall = widget.controller.inRoom;
    final level = inCall ? widget.controller.metrics.localAudioLevel : audio.testLevel;
    final gateOpen = inCall ? widget.controller.metrics.isGateOpen : audio.testGateOpen;
    final threshold = widget.controller.noiseGateThreshold.clamp(0.01, 0.35);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mic_external_on, color: Color(0xFFF0B232), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'マイク＆録音テスト (F-35, F-36)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'ノイズ抑制・ノイズゲートを通した自分の声がどう相手に聞こえるかを録音して聴き返せます。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          // レベルメーター＋しきい値バー
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final barW = (level.clamp(0.0, 1.0)) * maxW;
              final threshX = (threshold.clamp(0.0, 1.0)) * maxW;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '入力レベル: ${(level * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: gateOpen
                              ? const Color(0xFF23A55A).withValues(alpha: 0.2)
                              : const Color(0xFFED4245).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          gateOpen ? '🟢 ゲート開（送信）' : '🛡️ ゲート閉（ノイズ遮断中）',
                          style: TextStyle(
                            color: gateOpen ? const Color(0xFF23A55A) : const Color(0xFFED4245),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    children: [
                      Container(
                        height: 18,
                        width: maxW,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1F22),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        height: 18,
                        width: barW,
                        decoration: BoxDecoration(
                          color: gateOpen ? const Color(0xFF23A55A) : const Color(0xFFF0B232),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      if (widget.controller.noiseGateEnabled)
                        Positioned(
                          left: (threshX - 1.5).clamp(0.0, maxW - 3.0),
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 3,
                            color: const Color(0xFFED4245),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (inCall)
            const Text(
              '※ 通話中はリアルタイムのマイクレベルが表示されています（録音テストはルーム退出後に行えます）。',
              style: TextStyle(color: Color(0xFFF0B232), fontSize: 12),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!audio.isMicTesting)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFED4245),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.fiber_manual_record, size: 18),
                    label: const Text('録音テスト開始（最大15秒）'),
                    onPressed: () => audio.startMicTest(
                      recordToFile: true,
                      noiseSuppression: widget.controller.noiseSuppression,
                      echoCancellation: widget.controller.echoCancellation,
                      autoGainControl: widget.controller.autoGainControl,
                      noiseGateEnabled: widget.controller.noiseGateEnabled,
                      noiseGateThreshold: widget.controller.noiseGateThreshold,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF0B232),
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.stop, size: 18),
                    label: Text(audio.isRecordingFile ? '録音を停止して保存' : 'マイクテスト停止'),
                    onPressed: () => audio.stopMicTest(),
                  ),
                if (audio.hasRecording && !audio.isMicTesting)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          audio.isPlayingRecording ? const Color(0xFF4E5058) : const Color(0xFF23A55A),
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(audio.isPlayingRecording ? Icons.stop : Icons.play_arrow, size: 18),
                    label: Text(
                      audio.isPlayingRecording
                          ? '再生停止'
                          : '録音を聴き返す (${(audio.recordingDurationMs / 1000).toStringAsFixed(1)}秒)',
                    ),
                    onPressed: () {
                      if (audio.isPlayingRecording) {
                        audio.stopPlayback();
                      } else {
                        audio.playRecordedTest();
                      }
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAutoJoinSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        activeThumbColor: const Color(0xFF23A55A),
        title: const Row(
          children: [
            Icon(Icons.star_rounded, color: Color(0xFFF0B232), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '記憶した相手のルームに自動参加 (F-09)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '過去に通話した相手（⭐）のルームがLAN上で見つかったとき、自動で参加します。自分で退出したルームには再参加しません。',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        value: widget.controller.autoJoin,
        onChanged: (v) => widget.controller.setAutoJoin(v),
      ),
    );
  }

  Widget _buildKnownPeersSection(List<KnownPeer> peers) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '記憶した相手 (F-07)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (peers.isNotEmpty)
                TextButton.icon(
                  onPressed: () => widget.controller.clearKnownPeers(),
                  icon: const Icon(Icons.delete_sweep, color: Color(0xFFED4245), size: 18),
                  label: const Text('すべて消去', style: TextStyle(color: Color(0xFFED4245))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (peers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'まだ記憶した相手はいません。一度通話するとここに自動で記録されます。',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            )
          else
            for (final p in peers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Color(p.color),
                  child: Text(
                    p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  p.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    'ID: ${p.deviceId.substring(0, p.deviceId.length.clamp(0, 8))}',
                    if (p.lastHost != null) '前回IP: ${p.lastHost}:${p.lastPort ?? 47800}',
                  ].join('  •  '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  tooltip: '削除',
                  onPressed: () => widget.controller.removeKnownPeer(p.deviceId),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoSection(List<String> ips) {
    final devId = widget.controller.profile.deviceId;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'この端末の情報',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            '端末ID: ${devId.substring(0, devId.length.clamp(0, 12))}...',
            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            ips.isEmpty ? 'IPv4アドレス: 未接続' : 'IPv4アドレス: ${ips.join(', ')}',
            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }
}
