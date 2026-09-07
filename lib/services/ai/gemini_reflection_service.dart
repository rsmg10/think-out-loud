import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../features/reflection/reflection_service.dart';
import 'gemini_config.dart';

/// Real `ReflectionService` implementation — the one piece of this app
/// that actually calls a cloud AI provider, per the user's explicit
/// Phase 2 direction (see the Phase 2 plan's Context section). Never
/// called directly from a widget — only through the `ReflectionService`
/// interface, per CLAUDE.md.
class GeminiReflectionService implements ReflectionService {
  static const _modelName = 'gemini-2.0-flash';

  GenerativeModel? _model;

  GenerativeModel? _modelOrNull() {
    if (!GeminiConfig.isConfigured) return null;
    return _model ??= GenerativeModel(
      model: _modelName,
      apiKey: GeminiConfig.apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.object(
          properties: {
            'summary': Schema.string(
              description: 'A 2-4 sentence summary of what was said.',
              nullable: true,
            ),
            'keyIdeas': Schema.array(
              items: Schema.string(),
              description: 'The main ideas raised, as short phrases.',
            ),
            'actionPoints': Schema.array(
              items: Schema.string(),
              description:
                  'Concrete next actions/tasks implied or stated, as short '
                  'imperative phrases (e.g. "Email Sam about the budget").',
            ),
            'openQuestions': Schema.array(
              items: Schema.string(),
              description:
                  'Questions the speaker raised but did not resolve.',
            ),
            'mood': Schema.string(
              description:
                  'One word describing the speaker\'s mood, from this exact '
                  'set: calm, anxious, energized, frustrated, hopeful, '
                  'neutral, mixed.',
              nullable: true,
            ),
          },
          requiredProperties: ['keyIdeas', 'actionPoints', 'openQuestions'],
        ),
      ),
    );
  }

  @override
  Future<ReflectionResult?> reflect(String transcript) async {
    final model = _modelOrNull();
    if (model == null || transcript.trim().isEmpty) return null;

    try {
      final response = await model.generateContent([
        Content.text(
          'This is a transcript of someone thinking out loud into a '
          'recorder — informal, unstructured spoken thought, not a '
          'polished document. Reflect it back to them: summarize it, and '
          'pull out key ideas, concrete action points, and open '
          'questions they raised but didn\'t resolve. Use only what\'s '
          'actually in the transcript — do not invent content.\n\n'
          'Transcript:\n$transcript',
        ),
      ]);
      final text = response.text;
      if (text == null) return null;

      final json = jsonDecode(text) as Map<String, Object?>;
      return ReflectionResult(
        summary: json['summary'] as String?,
        keyIdeas: _stringList(json['keyIdeas']),
        actionPoints: _stringList(json['actionPoints']),
        openQuestions: _stringList(json['openQuestions']),
        mood: json['mood'] as String?,
      );
    } catch (_) {
      // Reflection is best-effort and never blocks the core session —
      // callers see this as a null result and can mark the session
      // AiProcessingStatus.failed rather than crash.
      return null;
    }
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }
}
