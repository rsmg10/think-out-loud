/// Small, local-only user preferences — not to be confused with the
/// session model. Kept separate from sqlite (AppDatabase) since these
/// are single scalar values, not records.
abstract class UserPreferencesService {
  /// Whether to route mic input through the connected Bluetooth
  /// headset (via SCO) when available.
  ///
  /// Default true. SCO is the only way to capture audio from a
  /// Bluetooth headset's mic, but it's a narrowband voice-call codec
  /// with its own protocol latency floor (~100-200ms) — genuinely
  /// lower quality and higher latency than the phone's own mic. Users
  /// without wired headphones need a way to trade "hands-free/pocket
  /// use" against "clarity and latency" themselves; the app can't pick
  /// correctly for them.
  Future<bool> getPreferBluetoothMic();

  Future<void> setPreferBluetoothMic(bool value);
}
