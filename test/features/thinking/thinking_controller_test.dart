import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:think_out_loud/features/reflection/reflection_service.dart';
import 'package:think_out_loud/features/sessions/session_repository.dart';
import 'package:think_out_loud/features/sessions/thinking_session.dart';
import 'package:think_out_loud/features/thinking/thinking_controller.dart';
import 'package:think_out_loud/features/thinking/thinking_state.dart';
import 'package:think_out_loud/services/audio/audio_monitoring_service.dart';
import 'package:think_out_loud/services/audio/audio_route.dart';
import 'package:think_out_loud/services/settings/user_preferences_service.dart';
import 'package:think_out_loud/services/storage/audio_file_storage.dart';
import 'package:think_out_loud/services/transcription/transcription_service.dart';

class MockAudioMonitoringService extends Mock
    implements AudioMonitoringService {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockAudioFileStorage extends Mock implements AudioFileStorage {}

class MockUserPreferencesService extends Mock
    implements UserPreferencesService {}

class MockTranscriptionService extends Mock implements TranscriptionService {}

class MockReflectionService extends Mock implements ReflectionService {}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late MockAudioMonitoringService audio;
  late MockSessionRepository repository;
  late MockAudioFileStorage storage;
  late MockUserPreferencesService preferences;
  late MockTranscriptionService transcription;
  late MockReflectionService reflection;
  late StreamController<double> levelController;
  late StreamController<AudioRoute> routeController;
  late StreamController<MonitoringInterruption> interruptionController;
  late StreamController<void> resumedController;
  late ThinkingController controller;

  setUpAll(() {
    registerFallbackValue(
      ThinkingSession(
        id: 'fallback',
        createdAt: DateTime(2026),
        startedAt: DateTime(2026),
        duration: Duration.zero,
      ),
    );
  });

  setUp(() {
    audio = MockAudioMonitoringService();
    repository = MockSessionRepository();
    storage = MockAudioFileStorage();
    preferences = MockUserPreferencesService();
    transcription = MockTranscriptionService();
    reflection = MockReflectionService();
    levelController = StreamController<double>.broadcast();
    routeController = StreamController<AudioRoute>.broadcast();
    interruptionController =
        StreamController<MonitoringInterruption>.broadcast();
    resumedController = StreamController<void>.broadcast();

    when(() => audio.levelStream).thenAnswer((_) => levelController.stream);
    when(() => audio.routeChanges).thenAnswer((_) => routeController.stream);
    when(
      () => audio.interruptions,
    ).thenAnswer((_) => interruptionController.stream);
    when(() => audio.resumed).thenAnswer((_) => resumedController.stream);
    when(
      () => audio.currentRoute(),
    ).thenAnswer((_) async => AudioRoute.headphones);
    when(
      () => storage.newAudioPath(any()),
    ).thenAnswer((_) async => '/tmp/session.wav');
    when(() => storage.delete(any())).thenAnswer((_) async {});
    when(() => repository.save(any())).thenAnswer((_) async {});
    when(
      () => preferences.getPreferBluetoothMic(),
    ).thenAnswer((_) async => true);
    when(
      () => preferences.getLiveEchoEnabled(),
    ).thenAnswer((_) async => true);
    when(() => audio.hasMicPermission()).thenAnswer((_) async => true);
    when(() => audio.requestMicPermission()).thenAnswer((_) async => true);
    when(
      () => transcription.startLiveTranscription(),
    ).thenAnswer((_) async {});
    when(
      () => transcription.stopLiveTranscription(),
    ).thenAnswer((_) async => null);

    controller = ThinkingController(
      audio,
      repository,
      storage,
      preferences,
      transcription,
      reflection,
    );
  });

  tearDown(() async {
    controller.dispose();
    await levelController.close();
    await routeController.close();
    await interruptionController.close();
    await resumedController.close();
  });

  test('idle -> starting -> thinking on a successful start', () async {
    when(
      () => audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
    ).thenAnswer((_) async {});

    expect(controller.state.phase, ThinkingPhase.idle);
    final future = controller.start();
    expect(controller.state.phase, ThinkingPhase.starting);
    await future;
    expect(controller.state.phase, ThinkingPhase.thinking);
  });

  test(
    'thinking -> stopping -> saved on stop, and the session is persisted',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      when(() => audio.stop()).thenAnswer((_) async {});
      await controller.start();

      final future = controller.stop();
      expect(controller.state.phase, ThinkingPhase.stopping);
      await future;

      expect(controller.state.phase, ThinkingPhase.saved);
      expect(controller.state.savedSession, isNotNull);
      expect(controller.state.savedSession!.audioReference, '/tmp/session.wav');
      verify(() => repository.save(any())).called(1);
    },
  );

  test(
    'a captured transcript triggers reflection: saved notProcessed, then pending, then complete',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      when(() => audio.stop()).thenAnswer((_) async {});
      when(
        () => transcription.stopLiveTranscription(),
      ).thenAnswer((_) async => 'I should call Sam about the budget.');
      when(() => reflection.reflect(any())).thenAnswer(
        (_) async => const ReflectionResult(
          summary: 'Discussed the budget.',
          keyIdeas: ['Budget needs revisiting'],
          actionPoints: ['Call Sam about the budget'],
          openQuestions: [],
        ),
      );

      await controller.start();
      await controller.stop();
      await _settle();
      await _settle();

      final saved = verify(
        () => repository.save(captureAny()),
      ).captured.cast<ThinkingSession>();
      expect(saved.map((s) => s.status).toList(), [
        AiProcessingStatus.notProcessed,
        AiProcessingStatus.pending,
        AiProcessingStatus.complete,
      ]);
      expect(saved.last.summary, 'Discussed the budget.');
      expect(saved.last.actionPoints, ['Call Sam about the budget']);
    },
  );

  test(
    'reflection failure marks the session failed instead of crashing',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      when(() => audio.stop()).thenAnswer((_) async {});
      when(
        () => transcription.stopLiveTranscription(),
      ).thenAnswer((_) async => 'some transcript');
      when(() => reflection.reflect(any())).thenAnswer((_) async => null);

      await controller.start();
      await controller.stop();
      await _settle();
      await _settle();

      final saved = verify(
        () => repository.save(captureAny()),
      ).captured.cast<ThinkingSession>();
      expect(saved.last.status, AiProcessingStatus.failed);
    },
  );

  test('no captured transcript means reflection is never triggered', () async {
    when(
      () => audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
    ).thenAnswer((_) async {});
    when(() => audio.stop()).thenAnswer((_) async {});
    // Default stub already returns null from stopLiveTranscription().

    await controller.start();
    await controller.stop();
    await _settle();

    verifyNever(() => reflection.reflect(any()));
  });

  test(
    'interrupted branch: thinking -> interrupted -> thinking on resume',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      await controller.start();

      interruptionController.add(
        MonitoringInterruption(
          InterruptionReason.bluetoothDisconnected,
          DateTime.now(),
        ),
      );
      await _settle();

      expect(controller.state.phase, ThinkingPhase.interrupted);
      expect(
        controller.state.interruptionReason,
        InterruptionReason.bluetoothDisconnected,
      );

      await controller.resumeAfterInterruption();

      expect(controller.state.phase, ThinkingPhase.thinking);
      verify(
        () => audio.start(
          '/tmp/session.wav',
          useBluetoothMic: any(named: 'useBluetoothMic'),
        ),
      ).called(2);
    },
  );

  test(
    'interrupted branch: thinking -> interrupted -> idle on cancel, discards audio',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      await controller.start();

      interruptionController.add(
        MonitoringInterruption(
          InterruptionReason.systemAudioInterruption,
          DateTime.now(),
        ),
      );
      await _settle();
      expect(controller.state.phase, ThinkingPhase.interrupted);

      await controller.cancelFromInterruption();

      expect(controller.state.phase, ThinkingPhase.idle);
      verify(() => storage.delete('/tmp/session.wav')).called(1);
      verifyNever(() => repository.save(any()));
    },
  );

  test(
    'an unsafe route change mid-session is treated as an interruption',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      await controller.start();

      routeController.add(AudioRoute.speaker);
      await _settle();

      expect(controller.state.phase, ThinkingPhase.interrupted);
      expect(
        controller.state.interruptionReason,
        InterruptionReason.routeBecameUnsafe,
      );
    },
  );

  test(
    'permission denied on start surfaces as an error and stays idle',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenThrow(
        const AudioEngineException(
          AudioEngineErrorType.permissionDenied,
          'no mic',
        ),
      );

      await controller.start();

      expect(controller.state.phase, ThinkingPhase.idle);
      expect(
        controller.state.error?.type,
        AudioEngineErrorType.permissionDenied,
      );
    },
  );

  test('no safe route on start surfaces as an error and stays idle', () async {
    when(
      () => audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
    ).thenThrow(
      const AudioEngineException(
        AudioEngineErrorType.noSafeRoute,
        'no headphones',
      ),
    );

    await controller.start();

    expect(controller.state.phase, ThinkingPhase.idle);
    expect(controller.state.error?.type, AudioEngineErrorType.noSafeRoute);
  });

  test(
    'a storage failure preparing the audio path surfaces as storageFailure, not a crash',
    () async {
      when(() => storage.newAudioPath(any())).thenThrow(Exception('disk full'));

      await controller.start();

      expect(controller.state.phase, ThinkingPhase.idle);
      expect(controller.state.error?.type, AudioEngineErrorType.storageFailure);
      verifyNever(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      );
    },
  );

  test(
    'a save failure on stop surfaces as storageFailure and stays idle',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      when(() => audio.stop()).thenAnswer((_) async {});
      when(() => repository.save(any())).thenThrow(Exception('db locked'));
      await controller.start();

      await controller.stop();

      expect(controller.state.phase, ThinkingPhase.idle);
      expect(controller.state.error?.type, AudioEngineErrorType.storageFailure);
    },
  );

  test(
    'an unexpected native engine failure on stop surfaces as engineFailure',
    () async {
      when(
        () =>
            audio.start(any(), useBluetoothMic: any(named: 'useBluetoothMic')),
      ).thenAnswer((_) async {});
      when(() => audio.stop()).thenThrow(
        const AudioEngineException(
          AudioEngineErrorType.engineFailure,
          'native crash',
        ),
      );
      await controller.start();

      await controller.stop();

      expect(controller.state.phase, ThinkingPhase.idle);
      expect(controller.state.error?.type, AudioEngineErrorType.engineFailure);
    },
  );

  group('live echo disabled', () {
    setUp(() {
      when(
        () => preferences.getLiveEchoEnabled(),
      ).thenAnswer((_) async => false);
    });

    test(
      'start() skips the monitoring engine and route/headphone check entirely',
      () async {
        await controller.start();

        expect(controller.state.phase, ThinkingPhase.thinking);
        expect(controller.state.liveEchoEnabled, isFalse);
        verifyNever(() => audio.currentRoute());
        verifyNever(() => storage.newAudioPath(any()));
        verifyNever(
          () => audio.start(
            any(),
            useBluetoothMic: any(named: 'useBluetoothMic'),
          ),
        );
        verify(() => transcription.startLiveTranscription()).called(1);
      },
    );

    test(
      'stop() does not call audio.stop() and saves a session with no audioReference',
      () async {
        await controller.start();

        await controller.stop();

        expect(controller.state.phase, ThinkingPhase.saved);
        expect(controller.state.savedSession!.audioReference, isNull);
        verifyNever(() => audio.stop());
        verify(() => repository.save(any())).called(1);
      },
    );

    test(
      'a denied mic permission surfaces as permissionDenied and never starts transcription',
      () async {
        when(() => audio.hasMicPermission()).thenAnswer((_) async => false);
        when(
          () => audio.requestMicPermission(),
        ).thenAnswer((_) async => false);

        await controller.start();

        expect(controller.state.phase, ThinkingPhase.idle);
        expect(
          controller.state.error?.type,
          AudioEngineErrorType.permissionDenied,
        );
        verifyNever(() => transcription.startLiveTranscription());
      },
    );
  });
}
