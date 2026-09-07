import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the local sqlite database. A handful of records at most in
/// Phase 1, but sqlite gives ordered queries (History is
/// reverse-chronological) for free without hand-rolled file parsing.
class AppDatabase {
  static const _dbName = 'think_out_loud.db';
  static const _dbVersion = 3;

  Database? _db;

  /// Overridable so tests can point at an in-memory / ffi-backed factory.
  DatabaseFactory? factoryOverride;

  /// Overridable so tests can use an isolated (e.g. in-memory) database
  /// file instead of the real on-disk path.
  String? pathOverride;

  Future<Database> open() async {
    if (_db != null) return _db!;
    final factory = factoryOverride ?? databaseFactory;
    final path = pathOverride ?? p.join(await factory.getDatabasesPath(), _dbName);
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              createdAt TEXT NOT NULL,
              startedAt TEXT NOT NULL,
              endedAt TEXT,
              durationMs INTEGER NOT NULL,
              audioReference TEXT,
              transcript TEXT,
              summary TEXT,
              keyIdeas TEXT,
              actionPoints TEXT,
              actionPointsDone TEXT,
              openQuestions TEXT,
              mood TEXT,
              tags TEXT,
              status TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_sessions_startedAt ON sessions(startedAt)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN actionPointsDone TEXT',
            );
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE sessions ADD COLUMN mood TEXT');
          }
        },
      ),
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
