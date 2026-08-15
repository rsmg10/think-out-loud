# Think Out Loud — CLAUDE.md

## What this is

A Flutter app that lets someone put on headphones, press **Think**, speak,
and hear their own voice back in near real time — an audio feedback loop
that helps people think out loud without staring at a screen. Later phases
add transcription, AI reflection, communication coaching, and cross-session
memory. **This build is Phase 1 only.**

North star: *"Does hearing yourself think make it easier to keep thinking?"*
Guiding principle: *every session should leave the user clearer than before.*

Full context lives in `docs/`. Read these before writing code:
- `docs/audio-architecture.md` — **read first.** The core feature and the
  hardest part. Do not pick an audio package before reading this.
- `docs/design.md` — design system status (currently unresolved, see below)
- `docs/session-model.md` — data model for a thinking session
- `docs/mvp-scope.md` — exact Phase 1 feature boundary
- `docs/testing.md` — required manual + automated test checklist

## Open blocker: design system

The product brief references "DesignMD" as the design system to follow, but
no such system is confirmed to exist in this repo or as a known package.
**Step 1: search the repo, any linked Figma, and any provided assets for
a design system matching that name before writing UI code.** If found,
inspect it fully (typography, spacing, color, components) before building
a single screen. If genuinely not found, say so explicitly and fall back to
the minimal direction in `docs/design.md` rather than inventing a competing
system silently.

## Hard rules

- **Do not fake the audio result.** The core acceptance test is: headphones
  on, press Think, speak, hear yourself with low enough latency to be
  useful. If you cannot verify this on a real device/simulator with real
  headphones in this environment, say so plainly. Compiling is not testing.
- No backend, no accounts, no auth in Phase 1.
- No AI API calls yet — build the service *interfaces* only
  (`TranscriptionService`, `SummarizationService`, `ReflectionService`,
  `CommunicationAnalysisService`, `MemoryService`), with mock/no-op
  implementations. Never call an AI provider directly from a widget.
- Never embed provider API keys client-side.
- Sessions are local-first. No unnecessary uploads, no tracking, no ads.
- The live monitoring path (mic → output) must never round-trip through a
  remote server.

## Architecture

Feature-oriented, business logic out of widgets, services testable in
isolation:

```
lib/
  core/
  features/
    thinking/        # active session screen, start/stop
    sessions/         # session model + local persistence
    history/
    reflection/        # interface + mock only
    communication/      # interface + mock only
    settings/
  services/
    audio/             # native-backed monitoring engine
    transcription/      # interface + mock only
    ai/                 # interface + mock only
    storage/
  shared/
```

Improve this structure if you find a better one — don't force-fit.

## Development order

1. Locate/inspect design system (see blocker above).
2. Read `docs/audio-architecture.md`, prototype the native monitoring path.
3. Test latency and headphone routing *before* building any UI around it.
4. Build the minimal Think / Active Thinking / Stop flow.
5. Local persistence (session model in `docs/session-model.md`).
6. History + Session Details screens.
7. Stub the future AI service interfaces (no real calls).
8. Polish against the design system.
9. Run automated tests, then manual tests from `docs/testing.md`.
10. Fix issues, re-test from a clean install.

## Final report format

When done, report against the 10 points in `docs/testing.md`'s report
template — not a generic "implementation complete." State specifically
what was tested, what was verified on real hardware/headphones vs.
simulator-only, and what remains unverified.
