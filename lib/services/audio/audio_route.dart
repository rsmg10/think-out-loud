/// Current output route, as far as the platform can report it. Speaker
/// monitoring is unsafe (feedback) and must be blocked with a warning per
/// docs/audio-architecture.md.
enum AudioRoute { headphones, bluetooth, speaker, unknown }

extension AudioRouteSafety on AudioRoute {
  bool get isSafeForMonitoring =>
      this == AudioRoute.headphones || this == AudioRoute.bluetooth;
}
