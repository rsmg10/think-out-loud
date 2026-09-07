import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/theme/app_motion.dart';
import 'package:think_out_loud/features/thinking/widgets/think_button.dart';

void main() {
  Widget wrap(Widget child, {required bool disableAnimations}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('collapses press-scale and loading transitions to zero duration '
      'when the OS reduce-motion setting is on', (tester) async {
    await tester.pumpWidget(
      wrap(ThinkButton(onPressed: () {}), disableAnimations: true),
    );

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));

    expect(scale.duration, Duration.zero);
    expect(container.duration, Duration.zero);
  });

  testWidgets('uses AppMotion durations when reduce-motion is off', (tester) async {
    await tester.pumpWidget(
      wrap(ThinkButton(onPressed: () {}), disableAnimations: false),
    );

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));

    expect(scale.duration, AppMotion.fast);
    expect(scale.duration, isNot(Duration.zero));
    expect(container.duration, AppMotion.medium);
    expect(container.duration, isNot(Duration.zero));
  });
}
