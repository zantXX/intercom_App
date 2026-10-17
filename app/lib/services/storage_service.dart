import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/peer.dart';
import '../models/profile.dart';

/// 端末内保存（プロフィール・最近の接続・設定）。
/// MethodChannel('intercom/audio') 経由でアプリ専用領域 (filesDir/intercom_store.json) に保存する。
class StorageService {
  StorageService._(this._data, this._profile, this._peers);

  static const MethodChannel _channel = MethodChannel('intercom/audio');

  static const _kProfile = 'profile';
  static const _kPeers = 'known_peers';
  static const _kAutoJoin = 'auto_join';
  static const _kNoiseSuppression = 'noise_suppression';
  static const _kEchoCancellation = 'echo_cancellation';
  static const _kAutoGainControl = 'auto_gain_control';
  static const _kNoiseGateEnabled = 'noise_gate_enabled';
  static const _kNoiseGateThreshold = 'noise_gate_threshold';
  static const _maxPeers = 20;

  final Map<String, dynamic> _data;
  Profile _profile;
  final List<KnownPeer> _peers;

  static Future<StorageService> load() async {
    Map<String, dynamic> data = <String, dynamic>{};
    try {
      final raw = await _channel.invokeMethod<String>('readStore');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      }
    } catch (_) {}

    Profile? profile;
    final rawProfile = data[_kProfile];
    if (rawProfile is Map<String, dynamic>) {
      profile = Profile.fromJson(rawProfile);
    }
    if (profile == null) {
      profile = Profile.generate();
      data[_kProfile] = profile.toJson();
    }

    final peers = <KnownPeer>[];
    final rawPeers = data[_kPeers];
    if (rawPeers is List) {
      for (final e in rawPeers) {
        final p = KnownPeer.fromJson(e);
        if (p != null) peers.add(p);
      }
    }

    final service = StorageService._(data, profile, peers);
    await service._flush();
    return service;
  }

  Future<void> _flush() async {
    try {
      await _channel.invokeMethod<bool>('writeStore', {
        'json': jsonEncode(_data),
      });
    } catch (_) {}
  }

  // ---- プロフィール ----
  Profile get profile => _profile;

  Future<void> saveProfile(Profile p) async {
    _profile = p;
    _data[_kProfile] = p.toJson();
    await _flush();
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

  Future<void> _savePeers() async {
    _data[_kPeers] = _peers.map((p) => p.toJson()).toList();
    await _flush();
  }

  // ---- 設定 ----
  /// 自動参加（F-09）。既定OFF。
  bool get autoJoin => _data[_kAutoJoin] == true;
  Future<void> setAutoJoin(bool v) async {
    _data[_kAutoJoin] = v;
    await _flush();
  }

  /// 音声処理（F-32）。すべて既定ON。
  bool get noiseSuppression => (_data[_kNoiseSuppression] as bool?) ?? true;
  Future<void> setNoiseSuppression(bool v) async {
    _data[_kNoiseSuppression] = v;
    await _flush();
  }

  bool get echoCancellation => (_data[_kEchoCancellation] as bool?) ?? true;
  Future<void> setEchoCancellation(bool v) async {
    _data[_kEchoCancellation] = v;
    await _flush();
  }

  bool get autoGainControl => (_data[_kAutoGainControl] as bool?) ?? true;
  Future<void> setAutoGainControl(bool v) async {
    _data[_kAutoGainControl] = v;
    await _flush();
  }

  /// ノイズゲート（入力感度 F-33）。既定ON、しきい値 0.04。
  bool get noiseGateEnabled => (_data[_kNoiseGateEnabled] as bool?) ?? true;
  Future<void> setNoiseGateEnabled(bool v) async {
    _data[_kNoiseGateEnabled] = v;
    await _flush();
  }

  double get noiseGateThreshold =>
      ((_data[_kNoiseGateThreshold] as num?)?.toDouble() ?? 0.04).clamp(0.01, 0.35);
  Future<void> setNoiseGateThreshold(double v) async {
    _data[_kNoiseGateThreshold] = v.clamp(0.01, 0.35);
    await _flush();
  }
}
