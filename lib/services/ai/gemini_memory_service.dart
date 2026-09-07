import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/sessions/session_repository.dart';
import '../../features/sessions/thinking_session.dart';
import 'gemini_config.dart';
import 'memory_service.dart';

/// Real `MemoryService` implementation — surfaces recurring themes/open
/// threads across a user's past sessions, per the Phase 2 market-research
/// direction (cross-entry pattern detection). Unlike `GeminiReflectionService`
/// this is inherently cross-session, so it needs repository access rather
/// than just a transcript string.
class GeminiMemoryService implements MemoryService {
  // gemini-2.0-flash was retired; matches the replacement model name
  // GeminiReflectionService moved to (see its own history) after Google's
  // API error named gemini-3.6-flash as the successor.
  static const _modelName = 'gemini-3.6-flash';
  static const _minQualifyingSessions = 3;
  static const _maxSessionsConsidered = 10;

  final SessionRepository _repository;

  GeminiMemoryService(this._repository);

  GenerativeModel? _model;

  GenerativeModel? _modelOrNull() {
    if (!GeminiConfig.isConfigured) return null;
    return _model ??= GenerativeModel(
      model: _modelName,
      apiKey: GeminiConfig.apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.array(
          items: Schema.string(),
          description:
              '3-5 recurring themes or open threads across the sessions, '
              'each phrased briefly (a few words).',
        ),
      ),
    );
  }

  @override
  Future<List<String>> recurringThemes() async {
    final model = _modelOrNull();
    if (model == null) return const [];

    try {
      final sessions = await _repository.listAll();
      final qualifying = sessions
          .take(_maxSessionsConsidered)
          .where((s) => s.summary != null && s.summary!.trim().isNotEmpty)
          .toList();
      if (qualifying.length < _minQualifyingSessions) return const [];

      final response = await model.generateContent([
        Content.text(
          'These are summaries of someone\'s recent thinking-out-loud '
          'sessions, most recent first. Identify 3-5 recurring themes or '
          'open threads that show up across multiple sessions — things '
          'they keep coming back to. Use only what\'s actually present '
          'across these sessions — do not invent content. Phrase each '
          'theme briefly, a few words each.\n\n'
          '${_describeSessions(qualifying)}',
        ),
      ]);
      final text = response.text;
      if (text == null) return const [];

      final json = jsonDecode(text);
      if (json is! List) return const [];
      return json.whereType<String>().toList();
    } catch (_) {
      // Best-effort, never blocks the UI — callers see this as an empty
      // list, same shape as "not enough sessions yet".
      return const [];
    }
  }

  String _describeSessions(List<ThinkingSession> sessions) {
    final buffer = StringBuffer();
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      buffer.writeln('Session ${i + 1}:');
      buffer.writeln('Summary: ${session.summary}');
      if (session.keyIdeas.isNotEmpty) {
        buffer.writeln('Key ideas: ${session.keyIdeas.join(', ')}');
      }
      if (session.openQuestions.isNotEmpty) {
        buffer.writeln('Open questions: ${session.openQuestions.join(', ')}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  @override
  Future<void> record(String sessionId, {List<String> themes = const []}) async {
    // No-op: themes are recomputed on-demand each time the Patterns screen
    // opens (recurringThemes() re-derives from session history), so there's
    // nothing cheap to gain from persisting them here — matches
    // NoOpMemoryService's behavior.
  }
}
