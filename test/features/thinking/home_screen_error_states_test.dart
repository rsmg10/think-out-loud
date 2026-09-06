import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/providers.dart';
import 'package:think_out_loud/core/theme/app_theme.dart';
import 'package:think_out_loud/features/reflection/reflection_service.dart';
import 'package:think_out_loud/features/sessions/session_repository.dart';
import 'package:think_out_loud/features/sessions/thinking_session.dart';
import 'package:think_out_loud/features/thinking/home_screen.dart';
import 'package:think_out_loud/features/thinking/thinking_controller.dart';
import 'package:think_out_loud/features/thinking/thinking_state.dart';
import 'package:think_out_loud/services/audio/audio_monitoring_service.dart';
import 'package:think_out_loud/services/audio/audio_route.dart';
import 'package:think_out_loud/services/settings/user_preferences_service.dart';
import 'package:think_out_loud/services/storage/audio_file_storage.dart';
import 'package:think_out_loud/services/transcription/transcription_service.dart';

class _InertAudioMonitoringService implements AudioMonitoringService {
  @override
  Stream<double> get levelStream => const Stream.empty();
  @override
  Stream<AudioRoute> get routeChanges => const Stream.empty();
  @override
  Stream<MonitoringInterruption> get interruptions => const Stream.empty();
  @override
  Stream<void> get resumed => const Stream.empty();
  @override
  Future<bool> hasMicPermission() async => true;
  @override
  Future<bool> requestMicPermission() async => true;
  @override
  Future<AudioRoute> currentRoute() async => AudioRoute.headphones;
  @override
  Future<void> start(String outputFilePath, {bool useBluetoothMic = true}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _InertUserPreferencesService implements UserPreferencesService {
  @override
  Future<bool> getPreferBluetoothMic() async => true;
  @override
  Future<void> setPreferBluetoothMic(bool value) async {}
  @override
  Future<bool> getLiveEchoEnabled() async => true;
  @override
  Future<void> setLiveEchoEnabled(bool value) async {}
}

class _InertTranscriptionService implements TranscriptionService {
  @override
  Future<void> startLiveTranscription() async {}
  @override
  Future<String?> stopLiveTranscription() async => null;
}

class _InertReflectionService implements ReflectionService {
  @override
  Future<ReflectionResult?> reflect(String transcript) async => null;
}

class _InertSessionRepository implements SessionRepository {
  @override
  Future<void> save(ThinkingSession session) async {}
  @override
  Future<List<ThinkingSession>> listAll() async => const [];
  @override
  Future<ThinkingSession?> getById(String id) async => null;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> deleteAll() async {}
}

/// A controller that never actually starts anything — its state is
/// pinned to whatever [ThinkingUiState] the test hands it, so the UI's
/// reaction to each error type can be checked in isolation.
class _FixedErrorController extends ThinkingController {
  _FixedErrorController(ThinkingUiState fixedState)
    : super(
        _InertAudioMonitoringService(),
        _InertSessionRepository(),
        AudioFileStorage(),
        _InertUserPreferencesService(),
        _InertTranscriptionService(),
        _InertReflectionService(),
      ) {
    state = fixedState;
  }
}

Future<void> _pumpHomeWithError(
  WidgetTester tester,
  AudioEngineErrorType type,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        thinkingControllerProvider.overrideWith(
          (ref) => _FixedErrorController(
            ThinkingUiState(
              error: AudioEngineException(type, 'details for $type'),
            ),
          ),
        ),
        userPreferencesServiceProvider.overrideWithValue(
          _InertUserPreferencesService(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // docs/mvp-scope.md requires explicit error states for these four
  // cases — this checks the Home screen actually reaches a distinct,
  // recognizable state for each rather than a generic failure screen.
  testWidgets('permission denied reaches the microphone-access error state', (
    tester,
  ) async {
    await _pumpHomeWithError(tester, AudioEngineErrorType.permissionDenied);
    expect(find.text('Microphone access needed'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('no safe route reaches the headphones-needed error state', (
    tester,
  ) async {
    await _pumpHomeWithError(tester, AudioEngineErrorType.noSafeRoute);
    expect(find.text('Headphones needed'), findsOneWidget);
  });

  testWidgets('storage failure reaches a distinct storage error state', (
    tester,
  ) async {
    await _pumpHomeWithError(tester, AudioEngineErrorType.storageFailure);
    expect(find.text('Storage problem'), findsOneWidget);
  });

  testWidgets(
    'unexpected engine failure reaches a generic-but-explicit error state',
    (tester) async {
      await _pumpHomeWithError(tester, AudioEngineErrorType.engineFailure);
      expect(find.text('Something went wrong'), findsOneWidget);
    },
  );

  testWidgets('idle with no error shows the Think button, not an error state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          thinkingControllerProvider.overrideWith(
            (ref) => _FixedErrorController(const ThinkingUiState()),
          ),
          userPreferencesServiceProvider.overrideWithValue(
            _InertUserPreferencesService(),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Think'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });
}
