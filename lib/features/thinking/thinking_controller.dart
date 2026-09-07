import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../services/audio/audio_monitoring_service.dart';
import '../../services/audio/audio_route.dart';
import '../../services/settings/user_preferences_service.dart';
import '../../services/storage/audio_file_storage.dart';
import '../../services/transcription/transcription_service.dart';
import '../reflection/reflection_service.dart';
import '../sessions/session_repository.dart';
import '../sessions/thinking_session.dart';
import 'thinking_state.dart';

const _uuid = Uuid();

/// Owns the idle -> starting -> thinking -> stopping -> saved state
/// machine (plus the interrupted branch) described in
/// docs/session-model.md. UI screens read [state] and call
/// start/stop/resume/cancel — none of them touch the audio service or
/// repository directly.
class ThinkingController extends StateNotifier<ThinkingUiState> {
  final AudioMonitoringService _audio;
  final SessionRepository _repository;
  final AudioFileStorage _audioStorage;
  final UserPreferencesService _preferences;
  final TranscriptionService _transcription;
  final ReflectionService _reflection;

  StreamSubscription<double>? _levelSub;
  StreamSubscription<AudioRoute>? _routeSub;
  StreamSubscription<MonitoringInterruption>? _interruptionSub;
  StreamSubscription<void>? _resumedSub;
  Timer? _ticker;

  String? _sessionId;
  String? _audioPath;
  DateTime? _createdAt;
  DateTime? _phaseStartedAt;
  Duration _accumulated = Duration.zero;
  bool _useBluetoothMic = true;
  bool _liveEchoEnabled = true;

  ThinkingController(
    this._audio,
    this._repository,
    this._audioStorage,
    this._preferences,
    this._transcription,
    this._reflection,
  ) : super(const ThinkingUiState()) {
    _routeSub = _audio.routeChanges.listen(_onRouteChanged);
    _interruptionSub = _audio.interruptions.listen(_onInterruption);
    _resumedSub = _audio.resumed.listen((_) => _onNativeResumed());
  }

  Future<void> start() async {
    state = const ThinkingUiState(phase: ThinkingPhase.starting);
    _sessionId = _uuid.v4();
    _createdAt = DateTime.now();
    _useBluetoothMic = await _preferences.getPreferBluetoothMic();
    _liveEchoEnabled = await _preferences.getLiveEchoEnabled();
    state = state.copyWith(liveEchoEnabled: _liveEchoEnabled);

    if (_liveEchoEnabled) {
      // Fetched up front (rather than left at the default `unknown`) so
      // the UI can show "Connecting to your headphones…" during a
      // Bluetooth SCO handshake instead of a bare spinner that looks
      // stuck. Only meaningful when the live echo will actually run.
      final startingRoute = await _audio.currentRoute();
      state = state.copyWith(
        route: startingRoute,
        useBluetoothMic: _useBluetoothMic,
      );
      try {
        _audioPath = await _audioStorage.newAudioPath(_sessionId!);
      } catch (e) {
        state = ThinkingUiState(
          phase: ThinkingPhase.idle,
          error: AudioEngineException(
            AudioEngineErrorType.storageFailure,
            'Could not prepare local storage for this session: $e',
          ),
        );
        return;
      }
      try {
        await _audio.start(_audioPath!, useBluetoothMic: _useBluetoothMic);
      } on AudioEngineException catch (e) {
        state = ThinkingUiState(phase: ThinkingPhase.idle, error: e);
        return;
      }
    } else {
      // No monitoring engine, no headphone/route requirement, no
      // recorded audio — the user is speaking straight at the phone.
      // Transcription still needs mic access, so ask for it directly
      // rather than relying on the (skipped) native engine's own check.
      if (!await _audio.hasMicPermission() && !await _audio.requestMicPermission()) {
        state = ThinkingUiState(
          phase: ThinkingPhase.idle,
          error: const AudioEngineException(
            AudioEngineErrorType.permissionDenied,
            'Microphone permission is required to capture this session.',
          ),
        );
        return;
      }
    }
    // Transcription is supplementary, not the core feature — a failure
    // here must never block or fail the actual thinking session.
    unawaited(_transcription.startLiveTranscription());
    _accumulated = Duration.zero;
    _phaseStartedAt = DateTime.now();
    _beginTicking();
    if (_liveEchoEnabled) {
      _levelSub = _audio.levelStream.listen(
        (level) => state = state.copyWith(level: level),
      );
    }
    state = ThinkingUiState(
      phase: ThinkingPhase.thinking,
      startedAt: _createdAt,
      liveEchoEnabled: _liveEchoEnabled,
    );
  }

