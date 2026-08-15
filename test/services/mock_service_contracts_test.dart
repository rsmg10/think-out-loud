import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/features/communication/communication_analysis_service.dart';
import 'package:think_out_loud/features/reflection/reflection_service.dart';
import 'package:think_out_loud/services/ai/memory_service.dart';
import 'package:think_out_loud/services/ai/summarization_service.dart';
import 'package:think_out_loud/services/transcription/transcription_service.dart';

/// Phase 1 must never call a real AI provider — CLAUDE.md's hard rules.
/// These tests confirm the no-op implementations satisfy their
/// interfaces and return "nothing happened" rather than throwing or
/// producing fabricated results.
void main() {
  test('NoOpTranscriptionService satisfies TranscriptionService and no-ops', () async {
    const TranscriptionService service = NoOpTranscriptionService();
    expect(await service.transcribe('/some/audio.wav'), isNull);
  });

  test('NoOpSummarizationService satisfies SummarizationService and no-ops', () async {
    const SummarizationService service = NoOpSummarizationService();
    expect(await service.summarize('some transcript'), isNull);
  });

  test('NoOpReflectionService satisfies ReflectionService and no-ops', () async {
    const ReflectionService service = NoOpReflectionService();
    expect(await service.reflect('some transcript'), isNull);
  });

  test(
    'NoOpCommunicationAnalysisService satisfies CommunicationAnalysisService and no-ops',
    () async {
      const CommunicationAnalysisService service =
          NoOpCommunicationAnalysisService();
      expect(await service.analyze('some transcript'), isNull);
    },
  );

  test('NoOpMemoryService satisfies MemoryService and no-ops', () async {
    const MemoryService service = NoOpMemoryService();
    expect(await service.recurringThemes(), isEmpty);
    // Must not throw even though nothing is actually recorded.
    await service.record('session-1', themes: const ['focus']);
  });
}
