import 'package:shared_preferences/shared_preferences.dart';

import 'user_preferences_service.dart';

class SharedPrefsUserPreferencesService implements UserPreferencesService {
  static const _preferBluetoothMicKey = 'preferBluetoothMic';

  @override
  Future<bool> getPreferBluetoothMic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_preferBluetoothMicKey) ?? true;
  }

  @override
  Future<void> setPreferBluetoothMic(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferBluetoothMicKey, value);
  }
}
