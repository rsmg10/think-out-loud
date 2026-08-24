# Known limitations

Tracks conscious shortcuts and unverified areas, so they don't get
mistaken for finished work. See `CLAUDE.md`'s "Phase 2" section for the
decision history behind these.

## Gemini API key is embedded client-side (temporary)

`lib/services/ai/gemini_config.dart` reads the key via
`String.fromEnvironment('GEMINI_API_KEY')`, passed at build/run time with
`--dart-define`. This is **not committed to source control** (nothing to
leak in the repo), but it **is baked into the compiled binary** — anyone
who gets the APK/IPA can extract it by decompiling.

This was an explicit, informed choice (not an oversight): the user chose
"local-only dev key for now" over standing up a backend proxy, to get
real AI features working before investing in that infrastructure. It is
only acceptable as long as:

- the app is only ever installed on the developer's own device(s), and
- the Gemini API key has spending limits / alerts configured in Google
  AI Studio, in case it does leak.

**Before this app is installed on anyone else's device**, this must
become a real backend (Cloud Function, Cloudflare Worker, or similar)
that holds the key server-side and proxies the Gemini request — the app
would call that backend instead of Gemini directly. The
`ReflectionService` interface (`lib/features/reflection/reflection_service.dart`)
doesn't need to change for this; only `GeminiReflectionService`'s
implementation would be replaced with an HTTP client hitting the backend.

## On-device transcription: concurrent mic access

`lib/services/transcription/on_device_transcription_service.dart` runs
the platform speech recognizer (`speech_to_text`) alongside the native
audio monitoring engine's own mic tap. Verified to coexist on **one
Android device** (Xiaomi/MIUI, Android 13) over a short test window —
not confirmed on iOS, other Android OEMs, or over a long (multi-minute)
session. If transcripts come back empty or garbled on other hardware,
this is the first thing to re-check.

## Transcription accuracy / cost

Per the user's direction: start with on-device (free, private) speech
recognition; revisit a paid cloud transcription API (e.g. a Whisper-class
model) later if accuracy turns out to be inadequate for real sessions.
No such evaluation has been done yet — on-device accuracy in practice is
unverified beyond the A0 spike, which didn't test real speech content.

## Google Calendar integration (built, not yet end-to-end verified)

`lib/services/calendar/google_calendar_service.dart` +
`lib/features/scheduling/schedule_action_points_screen.dart` are built:
Google Sign-In (via `google_sign_in`'s Credential Manager flow on
Android) and event creation (via `googleapis`'s `CalendarApi`), reached
from Session Details' "Schedule with Google Calendar" button whenever a
session has action points. Every event creation requires the user to
review the list, pick which items to schedule, and tap a button that
states exactly how many events will be created — never silent.

Verified: `flutter analyze`, `flutter test`, `flutter build apk --debug`
all pass, and the app launches without crashing with the new
`google_sign_in`/`googleapis`/`http` dependencies present. **Not
verified**: an actual sign-in + event creation against a real Google
account has not happened — that needs the user's phone and their own
Google consent. The OAuth client IDs in
`lib/services/calendar/google_calendar_config.dart` are configured for
Android only, tied to *this sandboxed environment's* debug keystore
SHA-1 — sign-in will fail on builds signed by a different machine/
keystore until that keystore's SHA-1 is also registered as an Android
OAuth client in the same Google Cloud project.

Scope: `.../auth/calendar.events.owned` — the app can only create/edit/
delete events it created itself, not manage the user's full calendar.

## Notion integration

Not built yet. Same shape as Calendar (user-confirmed, per-batch
writes) once the user creates a Notion internal integration token.
