/// 通話相手の情報（シグナリングで受け取る）。
class PeerInfo {
  const PeerInfo({required this.deviceId, required this.name, required this.color});

  final String deviceId;
  final String name;
  final int color;

  static PeerInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final color = json['color'];
    if (id is! String || name is! String) return null;
    return PeerInfo(deviceId: id, name: name, color: color is int ? color : 0xFF5865F2);
  }
}

/// 一度通話した相手の記憶（F-07）。
class KnownPeer {
  const KnownPeer({
    required this.deviceId,
    required this.name,
    required this.color,
    required this.lastSeen,
    this.lastHost,
    this.lastPort,
  });

  final String deviceId;
  final String name;
  final int color;
  final DateTime lastSeen;

  /// 相手がホストだったときの接続先（相手が参加者だった場合は null）。
  /// テザリングではIPが変わることがあるため、あくまで「試す」ための補助情報。
  final String? lastHost;
  final int? lastPort;

  KnownPeer mergeWith(KnownPeer newer) => KnownPeer(
        deviceId: deviceId,
        name: newer.name,
        color: newer.color,
        lastSeen: newer.lastSeen,
        lastHost: newer.lastHost ?? lastHost,
        lastPort: newer.lastPort ?? lastPort,
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'color': color,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        if (lastHost != null) 'lastHost': lastHost,
        if (lastPort != null) 'lastPort': lastPort,
      };

  static KnownPeer? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['deviceId'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final color = json['color'];
    final seen = json['lastSeen'];
    final host = json['lastHost'];
    final port = json['lastPort'];
    return KnownPeer(
      deviceId: id,
      name: name,
      color: color is int ? color : 0xFF5865F2,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(seen is int ? seen : 0),
      lastHost: host is String ? host : null,
      lastPort: port is int ? port : null,
    );
  }
}
