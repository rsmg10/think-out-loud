import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/services/storage/audio_file_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;
  late AudioFileStorage storage;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('think_out_loud_docs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDocs.path;
      }
      return null;
    });
    storage = AudioFileStorage();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await tempDocs.delete(recursive: true);
  });

  test('audio files are written under the private documents directory', () async {
    final path = await storage.newAudioPath('session-1');

    expect(path, startsWith(tempDocs.path));
    expect(path, contains('session_audio'));
  });

  test('delete removes the session file on disk', () async {
    final path = await storage.newAudioPath('session-1');
    await File(path).writeAsBytes([1, 2, 3]);
    expect(await storage.exists(path), isTrue);

    await storage.delete(path);

    expect(await storage.exists(path), isFalse);
  });

  test('delete is a no-op (does not throw) when the file is already gone', () async {
    final path = await storage.newAudioPath('never-created');

    await storage.delete(path);

    expect(await storage.exists(path), isFalse);
  });

  test('deleteAll removes every audio file, not just one', () async {
    final pathA = await storage.newAudioPath('a');
    final pathB = await storage.newAudioPath('b');
    await File(pathA).writeAsBytes([1]);
    await File(pathB).writeAsBytes([1]);

    await storage.deleteAll();

    expect(await storage.exists(pathA), isFalse);
    expect(await storage.exists(pathB), isFalse);
  });

  test('totalBytes sums the size of every stored audio file', () async {
    final pathA = await storage.newAudioPath('a');
    final pathB = await storage.newAudioPath('b');
    await File(pathA).writeAsBytes(List.filled(10, 0));
    await File(pathB).writeAsBytes(List.filled(20, 0));

    expect(await storage.totalBytes(), 30);
  });
}
