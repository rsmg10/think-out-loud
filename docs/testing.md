# Testing

Compiling is not testing. Every item below needs an actual pass/fail,
not an assumption.

## Automated

Priority order:
1. Thinking state transitions (`idle → starting → thinking → stopping →
   saved`, plus the `interrupted` branch).
2. Session persistence (create, restart app, verify survival; delete a
   session and verify both the DB row *and* its audio file on disk are
   gone; "delete all" removes every audio file, not just metadata).
3. Service abstraction contracts (mocks satisfy the interfaces; UI never
   imports a concrete AI provider directly).
4. Error states (permission denied, no audio route, storage failure) —
   verify the UI reaches the right error state, not just that no
   exception is thrown.

## Manual — fresh install

Launch → grant mic permission → press Think → speak → hear yourself →
press Stop → save → open the session from History.

## Manual — permissions

Deny mic permission → verify the app explains why it's needed and offers
a path to system settings → grant it there → return to app → verify it
recovers without a restart.

## Manual — headphones (the critical one)

Run the latency test protocol in `audio-architecture.md` on:
- at least one wired headphone set, if available in this environment
- at least one Bluetooth headphone set, if available in this environment

Report device model, headphone type/model, and subjective + (if possible)
measured round-trip latency for each. If neither is available in this
environment, say so explicitly rather than marking this untested-but-fine.

## Manual — interruption

- Background the app mid-session — verify graceful pause/resume.
- Lock the screen where supported — same.
- Disconnect Bluetooth mid-session — verify no crash, no speaker feedback,
  a clear message to the user.
- Trigger an audio interruption (e.g. incoming call if testable) — verify
  pause/resume.

## Manual — UI

Different screen sizes, long session lists, empty states, error states,
no overflow/clipping, light/dark mode if implemented, basic accessibility
(screen reader labels on the Think/Stop buttons at minimum).

## Final report template

1. Architecture overview
2. Audio architecture and package choice actually used, with rationale
3. Design system used — the real one if found, or confirmation the
   fallback in `design.md` was used
4. Files/features implemented
5. Tests performed (automated + manual, from this checklist)
6. Actual result of the manual audio/headphone test — device, headphone
   type, subjective + measured latency, or explicit statement that
   headphone hardware wasn't available to test in this environment
7. Known limitations
8. How to run the app
9. Required configuration
10. Recommended next development step
