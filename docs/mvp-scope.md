# MVP Scope (Phase 1 — "Think")

## Build now

- Home screen: one dominant **Think** button, minimal supporting text,
  understandable in under a second.
- Microphone permission flow, including recovery after denial.
- Native low-latency audio monitoring (see `audio-architecture.md`).
- Headphone/route detection with a warning when unsafe to monitor via
  speaker.
- Active Thinking screen: status, elapsed time, subtle waveform, Stop —
  nothing else. Should work with the phone in a pocket.
- Session completion screen: calm, positive, shows duration. No fake AI
  results (no key idea counts, no summaries) — those don't exist yet.
- Local session persistence (see `session-model.md`).
- History screen: reverse-chronological list, date, duration, and (since
  no transcript exists yet) a simple auto-generated or placeholder label
  — not a fake preview line implying transcription happened.
- Session Details screen: date/duration plus playback of the saved audio
  (basic play/pause/seek is enough for Phase 1); sections for
  transcript/summary/ideas/etc. simply don't render when empty rather
  than showing empty placeholders.
- Settings: audio route info, data/privacy basics (what's stored locally,
  delete-all).
- Explicit error states for: permission denied, no audio route, storage
  failure, unexpected native-engine failure.
- Automated tests (see `testing.md`).

## Architecture only — interfaces + mocks, not real calls

- `TranscriptionService`
- `SummarizationService` / part of a broader `ReflectionService`
- `ReflectionService`
- `CommunicationAnalysisService`
- `MemoryService`

These should be real Dart interfaces with a working mock/no-op
implementation wired through DI, so a future phase can swap in a real
provider without touching UI code. The UI must not know or care which
provider (if any) is behind them.

## Explicitly not in Phase 1

- No transcription, summarization, reflection, or communication analysis
  actually running.
- No cross-session memory or theme detection.
- No accounts, auth, or backend.
- No AI API calls of any kind.
