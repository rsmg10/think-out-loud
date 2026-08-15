import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns where session audio lives on disk. Files live in the app's private
/// sandboxed documents directory only — never a shared/public directory —
/// per docs/session-model.md.
class AudioFileStorage {
  Directory? _sessionsDir;

  Future<Directory> _dir() async {
    if (_sessionsDir != null) return _sessionsDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'session_audio'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _sessionsDir = dir;
    return dir;
  }

  /// Returns the absolute path a new session's audio should be recorded
  /// to. The native engine writes here directly.
  Future<String> newAudioPath(String sessionId) async {
    final dir = await _dir();
    return p.join(dir.path, '$sessionId.wav');
  }

  Future<bool> exists(String path) => File(path).exists();

  /// Deletes a single session's audio file. Never throws if the file is
  /// already gone (idempotent, matches session-delete semantics).
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Removes every file in the sessions audio directory — used by
  /// Settings "delete all", which must remove audio, not just DB rows.
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) {
        await entity.delete();
      }
    }
  }

  /// Total bytes used by session audio, for the Settings storage display.
  Future<int> totalBytes() async {
    final dir = await _dir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
