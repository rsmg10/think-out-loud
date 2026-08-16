import 'audio_route.dart';

enum AudioEngineErrorType {
  permissionDenied,
  noSafeRoute,
  engineFailure,
  unsupportedPlatform,
  storageFailure,
}

class AudioEngineException implements Exception {
  final AudioEngineErrorType type;
  final String message;

  const AudioEngineException(this.type, this.message);

  @override
  String toString() => 'AudioEngineException($type, $message)';
}

enum InterruptionReason {
  bluetoothDisconnected,
  systemAudioInterruption,
  routeBecameUnsafe,
}

class MonitoringInterruption {
  final InterruptionReason reason;
  final DateTime at;

  const MonitoringInterruption(this.reason, this.at);
}

/// Controls the native low-latency input-to-output audio tap described in
/// docs/audio-architecture.md. Implementations must route raw audio frames
/// entirely inside native code — this interface only starts/stops the
/// engine and reads levels/route/interruptions, it never touches PCM data.
abstract class AudioMonitoringService {
  /// Emits normalized (0.0-1.0) input levels while monitoring, for the
  /// waveform visualizer. Not used for any audio processing.
  Stream<double> get levelStream;

  Stream<AudioRoute> get routeChanges;

  Stream<MonitoringInterruption> get interruptions;

  /// Emitted when a previously-interrupted session can resume.
  Stream<void> get resumed;

  Future<bool> hasMicPermission();

  /// Requests mic permission. Returns false if denied — callers should
  /// direct the user to system settings for recovery, per
  /// docs/audio-architecture.md.
  Future<bool> requestMicPermission();

  Future<AudioRoute> currentRoute();

  /// Starts the native monitoring engine, recording to [outputFilePath] so
  /// the session can be played back later. Throws [AudioEngineException]
  /// if permission is missing, no safe route is available, or the native
  /// engine fails to start.
  ///
  /// [useBluetoothMic] controls what happens when the route is
  /// Bluetooth: true (default behavior) negotiates SCO to capture from
  /// the headset's own mic; false uses the phone's mic while still
  /// playing output through the Bluetooth device via A2DP. See
  /// UserPreferencesService for why this needs to be a user choice
  /// rather than something the engine decides — SCO is the only way to
  /// get Bluetooth mic input, but it's lower quality and higher latency
  /// than the phone's mic.
  Future<void> start(String outputFilePath, {bool useBluetoothMic = true});

  Future<void> stop();

  Future<void> dispose();
}
