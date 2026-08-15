import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/communication/communication_analysis_service.dart';
import '../features/reflection/reflection_service.dart';
import '../features/sessions/session_repository.dart';
import '../features/sessions/sqlite_session_repository.dart';
import '../features/sessions/thinking_session.dart';
import '../features/thinking/thinking_controller.dart';
import '../features/thinking/thinking_state.dart';
import '../services/ai/memory_service.dart';
import '../services/ai/summarization_service.dart';
import '../services/audio/audio_monitoring_service.dart';
import '../services/audio/native_audio_monitoring_service.dart';
import '../services/storage/app_database.dart';
import '../services/storage/audio_file_storage.dart';
import '../services/transcription/transcription_service.dart';

// Every provider below is overridable — tests and the widget tree swap
// concrete implementations for mocks without any UI code changing.

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final audioFileStorageProvider = Provider<AudioFileStorage>(
  (ref) => AudioFileStorage(),
);

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SqliteSessionRepository(ref.watch(appDatabaseProvider));
});

final audioMonitoringServiceProvider = Provider<AudioMonitoringService>((
  ref,
) {
  final service = NativeAudioMonitoringService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Phase 1: interfaces only, real calls never happen. See CLAUDE.md.
final transcriptionServiceProvider = Provider<TranscriptionService>(
  (ref) => const NoOpTranscriptionService(),
);
final summarizationServiceProvider = Provider<SummarizationService>(
  (ref) => const NoOpSummarizationService(),
);
final reflectionServiceProvider = Provider<ReflectionService>(
  (ref) => const NoOpReflectionService(),
);
final communicationAnalysisServiceProvider =
    Provider<CommunicationAnalysisService>(
      (ref) => const NoOpCommunicationAnalysisService(),
    );
final memoryServiceProvider = Provider<MemoryService>(
  (ref) => const NoOpMemoryService(),
);

final thinkingControllerProvider =
    StateNotifierProvider<ThinkingController, ThinkingUiState>((ref) {
      return ThinkingController(
        ref.watch(audioMonitoringServiceProvider),
        ref.watch(sessionRepositoryProvider),
        ref.watch(audioFileStorageProvider),
      );
    });

/// Refreshed whenever a session is saved/deleted via [sessionListRefreshProvider.notifier].state++.
final sessionListRefreshProvider = StateProvider<int>((ref) => 0);

final sessionListProvider = FutureProvider<List<ThinkingSession>>((
  ref,
) async {
  ref.watch(sessionListRefreshProvider);
  return ref.watch(sessionRepositoryProvider).listAll();
});
