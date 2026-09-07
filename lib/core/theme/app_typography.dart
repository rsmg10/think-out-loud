import 'package:flutter/material.dart';

/// Lora (display/title) + Raleway (body) — a calm serif/humanist-sans
/// pairing for reading-focused, unhurried interfaces, per docs/design.md.
/// Bundled as local font assets (see pubspec.yaml), not fetched at
/// runtime, to stay consistent with this app's local-first principle.
class AppTypography {
  AppTypography._();

  static const String displayFamily = 'Lora';
  static const String bodyFamily = 'Raleway';

  static TextTheme textTheme(Color textColor, Color mutedColor) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 40,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        height: 1.15,
        color: textColor,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 30,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.25,
        height: 1.2,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: textColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: mutedColor,
      ),
      labelLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: textColor,
      ),
    );
  }
}
