import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AiProcessingStatus { notProcessed, pending, complete, failed }

AiProcessingStatus aiProcessingStatusFromName(String name) {
  return AiProcessingStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => AiProcessingStatus.notProcessed,
  );
}

/// A single thinking session. Only the fields marked P1 in
/// docs/session-model.md are populated by this build; the rest exist so
/// later phases don't require a schema migration on day one.
@immutable
class ThinkingSession {
  final String id;
  final DateTime createdAt;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration duration;

  /// Path to the locally-persisted audio file, relative to the app's
  /// private documents directory. Never a shared/public path.
  final String? audioReference;

  final String? transcript;
  final String? summary;
  final List<String> keyIdeas;
  final List<String> actionPoints;

  /// Parallel to [actionPoints] — which ones the user has checked off in
  /// Session Details. Not length-enforced against [actionPoints] (a
  /// shorter list just means "the rest aren't done yet"); reset to `[]`
  /// whenever [actionPoints] itself is replaced by a fresh reflection, so
  /// stale checkmarks never silently point at different content.
  final List<bool> actionPointsDone;
  final List<String> openQuestions;

  /// One word from the fixed vocabulary in GeminiReflectionService's
  /// prompt (calm/anxious/energized/frustrated/hopeful/neutral/mixed), or
  /// null before reflection has run.
  final String? mood;

  final List<String> tags;
  final AiProcessingStatus status;

  const ThinkingSession({
    required this.id,
    required this.createdAt,
    required this.startedAt,
    this.endedAt,
    required this.duration,
    this.audioReference,
    this.transcript,
    this.summary,
    this.keyIdeas = const [],
    this.actionPoints = const [],
    this.actionPointsDone = const [],
    this.openQuestions = const [],
    this.mood,
    this.tags = const [],
    this.status = AiProcessingStatus.notProcessed,
  });

  ThinkingSession copyWith({
    DateTime? endedAt,
    Duration? duration,
    String? audioReference,
    String? transcript,
    String? summary,
    List<String>? keyIdeas,
    List<String>? actionPoints,
    List<bool>? actionPointsDone,
    List<String>? openQuestions,
    String? mood,
    AiProcessingStatus? status,
  }) {
    return ThinkingSession(
      id: id,
      createdAt: createdAt,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      audioReference: audioReference ?? this.audioReference,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      keyIdeas: keyIdeas ?? this.keyIdeas,
      actionPoints: actionPoints ?? this.actionPoints,
      actionPointsDone: actionPointsDone ?? this.actionPointsDone,
      openQuestions: openQuestions ?? this.openQuestions,
      mood: mood ?? this.mood,
      tags: tags,
      status: status ?? this.status,
    );
  }

  /// A label for History when no transcript exists yet — must not imply
  /// transcription happened (see docs/mvp-scope.md).
  String get placeholderLabel {
    final d = startedAt;
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return 'Session - $hour:$minute $period';
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'durationMs': duration.inMilliseconds,
      'audioReference': audioReference,
      'transcript': transcript,
      'summary': summary,
      'keyIdeas': jsonEncode(keyIdeas),
      'actionPoints': jsonEncode(actionPoints),
      'actionPointsDone': jsonEncode(actionPointsDone),
      'openQuestions': jsonEncode(openQuestions),
      'mood': mood,
      'tags': jsonEncode(tags),
      'status': status.name,
    };
  }

  factory ThinkingSession.fromMap(Map<String, Object?> map) {
    List<String> decodeOrEmpty(Object? v) {
      final s = v as String?;
      if (s == null || s.isEmpty) return const [];
      return (jsonDecode(s) as List).cast<String>();
    }

    List<bool> decodeBoolListOrEmpty(Object? v) {
      final s = v as String?;
      if (s == null || s.isEmpty) return const [];
      return (jsonDecode(s) as List).cast<bool>();
    }

    return ThinkingSession(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      startedAt: DateTime.parse(map['startedAt'] as String),
      endedAt: map['endedAt'] == null
          ? null
          : DateTime.parse(map['endedAt'] as String),
      duration: Duration(milliseconds: map['durationMs'] as int),
      audioReference: map['audioReference'] as String?,
      transcript: map['transcript'] as String?,
      summary: map['summary'] as String?,
      keyIdeas: decodeOrEmpty(map['keyIdeas']),
      actionPoints: decodeOrEmpty(map['actionPoints']),
      actionPointsDone: decodeBoolListOrEmpty(map['actionPointsDone']),
      openQuestions: decodeOrEmpty(map['openQuestions']),
      mood: map['mood'] as String?,
      tags: decodeOrEmpty(map['tags']),
      status: aiProcessingStatusFromName(map['status'] as String),
    );
  }
}
