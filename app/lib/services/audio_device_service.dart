import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// 音声出力先の情報（F-20〜F-24）。
class AudioOutputOption {
  const AudioOutputOption({
    required this.kind,
    required this.name,
    required this.active,
  });

  /// 'speaker' | 'earpiece' | 'wired' | 'bluetooth'
  final String kind;
  final String name;
  final bool active;

  static AudioOutputOption? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    final name = raw['name'];
    if (kind is! String || name is! String) return null;
    return AudioOutputOption(
      kind: kind,
      name: name,
      active: raw['active'] == true,
    );
  }
}

/// 音声出力先の切替（BT自動切替含む）およびマイク・録音テスト（F-35, F-36）を担当するサービス。
class AudioDeviceService extends ChangeNotifier {
  AudioDeviceService() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const MethodChannel _channel = MethodChannel('intercom/audio');

  List<AudioOutputOption> _outputs = const [
    AudioOutputOption(kind: 'speaker', name: 'スピーカー', active: true),
    AudioOutputOption(kind: 'earpiece', name: '受話口 (耳元)', active: false),
  ];
  String _activeKind = 'speaker';
  String _previousNonHeadsetKind = 'speaker';
  bool _hadBluetooth = false;
  bool _hadWired = false;

  // マイク・録音テスト状態（F-35, F-36）
  bool _isMicTesting = false;
  bool _isRecordingFile = false;
  double _testLevel = 0.0;
  bool _testGateOpen = true;
  bool _hasRecording = false;
  int _recordingDurationMs = 0;
  bool _isPlayingRecording = false;

  List<AudioOutputOption> get outputs => _outputs;
  String get activeKind => _activeKind;

  AudioOutputOption get activeOutput {
    for (final o in _outputs) {
      if (o.kind == _activeKind) return o;
    }
    return _outputs.first;
  }

  bool get isMicTesting => _isMicTesting;
  bool get isRecordingFile => _isRecordingFile;
  double get testLevel => _testLevel;
  bool get testGateOpen => _testGateOpen;
  bool get hasRecording => _hasRecording;
  int get recordingDurationMs => _recordingDurationMs;
  bool get isPlayingRecording => _isPlayingRecording;

