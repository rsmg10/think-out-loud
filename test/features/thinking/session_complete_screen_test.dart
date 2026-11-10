import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/providers.dart';
import 'package:think_out_loud/core/theme/app_theme.dart';
import 'package:think_out_loud/features/reflection/reflection_service.dart';
import 'package:think_out_loud/features/session_details/session_details_screen.dart';
import 'package:think_out_loud/features/sessions/session_repository.dart';
import 'package:think_out_loud/features/sessions/thinking_session.dart';
import 'package:think_out_loud/features/thinking/session_complete_screen.dart';
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

class _FakeSessionRepository implements SessionRepository {
  final Map<String, ThinkingSession> _sessions = {};

  _FakeSessionRepository(ThinkingSession seed) {
    _sessions[seed.id] = seed;
  }

  @override
  Future<void> save(ThinkingSession session) async =>
      _sessions[session.id] = session;
  @override
  Future<ThinkingSession?> getById(String id) async => _sessions[id];
  @override
  Future<List<ThinkingSession>> listAll() async => _sessions.values.toList();
  @override
  Future<void> delete(String id) async => _sessions.remove(id);
  @override
  Future<void> deleteAll() async => _sessions.clear();
}

/// Pinned in the `saved` phase, as it is when Session Complete appears.
class _SavedController extends ThinkingController {
  _SavedController(SessionRepository repository, ThinkingSession session)
    : super(
        _InertAudioMonitoringService(),
        repository,
        AudioFileStorage(),
        _InertUserPreferencesService(),
        _InertTranscriptionService(),
        _InertReflectionService(),
      ) {
    state = ThinkingUiState(phase: ThinkingPhase.saved, savedSession: session);
  }
}

ThinkingSession _session({
  required AiProcessingStatus status,
  String? transcript,
  String? audioReference,
}) {
  final start = DateTime(2026, 1, 1, 9);
  return ThinkingSession(
    id: 's1',
    createdAt: start,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 5)),
    duration: const Duration(minutes: 5),
    transcript: transcript,
    audioReference: audioReference,
    status: status,
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  ThinkingSession session,
) async {
  final repository = _FakeSessionRepository(session);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repository),
        thinkingControllerProvider.overrideWith(
          (ref) => _SavedController(repository, session),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SessionCompleteScreen(session: session),
                ),
              ),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('home'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(SessionCompleteScreen)),
  );
}

void main() {
  testWidgets(
    'a session with a transcript links straight to its reflection, and Back '
    'from Details returns home',
    (tester) async {
      final container = await _pump(
        tester,
        _session(
          status: AiProcessingStatus.pending,
          transcript: 'I should call Sam.',
        ),
      );

      expect(find.textContaining('reflection is being prepared'), findsOneWidget);
      await tester.tap(find.text('See your reflection'));
      // Details polls and animates its skeleton while pending, so pump a
      // fixed amount rather than pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SessionDetailsScreen), findsOneWidget);
      expect(find.byKey(const Key('reflection_skeleton')), findsOneWidget);
      expect(
        container.read(thinkingControllerProvider).phase,
        ThinkingPhase.idle,
      );

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SessionCompleteScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);

      // Dispose Details' poll timer.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a session without speech says so and offers no reflection link',
    (tester) async {
      final container = await _pump(
        tester,
        _session(status: AiProcessingStatus.notProcessed),
      );

      expect(find.textContaining('No speech was picked up'), findsOneWidget);
      expect(find.text('See your reflection'), findsNothing);
      // No audio either (echo was off), so there's nothing to view.
      expect(find.text('View session'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(
        container.read(thinkingControllerProvider).phase,
        ThinkingPhase.idle,
      );
    },
  );

  testWidgets('a speechless session with audio still offers View session', (
    tester,
  ) async {
    await _pump(
      tester,
      _session(
        status: AiProcessingStatus.notProcessed,
        audioReference: '/tmp/s1.m4a',
      ),
    );
    expect(find.text('View session'), findsOneWidget);
  });
}
