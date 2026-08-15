import 'package:sqflite/sqflite.dart';

import '../../services/storage/app_database.dart';
import 'session_repository.dart';
import 'thinking_session.dart';

class SqliteSessionRepository implements SessionRepository {
  final AppDatabase _appDatabase;

  SqliteSessionRepository(this._appDatabase);

  @override
  Future<void> save(ThinkingSession session) async {
    try {
      final db = await _appDatabase.open();
      await db.insert(
        'sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw StorageException('Failed to save session: $e');
    }
  }

  @override
  Future<List<ThinkingSession>> listAll() async {
    try {
      final db = await _appDatabase.open();
      final rows = await db.query('sessions', orderBy: 'startedAt DESC');
      return rows.map(ThinkingSession.fromMap).toList();
    } catch (e) {
      throw StorageException('Failed to load sessions: $e');
    }
  }

  @override
  Future<ThinkingSession?> getById(String id) async {
    try {
      final db = await _appDatabase.open();
      final rows = await db.query(
        'sessions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return ThinkingSession.fromMap(rows.first);
    } catch (e) {
      throw StorageException('Failed to load session: $e');
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      final db = await _appDatabase.open();
      await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      throw StorageException('Failed to delete session: $e');
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      final db = await _appDatabase.open();
      await db.delete('sessions');
    } catch (e) {
      throw StorageException('Failed to delete all sessions: $e');
    }
  }
}
