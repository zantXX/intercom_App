import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart';

import 'profile.dart';

const String kServiceType = '_intercom._tcp';
const int kProtocolVersion = 1;

/// mDNSで見つかったルーム。
class RoomInfo {
  const RoomInfo({
    required this.roomId,
    required this.roomName,
    required this.hostDeviceId,
    required this.hostName,
    required this.hostColor,
    required this.host,
    required this.port,
    required this.count,
    required this.max,
  });

  final String roomId;
  final String roomName;
  final String hostDeviceId;
  final String hostName;
  final int hostColor;
  final String host;
  final int port;
  final int count;
  final int max;

  bool get isFull => count >= max;

  static RoomInfo? fromService(Service s) {
    final txt = s.txt ?? const <String, Uint8List?>{};
    String? t(String key) {
      final v = txt[key];
      return v == null ? null : utf8.decode(v, allowMalformed: true);
    }

    if (t('app') != 'intercom') return null;
    final roomId = t('rid');
    final hostDeviceId = t('hd');
    final port = s.port;
    if (roomId == null || hostDeviceId == null || port == null) return null;

    String? ip;
    for (final a in s.addresses ?? const <InternetAddress>[]) {
      if (a.type == InternetAddressType.IPv4) {
        ip = a.address;
        break;
      }
    }
    ip ??= s.host;
    if (ip == null) return null;

    return RoomInfo(
      roomId: roomId,
      roomName: t('rn') ?? 'ルーム',
      hostDeviceId: hostDeviceId,
      hostName: t('hn') ?? '不明',
      hostColor: int.tryParse(t('hc') ?? '') ?? 0xFF5865F2,
      host: ip,
      port: port,
      count: int.tryParse(t('n') ?? '') ?? 1,
      max: int.tryParse(t('max') ?? '') ?? 2,
    );
  }
}

/// 自分がホストのときに公開するルーム情報。
class RoomAdvert {
  const RoomAdvert({
    required this.roomId,
    required this.roomName,
    required this.host,
    required this.port,
    required this.count,
    required this.max,
  });

  final String roomId;
  final String roomName;
  final Profile host;
  final int port;
  final int count;
  final int max;

  RoomAdvert withCount(int n) =>
      RoomAdvert(roomId: roomId, roomName: roomName, host: host, port: port, count: n, max: max);

  Service toService() {
    Uint8List b(String v) => Uint8List.fromList(utf8.encode(v));
    return Service(
      name: 'intercom-$roomId',
      type: kServiceType,
      port: port,
      txt: {
        'app': b('intercom'),
        'v': b('$kProtocolVersion'),
        'rid': b(roomId),
        'rn': b(_clip(roomName, 60)),
        'hd': b(host.deviceId),
        'hn': b(_clip(host.name, 60)),
        'hc': b('${host.color}'),
        'n': b('$count'),
        'max': b('$max'),
      },
    );
  }

  static String _clip(String s, int maxChars) => s.length <= maxChars ? s : s.substring(0, maxChars);
}
