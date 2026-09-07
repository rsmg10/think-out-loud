class ReflectionResult {
  final String? summary;
  final List<String> keyIdeas;
  final List<String> actionPoints;
  final List<String> openQuestions;

  /// One word from a fixed vocabulary (see GeminiReflectionService's
  /// prompt) — never free-form, so Session Details can map it to a fixed
  /// icon set.
  final String? mood;

  const ReflectionResult({
    this.summary,
    this.keyIdeas = const [],
    this.actionPoints = const [],
    this.openQuestions = const [],
    this.mood,
  });
}

/// Interface only for Phase 1 — no real provider is called. A future
/// phase implements this using SummarizationService plus additional
/// reasoning over the transcript.
abstract class ReflectionService {
  Future<ReflectionResult?> reflect(String transcript);
}

class NoOpReflectionService implements ReflectionService {
  const NoOpReflectionService();

  @override
  Future<ReflectionResult?> reflect(String transcript) async => null;
}
