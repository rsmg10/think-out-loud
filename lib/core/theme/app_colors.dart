import 'package:flutter/material.dart';

/// Restrained neutral palette per docs/design.md's fallback direction:
/// warm off-white / near-black in light mode, calm dark mode, one accent
/// used sparingly (mainly the Think button and active states).
class AppColors {
  AppColors._();

  static const Color lightBackground = Color(0xFFFAF7F2);
  static const Color lightSurface = Color(0xFFF1ECE3);
  static const Color lightText = Color(0xFF1C1A17);
  static const Color lightTextMuted = Color(0xFF6B6459);
  static const Color lightBorder = Color(0xFFE2DACB);

  static const Color darkBackground = Color(0xFF15130F);
  static const Color darkSurface = Color(0xFF201D18);
  static const Color darkText = Color(0xFFF3EFE7);
  static const Color darkTextMuted = Color(0xFFA69C8C);
  static const Color darkBorder = Color(0xFF3A362D);

  /// Single accent, used sparingly: the Think button and active states.
  static const Color accent = Color(0xFF2F6F6B);
  static const Color accentOnDark = Color(0xFF6FBAB4);

  static const Color error = Color(0xFFB3492F);
}
