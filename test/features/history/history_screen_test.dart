import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/providers.dart';
import 'package:think_out_loud/core/theme/app_theme.dart';
import 'package:think_out_loud/features/history/history_screen.dart';
import 'package:think_out_loud/features/sessions/session_repository.dart';
import 'package:think_out_loud/features/sessions/thinking_session.dart';

class _FakeSessionRepository implements SessionRepository {
  final List<ThinkingSession> sessions;

  _FakeSessionRepository(this.sessions);

  @override
  Future<void> save(ThinkingSession session) async {}
  @override
  Future<List<ThinkingSession>> listAll() async => sessions;
  @override
  Future<ThinkingSession?> getById(String id) async =>
      sessions.where((s) => s.id == id).firstOrNull;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> deleteAll() async {}
}

ThinkingSession _session({
  required String id,
  required String summary,
  required String transcript,
}) {
  final now = DateTime(2026, 1, 1, 9, 0);
  return ThinkingSession(
    id: id,
    createdAt: now,
    startedAt: now,
    endedAt: now.add(const Duration(minutes: 5)),
    duration: const Duration(minutes: 5),
    transcript: transcript,
    summary: summary,
  );
}

Future<void> _pumpHistory(
  WidgetTester tester,
  List<ThinkingSession> sessions,
) async {
  final repository = _FakeSessionRepository(sessions);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const HistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final sessions = [
    _session(
      id: '1',
      summary: 'Planning the product launch',
      transcript: 'We talked about timelines and budget.',
    ),
    _session(
      id: '2',
      summary: 'Morning reflection on habits',
      transcript: 'Thinking about waking up earlier.',
    ),
    _session(
      id: '3',
      summary: 'Debugging the audio pipeline',
      transcript: 'Latency was too high on Bluetooth.',
    ),
  ];

  testWidgets('shows all sessions with no query', (tester) async {
    await _pumpHistory(tester, sessions);

    expect(find.text('Planning the product launch'), findsOneWidget);
    expect(find.text('Morning reflection on habits'), findsOneWidget);
    expect(find.text('Debugging the audio pipeline'), findsOneWidget);
  });

  testWidgets('typing a query filters to only the matching session', (
    tester,
  ) async {
    await _pumpHistory(tester, sessions);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'launch');
    await tester.pumpAndSettle();

    expect(find.text('Planning the product launch'), findsOneWidget);
    expect(find.text('Morning reflection on habits'), findsNothing);
    expect(find.text('Debugging the audio pipeline'), findsNothing);
  });

  testWidgets('a query matching nothing shows the empty state', (
    tester,
  ) async {
    await _pumpHistory(tester, sessions);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nonexistent query xyz');
    await tester.pumpAndSettle();

    expect(find.text("No sessions match 'nonexistent query xyz'"), findsOneWidget);
    expect(find.text('Planning the product launch'), findsNothing);
  });

  testWidgets('clearing the query restores the full list', (tester) async {
    await _pumpHistory(tester, sessions);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'launch');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Planning the product launch'), findsOneWidget);
    expect(find.text('Morning reflection on habits'), findsOneWidget);
    expect(find.text('Debugging the audio pipeline'), findsOneWidget);
  });
}
