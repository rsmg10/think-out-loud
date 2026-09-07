import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';

/// A subtle waveform driven by input level only — motion should not draw
/// attention to itself, per docs/design.md.
class WaveformVisualizer extends StatelessWidget {
  final double level;

  const WaveformVisualizer({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: 48,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.fast,
        curve: AppMotion.enter,
        child: CustomPaint(
          size: const Size(double.infinity, 48),
          painter: _WaveformPainter(level: level, color: color),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double level;
  final Color color;

  _WaveformPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 24;
    final barWidth = size.width / (barCount * 1.6);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final progress = i / barCount;
      final falloff = 1 - (progress - 0.5).abs() * 2;
      final barHeight =
          (4 + level * size.height * 0.85 * falloff).clamp(4.0, size.height);
      final x = i * (size.width / barCount);
      final rect = Rect.fromCenter(
        center: Offset(x + barWidth / 2, centerY),
        width: barWidth,
        height: barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.color != color;
  }
}
