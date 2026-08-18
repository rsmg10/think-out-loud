/// Reads the Gemini API key at compile time via `--dart-define`, e.g.:
///
///   flutter run --dart-define=GEMINI_API_KEY=your-key-here
///
/// TEMPORARY, KNOWINGLY INSECURE FOR ANYTHING BEYOND THE DEVELOPER'S OWN
/// DEVICE: this is the "local-only dev key for now" option the user chose
/// over standing up a backend proxy (see the Phase 2 plan). A key passed
/// this way is baked into the compiled binary and can be extracted by
/// decompiling the APK/IPA — CLAUDE.md's original hard rule ("never embed
/// provider API keys client-side") is being consciously superseded here,
/// not overlooked. Before this app is ever installed on a device that
/// isn't the developer's own, this must become a real backend proxy that
/// holds the key server-side, per docs/known-limitations.md.
class GeminiConfig {
  GeminiConfig._();

  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;
}