  Future<void> stop() async {
    if (state.phase != ThinkingPhase.thinking &&
        state.phase != ThinkingPhase.interrupted) {
      return;
    }
    state = state.copyWith(phase: ThinkingPhase.stopping);
    _stopTicking();
    await _levelSub?.cancel();
    if (_liveEchoEnabled) {
      try {
        await _audio.stop();
      } on AudioEngineException catch (e) {
        state = state.copyWith(phase: ThinkingPhase.idle, error: e);
        return;
      }
    }
    final transcript = await _transcription.stopLiveTranscription();
    final duration = _accumulated;
    final session = ThinkingSession(
      id: _sessionId!,
      createdAt: _createdAt!,
      startedAt: _createdAt!,
      endedAt: DateTime.now(),
      duration: duration,
      audioReference: _audioPath,
      transcript: transcript,
    );
    try {
      await _repository.save(session);
    } catch (e) {
      state = state.copyWith(
        phase: ThinkingPhase.idle,
        error: const AudioEngineException(
          AudioEngineErrorType.storageFailure,
          'Could not save the session.',
        ),
      );
      return;
    }
    state = ThinkingUiState(phase: ThinkingPhase.saved, savedSession: session);
    if (transcript != null && transcript.trim().isNotEmpty) {
      // Fire-and-forget: reflection runs in the background regardless of
      // where the user navigates to next. Session Details reads whatever
      // is in the DB when it's opened, and polls while status is pending
      // (see SessionDetailsScreen) rather than this controller pushing
      // updates to a screen that may not even be mounted.
      unawaited(_processReflection(session));
    }
  }

  Future<void> _processReflection(ThinkingSession session) async {
    try {
      await _repository.save(
        session.copyWith(status: AiProcessingStatus.pending),
      );
    } catch (_) {
      return;
    }

    ReflectionResult? result;
    try {
      result = await _reflection.reflect(session.transcript!);
    } catch (_) {
      result = null;
    }

    final updated = result == null
        ? session.copyWith(status: AiProcessingStatus.failed)
        : session.copyWith(
            status: AiProcessingStatus.complete,
            summary: result.summary,
            keyIdeas: result.keyIdeas,
            actionPoints: result.actionPoints,
            actionPointsDone: const [],
            openQuestions: result.openQuestions,
          );
    try {
      await _repository.save(updated);
    } catch (_) {
      // Best-effort — if this save fails the session simply stays
      // "pending" in the DB, which Session Details already renders as a
      // (stalled) processing state rather than a crash.
    }
  }

  /// User acknowledged the completion screen — back to idle for a new
  /// session.
  void acknowledgeSaved() {
    _resetSessionFields();
    state = const ThinkingUiState();
  }

  Future<void> resumeAfterInterruption() async {
    if (state.phase != ThinkingPhase.interrupted) return;
    final route = await _audio.currentRoute();
    if (!route.isSafeForMonitoring) {
      // Still unsafe — stay interrupted, just refresh the reason.
      state = state.copyWith(
        route: route,
        interruptionReason: InterruptionReason.routeBecameUnsafe,
      );
      return;
    }
    try {
      await _audio.start(_audioPath!, useBluetoothMic: _useBluetoothMic);
    } on AudioEngineException catch (e) {
      state = state.copyWith(error: e);
      return;
    }
    _phaseStartedAt = DateTime.now();
    _beginTicking();
    state = state.copyWith(
      phase: ThinkingPhase.thinking,
      route: route,
      clearInterruption: true,
      clearError: true,
    );
  }

  /// User chose not to resume — discard the in-progress (unsaved) audio
  /// and go back to idle. Nothing was persisted yet since Stop was never
  /// pressed.
  Future<void> cancelFromInterruption() async {
    if (state.phase != ThinkingPhase.interrupted) return;
    await _transcription.stopLiveTranscription();
    if (_audioPath != null) {
      await _audioStorage.delete(_audioPath!);
    }
    _resetSessionFields();
    state = const ThinkingUiState();
  }

  void _onInterruption(MonitoringInterruption interruption) {
    if (state.phase != ThinkingPhase.thinking) return;
    _pauseForInterruption(interruption.reason);
  }

  void _onRouteChanged(AudioRoute route) {
    if (state.phase == ThinkingPhase.thinking && !route.isSafeForMonitoring) {
      _pauseForInterruption(InterruptionReason.routeBecameUnsafe);
    }
    state = state.copyWith(route: route);
  }

  void _pauseForInterruption(InterruptionReason reason) {
    _stopTicking();
    state = state.copyWith(
      phase: ThinkingPhase.interrupted,
      interruptionReason: reason,
    );
  }

  void _onNativeResumed() {
    // The platform signals the interruption itself has cleared (e.g. a
    // phone call ended). We still wait for the user to confirm resuming
    // via [resumeAfterInterruption] rather than silently restarting audio.
  }

  void _beginTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final since = DateTime.now().difference(_phaseStartedAt!);
      state = state.copyWith(elapsed: _accumulated + since);
    });
  }

  void _stopTicking() {
    if (_phaseStartedAt != null) {
      _accumulated += DateTime.now().difference(_phaseStartedAt!);
    }
    _ticker?.cancel();
    _ticker = null;
  }

  void _resetSessionFields() {
    _sessionId = null;
    _audioPath = null;
    _createdAt = null;
    _phaseStartedAt = null;
    _accumulated = Duration.zero;
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    _routeSub?.cancel();
    _interruptionSub?.cancel();
    _resumedSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
