import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/peer.dart';
import '../models/profile.dart';

/// 端末内保存（プロフィール・最近の接続・設定）。
class StorageService {
  StorageService._(this._prefs, this._profile, this._peers);

  static const _kProfile = 'profile';
  static const _kPeers = 'known_peers';
  static const _kAutoJoin = 'auto_join';
  static const _kNoiseSuppression = 'noise_suppression';
  static const _kEchoCancellation = 'echo_cancellation';
  static const _kAutoGainControl = 'auto_gain_control';
  static const _kNoiseGateEnabled = 'noise_gate_enabled';
  static const _kNoiseGateThreshold = 'noise_gate_threshold';
  static const _maxPeers = 20;

  final SharedPreferences _prefs;
  Profile _profile;
  final List<KnownPeer> _peers;

  static Future<StorageService> load() async {
    final prefs = await SharedPreferences.getInstance();

    Profile? profile;
    final rawProfile = prefs.getString(_kProfile);
    if (rawProfile != null) {
      try {
        profile = Profile.fromJson(jsonDecode(rawProfile) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (profile == null) {
      profile = Profile.generate();
      await prefs.setString(_kProfile, jsonEncode(profile.toJson()));
    }

    final peers = <KnownPeer>[];
    final rawPeers = prefs.getString(_kPeers);
    if (rawPeers != null) {
      try {
        for (final e in jsonDecode(rawPeers) as List) {
          final p = KnownPeer.fromJson(e);
          if (p != null) peers.add(p);
        }
      } catch (_) {}
    }
    return StorageService._(prefs, profile, peers);
  }

  // ---- プロフィール ----
  Profile get profile => _profile;

  Future<void> saveProfile(Profile p) async {
    _profile = p;
    await _prefs.setString(_kProfile, jsonEncode(p.toJson()));
  }

  // ---- 最近の接続（F-07） ----
  /// 新しい順。
  List<KnownPeer> get knownPeers {
    final list = List<KnownPeer>.of(_peers);
    list.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  bool isKnown(String deviceId) => _peers.any((p) => p.deviceId == deviceId);

  Future<void> upsertKnownPeer(KnownPeer peer) async {
    final i = _peers.indexWhere((p) => p.deviceId == peer.deviceId);
    if (i >= 0) {
      _peers[i] = _peers[i].mergeWith(peer);
    } else {
      _peers.add(peer);
    }
    if (_peers.length > _maxPeers) {
      _peers.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      _peers.removeRange(_maxPeers, _peers.length);
    }
    await _savePeers();
  }

  Future<void> removeKnownPeer(String deviceId) async {
    _peers.removeWhere((p) => p.deviceId == deviceId);
    await _savePeers();
  }

  Future<void> clearKnownPeers() async {
    _peers.clear();
    await _savePeers();
  }

  Future<void> _savePeers() =>
      _prefs.setString(_kPeers, jsonEncode(_peers.map((p) => p.toJson()).toList()));

  // ---- 設定 ----
  /// 自動参加（F-09）。既定OFF。
  bool get autoJoin => _prefs.getBool(_kAutoJoin) ?? false;
  Future<void> setAutoJoin(bool v) => _prefs.setBool(_kAutoJoin, v);

  /// 音声処理（F-32）。すべて既定ON。
  bool get noiseSuppression => _prefs.getBool(_kNoiseSuppression) ?? true;
  Future<void> setNoiseSuppression(bool v) => _prefs.setBool(_kNoiseSuppression, v);

  bool get echoCancellation => _prefs.getBool(_kEchoCancellation) ?? true;
  Future<void> setEchoCancellation(bool v) => _prefs.setBool(_kEchoCancellation, v);

  bool get autoGainControl => _prefs.getBool(_kAutoGainControl) ?? true;
  Future<void> setAutoGainControl(bool v) => _prefs.setBool(_kAutoGainControl, v);

  /// ノイズゲート（入力感度 F-33）。既定ON、しきい値 0.04。
  bool get noiseGateEnabled => _prefs.getBool(_kNoiseGateEnabled) ?? true;
  Future<void> setNoiseGateEnabled(bool v) => _prefs.setBool(_kNoiseGateEnabled, v);

  double get noiseGateThreshold => _prefs.getDouble(_kNoiseGateThreshold) ?? 0.04;
  Future<void> setNoiseGateThreshold(double v) =>
      _prefs.setBool(_kNoiseGateEnabled, noiseGateEnabled).then(
            (_) => _prefs.setDouble(_kNoiseGateThreshold, v.clamp(0.01, 0.35)),
          );
}
