/// Cross-session memory/theme detection — out of scope for Phase 1
/// (see docs/mvp-scope.md). Interface only, no real provider is called.
abstract class MemoryService {
  Future<List<String>> recurringThemes();

  Future<void> record(String sessionId, {List<String> themes});
}

class NoOpMemoryService implements MemoryService {
  const NoOpMemoryService();

  @override
  Future<List<String>> recurringThemes() async => const [];

  @override
  Future<void> record(String sessionId, {List<String> themes = const []}) async {}
}
