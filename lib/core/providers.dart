import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/communication/communication_analysis_service.dart';
import '../features/reflection/reflection_service.dart';
import '../features/sessions/session_repository.dart';
import '../features/sessions/sqlite_session_repository.dart';
import '../features/sessions/thinking_session.dart';
import '../features/thinking/thinking_controller.dart';
import '../features/thinking/thinking_state.dart';
import '../services/ai/gemini_reflection_service.dart';
import '../services/ai/memory_service.dart';
import '../services/ai/summarization_service.dart';
import '../services/audio/audio_monitoring_service.dart';
import '../services/audio/native_audio_monitoring_service.dart';
import '../services/calendar/calendar_service.dart';
import '../services/calendar/google_calendar_service.dart';
import '../services/settings/shared_prefs_user_preferences_service.dart';
import '../services/settings/user_preferences_service.dart';
import '../services/storage/app_database.dart';
import '../services/storage/audio_file_storage.dart';
import '../services/transcription/on_device_transcription_service.dart';
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

final audioMonitoringServiceProvider = Provider<AudioMonitoringService>((ref) {
  final service = NativeAudioMonitoringService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Phase 2: real, on-device, no API key or network call involved — see
// docs/audio-architecture.md-style verification in the Phase 2 plan (A0).
final transcriptionServiceProvider = Provider<TranscriptionService>(
  (ref) => OnDeviceTranscriptionService(),
);
// Phase 1: interfaces only, real calls never happen for these. See CLAUDE.md.
final summarizationServiceProvider = Provider<SummarizationService>(
  (ref) => const NoOpSummarizationService(),
);
// Phase 2: real Gemini calls (see docs/known-limitations.md for the
// local-only API key caveat). Falls back to a no-op result whenever
// GEMINI_API_KEY isn't configured, so the app still works without it.
final reflectionServiceProvider = Provider<ReflectionService>(
  (ref) => GeminiReflectionService(),
);
final communicationAnalysisServiceProvider =
    Provider<CommunicationAnalysisService>(
      (ref) => const NoOpCommunicationAnalysisService(),
    );
final memoryServiceProvider = Provider<MemoryService>(
  (ref) => const NoOpMemoryService(),
);

final userPreferencesServiceProvider = Provider<UserPreferencesService>(
  (ref) => SharedPrefsUserPreferencesService(),
);

// Phase B: real Google Sign-In + Calendar API. Every write is gated behind
// explicit user confirmation in ScheduleActionPointsScreen — see CLAUDE.md.
final calendarServiceProvider = Provider<CalendarService>(
  (ref) => GoogleCalendarService(),
);

final thinkingControllerProvider =
    StateNotifierProvider<ThinkingController, ThinkingUiState>((ref) {
      return ThinkingController(
        ref.watch(audioMonitoringServiceProvider),
        ref.watch(sessionRepositoryProvider),
        ref.watch(audioFileStorageProvider),
        ref.watch(userPreferencesServiceProvider),
        ref.watch(transcriptionServiceProvider),
        ref.watch(reflectionServiceProvider),
      );
    });

/// Loaded once and kept in sync with Settings — Home reads this (not the
/// raw service) so the "Connecting to your headphones…" copy and the
/// Settings switch never disagree.
class PreferBluetoothMicController extends StateNotifier<bool> {
  final UserPreferencesService _preferences;

  PreferBluetoothMicController(this._preferences) : super(true) {
    _load();
  }

  Future<void> _load() async {
    state = await _preferences.getPreferBluetoothMic();
  }

  Future<void> setPreferBluetoothMic(bool value) async {
    state = value;
    await _preferences.setPreferBluetoothMic(value);
  }
}

final preferBluetoothMicProvider =
    StateNotifierProvider<PreferBluetoothMicController, bool>((ref) {
      return PreferBluetoothMicController(
        ref.watch(userPreferencesServiceProvider),
      );
    });

/// Refreshed whenever a session is saved/deleted via [sessionListRefreshProvider.notifier].state++.
final sessionListRefreshProvider = StateProvider<int>((ref) => 0);

final sessionListProvider = FutureProvider<List<ThinkingSession>>((ref) async {
  ref.watch(sessionListRefreshProvider);
  return ref.watch(sessionRepositoryProvider).listAll();
});
