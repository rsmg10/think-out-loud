import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/providers.dart';
import 'package:think_out_loud/core/theme/app_theme.dart';
import 'package:think_out_loud/features/patterns/patterns_screen.dart';
import 'package:think_out_loud/services/ai/memory_service.dart';

class _FakeMemoryService implements MemoryService {
  final List<String> themes;

  _FakeMemoryService(this.themes);

  @override
  Future<List<String>> recurringThemes() async => themes;

  @override
  Future<void> record(String sessionId, {List<String> themes = const []}) async {}
}

Future<void> _pumpPatterns(WidgetTester tester, MemoryService service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [memoryServiceProvider.overrideWithValue(service)],
      child: MaterialApp(theme: AppTheme.light(), home: const PatternsScreen()),
    ),
  );
}

void main() {
  testWidgets('a non-empty theme list renders each theme as bulleted content', (
    tester,
  ) async {
    await _pumpPatterns(
      tester,
      _FakeMemoryService(['Career direction', 'Work-life balance', 'Money worries']),
    );
    await tester.pumpAndSettle();

    expect(find.text('Career direction'), findsOneWidget);
    expect(find.text('Work-life balance'), findsOneWidget);
    expect(find.text('Money worries'), findsOneWidget);
  });

  testWidgets('an empty theme list renders the not-enough-sessions empty state', (
    tester,
  ) async {
    await _pumpPatterns(tester, _FakeMemoryService(const []));
    await tester.pumpAndSettle();

    expect(find.text('Nothing yet'), findsOneWidget);
    expect(
      find.textContaining('Not enough sessions yet to find patterns'),
      findsOneWidget,
    );
  });
}
