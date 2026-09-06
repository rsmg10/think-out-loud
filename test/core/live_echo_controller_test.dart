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
      () => preferences.getLiveEchoEnabled(),
    ).thenAnswer((_) async => false);

    final controller = LiveEchoController(preferences);
    // Synchronous default before the async load resolves.
    expect(controller.state, isTrue);

    await _settle();

    expect(controller.state, isFalse);
    controller.dispose();
  });

  test('setLiveEchoEnabled updates state and persists the new value', () async {
    when(
      () => preferences.getLiveEchoEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => preferences.setLiveEchoEnabled(any()),
    ).thenAnswer((_) async {});

    final controller = LiveEchoController(preferences);
    await _settle();

    await controller.setLiveEchoEnabled(false);

    expect(controller.state, isFalse);
    verify(() => preferences.setLiveEchoEnabled(false)).called(1);
    controller.dispose();
  });
}
