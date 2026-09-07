import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_out_loud/core/theme/app_motion.dart';
import 'package:think_out_loud/features/thinking/widgets/waveform_visualizer.dart';

void main() {
  Widget wrap(Widget child, {required bool disableAnimations}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('collapses to zero duration when the OS reduce-motion setting is on',
      (tester) async {
    await tester.pumpWidget(
      wrap(const WaveformVisualizer(level: 0.5), disableAnimations: true),
    );

    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));

    expect(container.duration, Duration.zero);
  });

  testWidgets('uses AppMotion.fast when reduce-motion is off', (tester) async {
    await tester.pumpWidget(
      wrap(const WaveformVisualizer(level: 0.5), disableAnimations: false),
    );

    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));

    expect(container.duration, AppMotion.fast);
    expect(container.duration, isNot(Duration.zero));
  });
}
