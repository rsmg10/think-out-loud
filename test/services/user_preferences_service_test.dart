import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:think_out_loud/services/settings/shared_prefs_user_preferences_service.dart';

void main() {
  late SharedPrefsUserPreferencesService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SharedPrefsUserPreferencesService();
  });

  test('defaults to true (Bluetooth mic) when nothing has been saved yet', () async {
    expect(await service.getPreferBluetoothMic(), isTrue);
  });

  test('setPreferBluetoothMic persists the value across reads', () async {
    await service.setPreferBluetoothMic(false);

    expect(await service.getPreferBluetoothMic(), isFalse);
  });

  test('value survives a fresh service instance (simulated app restart)', () async {
    await service.setPreferBluetoothMic(false);

    final reopened = SharedPrefsUserPreferencesService();

    expect(await reopened.getPreferBluetoothMic(), isFalse);
  });
}
