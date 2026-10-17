import 'dart:io';

/// この端末のIPv4アドレス一覧（ループバック除く）。手動接続の案内用。
Future<List<String>> localIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final iface in interfaces)
        for (final addr in iface.addresses) addr.address,
    ];
  } catch (_) {
    return const [];
  }
}
