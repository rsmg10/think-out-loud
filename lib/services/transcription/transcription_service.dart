/// Transcription runs live, alongside a thinking session (verified viable
/// running concurrently with the native audio monitoring engine — see the
/// Phase 2 plan's A0 spike), not as a one-shot pass over a finished audio
/// file. UI code must depend on this interface, never a concrete provider,
/// per CLAUDE.md.
abstract class TranscriptionService {
  /// Begins transcribing. Safe to call even if unavailable (e.g. no
  /// on-device recognizer, permission denied) — failures are silent here
  /// since transcription is supplementary, not the core feature; check
  /// [stopLiveTranscription]'s result to know whether anything was
  /// captured.
  Future<void> startLiveTranscription();

  /// Stops transcribing and returns everything captured since
  /// [startLiveTranscription], or null if nothing was captured.
  Future<String?> stopLiveTranscription();
}

class NoOpTranscriptionService implements TranscriptionService {
  const NoOpTranscriptionService();

  @override
  Future<void> startLiveTranscription() async {}

  @override
  Future<String?> stopLiveTranscription() async => null;
}
