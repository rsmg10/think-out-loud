import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/providers.dart';
import 'package:think_out_loud/core/theme/app_theme.dart';
import 'package:think_out_loud/features/session_details/session_details_screen.dart';
import 'package:think_out_loud/features/sessions/session_repository.dart';
import 'package:think_out_loud/features/sessions/thinking_session.dart';

class _FakeSessionRepository implements SessionRepository {
  final Map<String, ThinkingSession> _sessions = {};
  final List<ThinkingSession> saved = [];

  _FakeSessionRepository(ThinkingSession seed) {
    _sessions[seed.id] = seed;
  }

  @override
  Future<void> save(ThinkingSession session) async {
    _sessions[session.id] = session;
    saved.add(session);
  }

  @override
  Future<ThinkingSession?> getById(String id) async => _sessions[id];

  @override
  Future<List<ThinkingSession>> listAll() async => _sessions.values.toList();

  @override
  Future<void> delete(String id) async => _sessions.remove(id);

  @override
  Future<void> deleteAll() async => _sessions.clear();
}

ThinkingSession _buildSession() {
  final start = DateTime(2026, 1, 1, 9);
  return ThinkingSession(
    id: 's1',
    createdAt: start,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 5)),
    duration: const Duration(minutes: 5),
    transcript: 'I should call Sam about the budget.',
    summary: 'Discussed the budget.',
    actionPoints: const ['Call Sam about the budget', 'Draft the proposal'],
    status: AiProcessingStatus.complete,
  );
}

ThinkingSession _buildPendingSession() {
  final start = DateTime(2026, 1, 1, 9);
  return ThinkingSession(
    id: 's1',
    createdAt: start,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 5)),
    duration: const Duration(minutes: 5),
    transcript: 'I should call Sam about the budget.',
    status: AiProcessingStatus.pending,
  );
}

Future<void> _pump(WidgetTester tester, _FakeSessionRepository repository) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SessionDetailsScreen(sessionId: 's1'),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'copying the summary writes it to the clipboard and confirms it',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await _pump(tester, _FakeSessionRepository(_buildSession()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.copy_outlined).first,
      );
      await tester.pump();

      final clipboardCalls = calls.where(
        (c) => c.method == 'Clipboard.setData',
      );
      expect(clipboardCalls, isNotEmpty);
      expect(
        (clipboardCalls.first.arguments as Map)['text'],
        'Discussed the budget.',
      );
      expect(find.text('Summary copied'), findsOneWidget);
    },
  );

  testWidgets(
    'checking an action point flips its style and persists the checklist',
    (tester) async {
      final repository = _FakeSessionRepository(_buildSession());
      await _pump(tester, repository);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(repository.saved, isNotEmpty);
      expect(repository.saved.last.actionPointsDone, [true, false]);

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(checkbox.value, isTrue);
    },
  );

  testWidgets(
    'a pending reflection shows the skeleton placeholder, not the old spinner/text',
    (tester) async {
      await _pump(tester, _FakeSessionRepository(_buildPendingSession()));
      // Deliberately not pumpAndSettle: the skeleton's pulse timer and the
      // screen's poll timer are both periodic and never "settle" — a few
      // zero-duration pumps are enough to let the FutureProvider resolve
      // without advancing the fake clock far enough to fire either timer.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('reflection_skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Reflecting on this session…'), findsNothing);

      // Unmount before the test ends so both periodic timers are
      // cancelled in dispose(), rather than left pending.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a calm mood renders its icon next to the header', (
    tester,
  ) async {
    final session = _buildSession().copyWith(mood: 'calm');
    await _pump(tester, _FakeSessionRepository(session));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.self_improvement_outlined), findsOneWidget);
  });
}
