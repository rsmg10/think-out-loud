import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:think_out_loud/features/sessions/sqlite_session_repository.dart';
import 'package:think_out_loud/features/sessions/thinking_session.dart';
import 'package:think_out_loud/services/storage/app_database.dart';

ThinkingSession _session(String id, {DateTime? startedAt, String? audioReference}) {
  final start = startedAt ?? DateTime(2026, 1, 1, 9);
  return ThinkingSession(
    id: id,
    createdAt: start,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 5)),
    duration: const Duration(minutes: 5),
    audioReference: audioReference,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDatabase;
  late SqliteSessionRepository repository;

  setUp(() {
    // A fresh in-memory database per test — no state leaks between tests
    // and no real disk/platform channel involved, per docs/testing.md
    // priority #2 (session persistence).
    appDatabase = AppDatabase()
      ..factoryOverride = databaseFactoryFfi
      ..pathOverride = inMemoryDatabasePath;
    repository = SqliteSessionRepository(appDatabase);
  });

  tearDown(() => appDatabase.close());

  test('a saved session can be read back with all fields intact', () async {
    final session = _session(
      's1',
      audioReference: '/docs/session_audio/s1.wav',
    );

    await repository.save(session);
    final loaded = await repository.getById('s1');

    expect(loaded, isNotNull);
    expect(loaded!.id, session.id);
    expect(loaded.duration, session.duration);
    expect(loaded.audioReference, session.audioReference);
    expect(loaded.startedAt, session.startedAt);
    expect(loaded.endedAt, session.endedAt);
  });

  test('sessions survive a simulated app restart (close + reopen same file)', () async {
    // Uses a real temp file (not :memory:) so closing and reopening the
    // connection genuinely round-trips through disk, the way an app
    // restart would — this is docs/testing.md priority #2.
    final tempDir = await Directory.systemTemp.createTemp('think_out_loud_test');
    final dbPath = p.join(tempDir.path, 'restart_test.db');
    addTearDown(() => tempDir.delete(recursive: true));

    final firstOpen = AppDatabase()
      ..factoryOverride = databaseFactoryFfi
      ..pathOverride = dbPath;
    await SqliteSessionRepository(firstOpen).save(_session('s1'));
    await firstOpen.close();

    final reopened = AppDatabase()
      ..factoryOverride = databaseFactoryFfi
      ..pathOverride = dbPath;
    final reopenedRepo = SqliteSessionRepository(reopened);

    final afterReopen = await reopenedRepo.listAll();
    expect(afterReopen.map((s) => s.id), ['s1']);
    await reopened.close();
  });

  test('listAll returns sessions reverse-chronologically', () async {
    await repository.save(
      _session('older', startedAt: DateTime(2026, 1, 1, 8)),
    );
    await repository.save(
      _session('newer', startedAt: DateTime(2026, 1, 1, 10)),
    );
    await repository.save(
      _session('middle', startedAt: DateTime(2026, 1, 1, 9)),
    );

    final all = await repository.listAll();

    expect(all.map((s) => s.id).toList(), ['newer', 'middle', 'older']);
  });

  test('delete removes only the targeted session row', () async {
    await repository.save(_session('keep'));
    await repository.save(_session('remove'));

    await repository.delete('remove');
    final remaining = await repository.listAll();

    expect(remaining.map((s) => s.id), ['keep']);
    expect(await repository.getById('remove'), isNull);
  });

  test('deleteAll clears every session row', () async {
    await repository.save(_session('a'));
    await repository.save(_session('b'));

    await repository.deleteAll();

    expect(await repository.listAll(), isEmpty);
  });

  test(
    'actionPointsDone round-trips alongside actionPoints (checklist state)',
    () async {
      final session = _session('s1').copyWith(
        actionPoints: ['a', 'b'],
        actionPointsDone: [true, false],
      );

      await repository.save(session);
      final loaded = await repository.getById('s1');

      expect(loaded!.actionPoints, ['a', 'b']);
      expect(loaded.actionPointsDone, [true, false]);
    },
  );
}
