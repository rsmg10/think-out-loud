/// OAuth client IDs for Google Sign-In, created in Google Cloud Console
/// (Phase B — see CLAUDE.md and the session's plan for the walkthrough).
///
/// Unlike the Gemini API key, these are NOT secrets — Google verifies the
/// calling app via its package name + signing certificate (Android) or
/// bundle ID (iOS), not by keeping the client ID hidden. Safe to commit.
/// The corresponding Web client's *secret* was deliberately never saved
/// anywhere in this codebase — the mobile sign-in flow only needs the
/// Web client's ID (as `serverClientId`), never its secret.
class GoogleCalendarConfig {
  GoogleCalendarConfig._();

  /// The Web application OAuth client's ID. Required by google_sign_in on
  /// Android (Credential Manager) even though this app has no server —
  /// see the package's docs for why.
  static const String serverClientId =
      '13506327160-q6ta074th81v3mei3kr25k0ekg6bc0ht.apps.googleusercontent.com';

  /// Only lets the app manage events it created itself — not full
  /// calendar access. See the OAuth consent screen configuration.
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/calendar.events.owned',
  ];
}
