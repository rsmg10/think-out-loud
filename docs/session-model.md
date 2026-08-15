# Session Model

Every thinking session is an independent, self-contained record. Phase 1
only populates the fields marked (P1); the rest exist so later phases
don't require a schema migration story on day one.

```dart
class ThinkingSession {
  final String id;
  final DateTime createdAt;      // P1
  final DateTime startedAt;      // P1
  final DateTime? endedAt;       // P1
  final Duration duration;       // P1 — derived, but store explicitly

  final String? audioReference;  // P1 if audio is persisted locally, else null

  final String? transcript;              // future
  final String? summary;                 // future
  final List<String> keyIdeas;           // future
  final List<String> actionPoints;       // future
  final List<String> openQuestions;      // future
  final CommunicationAnalysis? analysis; // future

  final List<String> tags;       // P1, empty by default — user-editable later
  final AiProcessingStatus status; // P1 — starts as `notProcessed`
}

enum AiProcessingStatus { notProcessed, pending, complete, failed }
```

## Phase 1 rules

- A session is created when the user presses **Think** and finalized when
  they press **Stop**. `duration` is always known even if nothing else is.
- Persist locally (e.g. a local DB — sqlite/drift/isar, or simple
  file-based storage if the volume stays low; pick based on what's already
  in the project, don't add a heavy dependency for a handful of records).
- Raw audio **is** persisted locally in Phase 1, so past sessions can be
  played back. `audioReference` points to a local file (app documents
  directory, not a shared/public one). This is local-only storage — it
  does not change the "don't upload audio unnecessarily" rule, which is
  about network calls, not local retention. Because sessions may contain
  sensitive personal thoughts:
  - store audio files in the app's private sandboxed storage, never a
    public/shared directory;
  - deleting a session must delete its audio file on disk, not just the
    DB row — verify this with a test, not an assumption;
  - "delete all" in Settings must remove all audio files, not just
    metadata;
  - consider on-device storage growth (long/frequent sessions add up) —
    surface storage used in Settings if reasonably easy, otherwise note it
    as a follow-up rather than blocking Phase 1 on it.
- The user must always be able to delete a session (and, later, all data).
  Build the delete path now even though it's barely visible in Phase 1 UI.

## Session states (thinking flow)

```
idle → starting → thinking → stopping → saved
                      ↘ interrupted (bluetooth drop / audio interruption) → thinking | idle
```

Cover these transitions explicitly in state-management tests — this is
one of the two things (along with persistence) most worth automated test
coverage on.
