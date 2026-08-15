/// Interface only for Phase 1 — no real provider is called. See
/// CLAUDE.md: "No AI API calls yet — build the service interfaces only."
/// UI code must depend on this interface, never a concrete provider.
abstract class TranscriptionService {
  Future<String?> transcribe(String audioFilePath);
}

class NoOpTranscriptionService implements TranscriptionService {
  const NoOpTranscriptionService();

  @override
  Future<String?> transcribe(String audioFilePath) async => null;
}
