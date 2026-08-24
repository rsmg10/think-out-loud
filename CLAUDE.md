# Think Out Loud — CLAUDE.md

## What this is

A Flutter app that lets someone put on headphones, press **Think**, speak,
and hear their own voice back in near real time — an audio feedback loop
that helps people think out loud without staring at a screen. Later phases
add transcription, AI reflection, communication coaching, and cross-session
memory. **Phase 1 (the audio loop, local persistence, History/Details) is
done. Phase 2 (real transcription + AI reflection, in progress; Calendar/
Notion integration, planned) supersedes some of Phase 1's hard rules below
— see "Phase 2" for exactly what changed and why.**

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
- No backend, no accounts, no auth in Phase 1. **(Superseded for Phase 2's
  AI calls — see "Phase 2" below.)**
- No AI API calls yet — build the service *interfaces* only
  (`TranscriptionService`, `SummarizationService`, `ReflectionService`,
  `CommunicationAnalysisService`, `MemoryService`), with mock/no-op
  implementations. Never call an AI provider directly from a widget.
  **(Superseded for `TranscriptionService` — on-device, not a cloud call —
  and `ReflectionService`, which now calls Gemini. Summarization/
  communication/memory remain no-op.)**
- Never embed provider API keys client-side. **(Knowingly superseded, as a
  temporary shortcut, for the Gemini key — see "Phase 2" and
  `docs/known-limitations.md`. Still applies to every other rule on this
  list; this is not a general license to skip it elsewhere.)**
- Sessions are local-first. No unnecessary uploads, no tracking, no ads.
  Still true — Gemini reflection is the one deliberate exception, and only
  the transcript (not raw audio) is ever sent, only when the user's
  session actually produced one.
- The live monitoring path (mic → output) must never round-trip through a
  remote server. Still an absolute rule, unaffected by Phase 2 — the AI
  calls happen after a session ends, never in the live audio path.

## Phase 2: real AI, in progress

The user explicitly asked to move past Phase 1's AI boundary: real
transcription, real summarization/task-extraction, and (planned) Google
Calendar / Notion integration. This was a deliberate product decision, not
scope creep — captured here so the "Hard rules" above don't read as
silently contradicted.

- **Transcription**: on-device (`speech_to_text`), live during a session,
  chosen over a cloud API to stay local-first for as long as accuracy
  allows. See `docs/known-limitations.md` for what's actually been
  verified about this (one device, short window).
- **Reflection** (summary/key ideas/action points/open questions): calls
  Google Gemini with the session transcript. This is the one place in the
  app that calls a real cloud AI provider — gated behind
  `GeminiConfig.isConfigured`, so the app still works with no key
  configured (reflection silently no-ops, same as Phase 1's behavior).
- **API key handling is a known, temporary shortcut** — see
  `docs/known-limitations.md` before treating this as production-ready.
- **Calendar**: built (`lib/services/calendar/`, `lib/features/scheduling/`)
  — Google Sign-In + Calendar API, reached from Session Details. Every
  event creation requires the user to pick which action points to
  schedule and confirm a button stating exactly how many events will be
  created — never silent. Not yet end-to-end verified against a real
  Google account; see `docs/known-limitations.md`.
- **Notion**: not built yet. Same confirmation-required shape as
  Calendar, once the user creates a Notion integration token.

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
    reflection/        # interface + real Gemini impl (Phase 2)
    communication/      # interface + mock only
    settings/
  services/
    audio/             # native-backed monitoring engine
    transcription/      # interface + real on-device impl (Phase 2)
    ai/                 # Gemini config/client + mock summarization
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
