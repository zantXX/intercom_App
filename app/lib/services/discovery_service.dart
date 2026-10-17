import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

import '../models/room.dart';

/// mDNS（DNS-SD）によるルームの公開・検出。
class DiscoveryService extends ChangeNotifier {
  Discovery? _discovery;
  Registration? _registration;
  RoomAdvert? _advert;
  String? _selfDeviceId;
  final Map<String, RoomInfo> _rooms = {};

  bool _browsing = false;
  String? _lastError;

  bool get browsing => _browsing;
  String? get lastError => _lastError;
  List<RoomInfo> get rooms => _rooms.values.toList();

  /// ルームの検出を開始する（ホーム画面を開いている間だけ動かす）。
  Future<void> startBrowsing(String selfDeviceId) async {
    if (_discovery != null) return;
    _selfDeviceId = selfDeviceId;
    try {
      final d = await startDiscovery(kServiceType, ipLookupType: IpLookupType.v4);
      d.addServiceListener(_onService);
      _discovery = d;
      _browsing = true;
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
      debugPrint('[discovery] start failed: $e');
    }
    notifyListeners();
  }

  void _onService(Service service, ServiceStatus status) {
    final key = service.name;
    if (key == null) return;
    if (status == ServiceStatus.found) {
      final room = RoomInfo.fromService(service);
      if (room == null || room.hostDeviceId == _selfDeviceId) return;
      _rooms[key] = room;
    } else {
      _rooms.remove(key);
    }
    notifyListeners();
  }

  Future<void> stopBrowsing() async {
    final d = _discovery;
    _discovery = null;
    _browsing = false;
    _rooms.clear();
    if (d != null) {
      try {
        await stopDiscovery(d);
      } catch (e) {
        debugPrint('[discovery] stop failed: $e');
      }
    }
    notifyListeners();
  }

  /// 自分のルームを公開する。
  Future<void> advertise(RoomAdvert advert) async {
    await stopAdvertising();
    _advert = advert;
    try {
      _registration = await register(advert.toService());
    } catch (e) {
      _lastError = '$e';
      debugPrint('[discovery] register failed: $e');
    }
  }

  /// 参加人数が変わったら公開し直す（TXTレコードの n を更新）。
  Future<void> updateAdvertCount(int count) async {
    final a = _advert;
    if (a == null || a.count == count) return;
    await advertise(a.withCount(count));
  }

  Future<void> stopAdvertising() async {
    final r = _registration;
    _registration = null;
    _advert = null;
    if (r != null) {
      try {
        await unregister(r);
      } catch (e) {
        debugPrint('[discovery] unregister failed: $e');
      }
    }
  }
}
