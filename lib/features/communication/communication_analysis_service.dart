class CommunicationAnalysis {
  final String? clarityNotes;
  final List<String> fillerWordFlags;

  const CommunicationAnalysis({
    this.clarityNotes,
    this.fillerWordFlags = const [],
  });
}

/// Interface only for Phase 1 — no real provider is called.
abstract class CommunicationAnalysisService {
  Future<CommunicationAnalysis?> analyze(String transcript);
}

class NoOpCommunicationAnalysisService implements CommunicationAnalysisService {
  const NoOpCommunicationAnalysisService();

  @override
  Future<CommunicationAnalysis?> analyze(String transcript) async => null;
}
