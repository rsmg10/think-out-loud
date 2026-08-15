import 'thinking_session.dart';

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);

  @override
  String toString() => 'StorageException($message)';
}

/// Local-only persistence for sessions. No network calls — sessions are
/// local-first per CLAUDE.md.
abstract class SessionRepository {
  Future<void> save(ThinkingSession session);

  /// Reverse-chronological (newest first), for the History screen.
  Future<List<ThinkingSession>> listAll();

  Future<ThinkingSession?> getById(String id);

  /// Deletes the session row. Callers are responsible for also deleting
  /// the referenced audio file (see AudioFileStorage) — this method only
  /// owns the DB row.
  Future<void> delete(String id);

  Future<void> deleteAll();
}
