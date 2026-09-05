import 'package:flutter/material.dart';

/// Subtle only — a gentle waveform, soft transitions, nothing that draws
/// attention to itself, per docs/design.md. Centralized so every screen's
/// micro-interactions share the same rhythm instead of ad-hoc durations.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;

  /// Subtle press-down feedback for tappable circles/cards — restores on
  /// release. Kept small (0.96, not 0.9) so it reads as a soft press, not
  /// a bounce.
  static const double pressedScale = 0.96;
}
