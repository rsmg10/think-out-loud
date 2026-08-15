/// Interface only for Phase 1 — no real provider is called.
abstract class SummarizationService {
  Future<String?> summarize(String transcript);
}

class NoOpSummarizationService implements SummarizationService {
  const NoOpSummarizationService();

  @override
  Future<String?> summarize(String transcript) async => null;
}
