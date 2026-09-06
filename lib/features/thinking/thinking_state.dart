import 'package:flutter/foundation.dart';

import '../../services/audio/audio_monitoring_service.dart';
import '../../services/audio/audio_route.dart';
import '../sessions/thinking_session.dart';

/// idle -> starting -> thinking -> stopping -> saved
///                         \-> interrupted -> thinking | idle
/// per docs/session-model.md.
enum ThinkingPhase { idle, starting, thinking, stopping, saved, interrupted }

@immutable
class ThinkingUiState {
  final ThinkingPhase phase;
  final DateTime? startedAt;
  final Duration elapsed;
  final double level;
  final AudioRoute route;
  final InterruptionReason? interruptionReason;
  final AudioEngineException? error;
  final ThinkingSession? savedSession;

  /// Whether the current/most recent start attempt is using the
  /// Bluetooth headset's mic (vs. the phone's own mic) — read from
  /// UserPreferencesService at start(). Only meaningful in combination
  /// with `route == AudioRoute.bluetooth`.
  final bool useBluetoothMic;

  /// Whether the current/most recent session is running the live
  /// mic-to-headphone audio echo — read from UserPreferencesService at
  /// start(). When false, no headphones are required, no route safety
  /// check applies, and `level`/`route` stay at their defaults since no
  /// monitoring engine is running (transcription runs independently).
  final bool liveEchoEnabled;

  const ThinkingUiState({
    this.phase = ThinkingPhase.idle,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.level = 0.0,
    this.route = AudioRoute.unknown,
    this.interruptionReason,
    this.error,
    this.savedSession,
    this.useBluetoothMic = true,
    this.liveEchoEnabled = true,
  });

  ThinkingUiState copyWith({
    ThinkingPhase? phase,
    DateTime? startedAt,
    Duration? elapsed,
    double? level,
    AudioRoute? route,
    InterruptionReason? interruptionReason,
    AudioEngineException? error,
    ThinkingSession? savedSession,
    bool? useBluetoothMic,
    bool? liveEchoEnabled,
    bool clearError = false,
    bool clearInterruption = false,
    bool clearSavedSession = false,
  }) {
    return ThinkingUiState(
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      elapsed: elapsed ?? this.elapsed,
      level: level ?? this.level,
      route: route ?? this.route,
      interruptionReason: clearInterruption
          ? null
          : (interruptionReason ?? this.interruptionReason),
      error: clearError ? null : (error ?? this.error),
      savedSession: clearSavedSession
          ? null
          : (savedSession ?? this.savedSession),
      useBluetoothMic: useBluetoothMic ?? this.useBluetoothMic,
      liveEchoEnabled: liveEchoEnabled ?? this.liveEchoEnabled,
    );
  }
}
