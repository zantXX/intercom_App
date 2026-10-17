import 'dart:math';

/// 端末内に保存する自分のプロフィール（アカウント登録は不要）。
class Profile {
  const Profile({required this.deviceId, required this.name, required this.color});

  /// 初回起動時に生成するランダムな端末ID。相手の識別に使う（IPは変わるため使わない）。
  final String deviceId;
  final String name;
  final int color;

  Profile copyWith({String? name, int? color}) =>
      Profile(deviceId: deviceId, name: name ?? this.name, color: color ?? this.color);

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'name': name, 'color': color};

  /// シグナリングで相手に送る形式。
  Map<String, dynamic> toPeerJson() => {'id': deviceId, 'name': name, 'color': color};

  static Profile? fromJson(Map<String, dynamic> json) {
    final id = json['deviceId'];
    final name = json['name'];
    final color = json['color'];
    if (id is! String || name is! String || color is! int) return null;
    return Profile(deviceId: id, name: name, color: color);
  }

  static Profile generate() {
    final rnd = Random.secure();
    return Profile(
      deviceId: randomHex(16),
      name: 'ライダー${rnd.nextInt(9000) + 1000}',
      color: avatarPalette[rnd.nextInt(avatarPalette.length)],
    );
  }
}

/// アイコン色の候補（Discord風）。
const List<int> avatarPalette = [
  0xFF5865F2, // blurple
  0xFF23A55A, // green
  0xFFF0B232, // yellow
  0xFFEB459E, // fuchsia
  0xFFED4245, // red
  0xFF00A8FC, // cyan
  0xFF9B59B6, // purple
  0xFFE67E22, // orange
];

String randomHex(int bytes) {
  final rnd = Random.secure();
  final sb = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    sb.write(rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