  Future<void> refreshOutputs({bool allowAutoSwitch = false}) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listAudioOutputs');
      if (raw != null) {
        _applyOutputsList(raw, allowAutoSwitch: allowAutoSwitch);
      }
    } catch (e) {
      debugPrint('[audio] listAudioOutputs error: $e');
    }
  }

  void _applyOutputsList(List<Object?> raw, {required bool allowAutoSwitch}) {
    final parsed = <AudioOutputOption>[];
    for (final item in raw) {
      final opt = AudioOutputOption.fromMap(item);
      if (opt != null) parsed.add(opt);
    }
    if (parsed.isEmpty) return;

    final hasBt = parsed.any((o) => o.kind == 'bluetooth');
    final hasWired = parsed.any((o) => o.kind == 'wired');

    // F-21 / F-22: ヘッドセット接続時の自動切替と切断時の自動復帰
    if (allowAutoSwitch) {
      if (hasBt && !_hadBluetooth) {
        _hadBluetooth = true;
        _hadWired = hasWired;
        _outputs = parsed;
        selectOutput('bluetooth');
        return;
      } else if (hasWired && !_hadWired && _activeKind != 'bluetooth') {
        _hadWired = true;
        _hadBluetooth = hasBt;
        _outputs = parsed;
        selectOutput('wired');
        return;
      } else if (!hasBt && _hadBluetooth && _activeKind == 'bluetooth') {
        _hadBluetooth = false;
        _hadWired = hasWired;
        _outputs = parsed;
        selectOutput(hasWired ? 'wired' : _previousNonHeadsetKind);
        return;
      } else if (!hasWired && _hadWired && _activeKind == 'wired') {
        _hadWired = false;
        _hadBluetooth = hasBt;
        _outputs = parsed;
        selectOutput(hasBt ? 'bluetooth' : _previousNonHeadsetKind);
        return;
      }
    }

    _hadBluetooth = hasBt;
    _hadWired = hasWired;

    // 選択中のデバイスが一覧に存在しなければスピーカーへ戻す
    if (!parsed.any((o) => o.kind == _activeKind)) {
      _activeKind = 'speaker';
    }

    _outputs = [
      for (final o in parsed)
        AudioOutputOption(
          kind: o.kind,
          name: o.name,
          active: o.kind == _activeKind,
        ),
    ];
    notifyListeners();
  }

  /// 出力先を切り替える（F-20）。
  Future<void> selectOutput(String kind) async {
    if (kind == 'speaker' || kind == 'earpiece') {
      _previousNonHeadsetKind = kind;
    }
    _activeKind = kind;
    _outputs = [
      for (final o in _outputs)
        AudioOutputOption(
          kind: o.kind,
          name: o.name,
          active: o.kind == kind,
        ),
    ];
    notifyListeners();

    try {
      await Helper.setSpeakerphoneOn(kind == 'speaker');
    } catch (_) {}

    try {
      await _channel.invokeMethod<bool>('selectAudioOutput', {'kind': kind});
    } catch (e) {
      debugPrint('[audio] selectAudioOutput error: $e');
    }
  }

  /// 通話開始時に最適な出力先を自動選択する（BT接続中ならBT、有線なら有線、なければスピーカー）。
  Future<void> applyInitialCallRoute() async {
    await refreshOutputs(allowAutoSwitch: false);
    if (_outputs.any((o) => o.kind == 'bluetooth')) {
      await selectOutput('bluetooth');
    } else if (_outputs.any((o) => o.kind == 'wired')) {
      await selectOutput('wired');
    } else {
      await selectOutput(_previousNonHeadsetKind);
    }
  }

  // ---- マイクテスト & 録音テスト (F-35, F-36) ----
  Future<void> startMicTest({
    required bool recordToFile,
    required bool noiseSuppression,
    required bool echoCancellation,
    required bool autoGainControl,
    required bool noiseGateEnabled,
    required double noiseGateThreshold,
  }) async {
    await Permission.microphone.request();
    _isMicTesting = true;
    _isRecordingFile = recordToFile;
    _testLevel = 0.0;
    _testGateOpen = true;
    _isPlayingRecording = false;
    notifyListeners();

    try {
      await _channel.invokeMethod<bool>('startMicTest', {
        'recordToFile': recordToFile,
        'noiseSuppression': noiseSuppression,
        'echoCancellation': echoCancellation,
        'autoGainControl': autoGainControl,
        'noiseGateEnabled': noiseGateEnabled,
        'noiseGateThreshold': noiseGateThreshold,
      });
    } catch (e) {
      _isMicTesting = false;
      _isRecordingFile = false;
      notifyListeners();
    }
  }

  Future<void> updateMicTestGate({
    required bool noiseGateEnabled,
    required double noiseGateThreshold,
  }) async {
    if (!_isMicTesting) return;
    try {
      await _channel.invokeMethod<bool>('updateMicTestGate', {
        'noiseGateEnabled': noiseGateEnabled,
        'noiseGateThreshold': noiseGateThreshold,
      });
    } catch (_) {}
  }

  Future<void> stopMicTest() async {
    if (!_isMicTesting) return;
    _isMicTesting = false;
    _isRecordingFile = false;
    _testLevel = 0.0;
    notifyListeners();

    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>('stopMicTest');
      if (res != null) {
        _hasRecording = res['hasRecording'] == true;
        final dur = res['durationMs'];
        _recordingDurationMs = dur is int ? dur : 0;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> playRecordedTest() async {
    if (_isMicTesting) {
      await stopMicTest();
    }
    try {
      final ok = await _channel.invokeMethod<bool>('playRecordedTest') ?? false;
      _isPlayingRecording = ok;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopPlayback() async {
    _isPlayingRecording = false;
    notifyListeners();
    try {
      await _channel.invokeMethod<bool>('stopPlayback');
    } catch (_) {}
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAudioDevicesChanged':
        final args = call.arguments;
        if (args is List<Object?>) {
          _applyOutputsList(args, allowAutoSwitch: true);
        }
      case 'onMicTestLevel':
        final args = call.arguments;
        if (args is Map && _isMicTesting) {
          final lvl = args['level'];
          _testLevel = lvl is num ? lvl.toDouble() : 0.0;
          _testGateOpen = args['gateOpen'] == true;
          notifyListeners();
        }
      case 'onPlaybackCompleted':
        _isPlayingRecording = false;
        notifyListeners();
    }
  }
}
