import 'package:flutter/material.dart';

import '../models/peer.dart';
import '../models/room.dart';
import '../services/call_controller.dart';
import 'room_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final CallController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ipController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final notice = widget.controller.consumeNotice();
    if (notice != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
      });
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: widget.controller),
      ),
    );
  }

  Future<void> _promptCustomRoomName() async {
    final nameCtrl = TextEditingController(text: '${widget.controller.profile.name}のルーム');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2B2D31),
        title: const Text('ルーム名を指定して作成', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '例: ツーリング部屋',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5865F2),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (result != null) {
      await widget.controller.createRoom(customRoomName: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.inRoom) {
          return RoomScreen(controller: widget.controller);
        }

        final profile = widget.controller.profile;
        final rooms = widget.controller.sortedRooms;
        final peers = widget.controller.knownPeers;
        final initial =
            profile.name.trim().isEmpty ? '?' : profile.name.trim().characters.first.toUpperCase();

        return Scaffold(
          backgroundColor: const Color(0xFF1E1F22),
          appBar: AppBar(
            backgroundColor: const Color(0xFF2B2D31),
            titleSpacing: 12,
            title: InkWell(
              onTap: _openSettings,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(profile.color),
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        profile.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 15, color: Colors.white54),
                  ],
                ),
              ),
            ),
            actions: [
              if (widget.controller.autoJoin)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23A55A).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF23A55A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt, size: 14, color: Color(0xFF23A55A)),
                        SizedBox(width: 2),
                        Text(
                          '自動参加ON',
                          style: TextStyle(
                            color: Color(0xFF23A55A),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '再スキャン',
                onPressed: widget.controller.refreshNetwork,
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: '設定',
                onPressed: _openSettings,
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: widget.controller.refreshNetwork,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCreateRoomCard(),
                  const SizedBox(height: 20),
                  _buildDiscoveredRoomsSection(rooms),
                  if (peers.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildRecentPeersSection(peers, rooms),
                  ],
                  const SizedBox(height: 20),
                  _buildManualIpSection(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateRoomCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF35373C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5865F2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_call, size: 22),
                  label: const Text(
                    '＋ ルームを作る（ワンタップ）',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  onPressed: () => widget.controller.createRoom(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF35373C),
                  foregroundColor: Colors.white70,
                  minimumSize: const Size(52, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.edit_note),
                tooltip: 'ルーム名を指定して作成',
                onPressed: _promptCustomRoomName,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '作成した端末がホストになり、同じWi-Fi / テザリング内の端末に自動表示されます。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveredRoomsSection(List<RoomInfo> rooms) {
    final browsing = widget.controller.discovery.browsing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.radar, color: Color(0xFF23A55A), size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '近くのルーム（タップで参加）',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (browsing)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF23A55A)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (rooms.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2D31),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF35373C)),
            ),
            child: Column(
              children: [
                const Icon(Icons.wifi_find, color: Colors.white38, size: 36),
                const SizedBox(height: 10),
                const Text(
                  '近くに公開中のルームはまだありません',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '同じWi-Fiまたはテザリングに接続しているか確認してください。\n相手がルームを作ると自動でここに表示されます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (widget.controller.discovery.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '検出状態: ${widget.controller.discovery.lastError}',
                    style: const TextStyle(color: Color(0xFFF0B232), fontSize: 11),
                  ),
                ],
              ],
            ),
          )
        else
          for (final r in rooms) _buildRoomTile(r),
      ],
    );
  }

  Widget _buildRoomTile(RoomInfo room) {
    final isKnown = widget.controller.isKnownHost(room.hostDeviceId);
    final initial =
        room.hostName.trim().isEmpty ? '?' : room.hostName.trim().characters.first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: room.isFull ? null : () => widget.controller.joinRoom(room),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2D31),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isKnown ? const Color(0xFFF0B232) : const Color(0xFF35373C),
              width: isKnown ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Color(room.hostColor),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isKnown) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0B232).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '⭐ 以前の相手',
                              style: TextStyle(
                                color: Color(0xFFF0B232),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            room.roomName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ホスト: ${room.hostName} (${room.host})',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: room.isFull
                      ? const Color(0xFF4E5058)
                      : const Color(0xFF23A55A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  room.isFull ? '満員 ${room.count}/${room.max}' : '参加 ${room.count}/${room.max}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentPeersSection(List<KnownPeer> peers, List<RoomInfo> activeRooms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history, color: Color(0xFFF0B232), size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '最近の接続（ワンタップ再接続）',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: _openSettings,
              child: const Text('管理', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final peer in peers) _buildRecentPeerTile(peer, activeRooms),
      ],
    );
  }

  Widget _buildRecentPeerTile(KnownPeer peer, List<RoomInfo> activeRooms) {
    RoomInfo? activeRoom;
    for (final r in activeRooms) {
      if (r.hostDeviceId == peer.deviceId) {
        activeRoom = r;
        break;
      }
    }
    final canTryConnect = activeRoom != null || (peer.lastHost != null && peer.lastHost!.isNotEmpty);
    final initial = peer.name.trim().isEmpty ? '?' : peer.name.trim().characters.first.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: canTryConnect ? () => widget.controller.joinKnownPeer(peer) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2D31),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF35373C)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color(peer.color),
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFF0B232), size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            peer.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeRoom != null
                          ? '🟢 ルーム公開中: ${activeRoom.roomName} (${activeRoom.count}/${activeRoom.max})'
                          : peer.lastHost != null
                              ? '前回ホストIP: ${peer.lastHost}:${peer.lastPort ?? 47800}（タップで接続試行）'
                              : '現在オフライン（相手がルームを作ると接続できます）',
                      style: TextStyle(
                        color: activeRoom != null ? const Color(0xFF23A55A) : Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (canTryConnect)
                const Icon(Icons.login, color: Colors.white70, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualIpSection() {
    final ips = widget.controller.myIps;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF35373C)),
      ),
      child: ExpansionTile(
        collapsedIconColor: Colors.white54,
        iconColor: Colors.white70,
        leading: const Icon(Icons.lan, color: Color(0xFF5865F2), size: 20),
        title: const Text(
          'IPアドレス直接入力で参加（手動接続）',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (ips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Text(
                    'この端末のIP: ',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  Expanded(
                    child: SelectableText(
                      ips.join(', '),
                      style: const TextStyle(
                        color: Color(0xFF23A55A),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: '例: 192.168.43.1',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E1F22),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.url,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF23A55A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => widget.controller.joinByIpInput(_ipController.text),
                child: const Text('参加', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
