import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:think_out_loud/core/providers.dart';
import 'package:think_out_loud/services/settings/user_preferences_service.dart';

class MockUserPreferencesService extends Mock implements UserPreferencesService {}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late MockUserPreferencesService preferences;

  setUp(() {
    preferences = MockUserPreferencesService();
  });

  test('loads the persisted value asynchronously after construction', () async {
    when(
      () => preferences.getPreferBluetoothMic(),
    ).thenAnswer((_) async => false);

    final controller = PreferBluetoothMicController(preferences);
    // Synchronous default before the async load resolves.
    expect(controller.state, isTrue);

    await _settle();

    expect(controller.state, isFalse);
    controller.dispose();
  });

  test('setPreferBluetoothMic updates state and persists the new value', () async {
    when(
      () => preferences.getPreferBluetoothMic(),
    ).thenAnswer((_) async => true);
    when(
      () => preferences.setPreferBluetoothMic(any()),
    ).thenAnswer((_) async {});

    final controller = PreferBluetoothMicController(preferences);
    await _settle();

    await controller.setPreferBluetoothMic(false);

    expect(controller.state, isFalse);
    verify(() => preferences.setPreferBluetoothMic(false)).called(1);
    controller.dispose();
  });
}
