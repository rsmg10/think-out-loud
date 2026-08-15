import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'audio_monitoring_service.dart';
import 'audio_route.dart';

/// Talks to the native audio engine (Android Kotlin/AAudio,
/// iOS Swift/AVAudioEngine) over a MethodChannel for control and an
/// EventChannel for level/route/interruption events. All PCM handling
/// stays in native code per docs/audio-architecture.md — nothing here
/// touches sample data.
class NativeAudioMonitoringService implements AudioMonitoringService {
  static const MethodChannel _methodChannel = MethodChannel(
    'think_out_loud/audio_engine',
  );
  static const EventChannel _eventChannel = EventChannel(
    'think_out_loud/audio_engine/events',
  );

  final _levelController = StreamController<double>.broadcast();
  final _routeController = StreamController<AudioRoute>.broadcast();
  final _interruptionController =
      StreamController<MonitoringInterruption>.broadcast();
  final _resumedController = StreamController<void>.broadcast();

  StreamSubscription<dynamic>? _eventSub;

  NativeAudioMonitoringService() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(_onEvent);
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    switch (type) {
      case 'level':
        final level = (event['level'] as num?)?.toDouble() ?? 0.0;
        _levelController.add(level.clamp(0.0, 1.0));
      case 'route':
        _routeController.add(_routeFromString(event['route'] as String?));
      case 'interruption':
        final reason = _reasonFromString(event['reason'] as String?);
        _interruptionController.add(
          MonitoringInterruption(reason, DateTime.now()),
        );
      case 'resumed':
        _resumedController.add(null);
    }
  }

  AudioRoute _routeFromString(String? value) {
    switch (value) {
      case 'headphones':
        return AudioRoute.headphones;
      case 'bluetooth':
        return AudioRoute.bluetooth;
      case 'speaker':
        return AudioRoute.speaker;
      default:
        return AudioRoute.unknown;
    }
  }

  InterruptionReason _reasonFromString(String? value) {
    switch (value) {
      case 'bluetoothDisconnected':
        return InterruptionReason.bluetoothDisconnected;
      case 'routeBecameUnsafe':
        return InterruptionReason.routeBecameUnsafe;
      default:
        return InterruptionReason.systemAudioInterruption;
    }
  }

  @override
  Stream<double> get levelStream => _levelController.stream;

  @override
  Stream<AudioRoute> get routeChanges => _routeController.stream;

  @override
  Stream<MonitoringInterruption> get interruptions =>
      _interruptionController.stream;

  @override
  Stream<void> get resumed => _resumedController.stream;

  @override
  Future<bool> hasMicPermission() async {
    return (await Permission.microphone.status).isGranted;
  }

  @override
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<AudioRoute> currentRoute() async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'currentRoute',
      );
      return _routeFromString(result);
    } on PlatformException {
      return AudioRoute.unknown;
    }
  }

  @override
  Future<void> start(String outputFilePath) async {
    if (!await hasMicPermission() && !await requestMicPermission()) {
      throw const AudioEngineException(
        AudioEngineErrorType.permissionDenied,
        'Microphone permission is required to start monitoring.',
      );
    }
    final route = await currentRoute();
    if (!route.isSafeForMonitoring) {
      throw const AudioEngineException(
        AudioEngineErrorType.noSafeRoute,
        'No headphone route detected — monitoring via speaker would cause feedback.',
      );
    }
    // Capturing input from a Bluetooth headset's mic requires bringing
    // up the SCO link natively, which on Android 12+ needs the runtime
    // BLUETOOTH_CONNECT permission — request it up front so the native
    // SCO negotiation in AudioEngine.kt doesn't fail on a missing grant.
    if (route == AudioRoute.bluetooth) {
      final bluetoothStatus = await Permission.bluetoothConnect.status;
      if (!bluetoothStatus.isGranted &&
          !(await Permission.bluetoothConnect.request()).isGranted) {
        throw const AudioEngineException(
          AudioEngineErrorType.permissionDenied,
          "Bluetooth permission is required to use your headphones' microphone.",
        );
      }
    }
    try {
      await _methodChannel.invokeMethod('start', {
        'outputPath': outputFilePath,
      });
    } on PlatformException catch (e) {
      if (e.code == 'permission_denied') {
        throw AudioEngineException(
          AudioEngineErrorType.permissionDenied,
          e.message ?? 'Permission is required to start monitoring.',
        );
      }
      throw AudioEngineException(
        AudioEngineErrorType.engineFailure,
        e.message ?? 'Native audio engine failed to start.',
      );
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stop');
    } on PlatformException catch (e) {
      throw AudioEngineException(
        AudioEngineErrorType.engineFailure,
        e.message ?? 'Native audio engine failed to stop cleanly.',
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _levelController.close();
    await _routeController.close();
    await _interruptionController.close();
    await _resumedController.close();
  }
}
