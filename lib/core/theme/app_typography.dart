import 'package:flutter/material.dart';

/// A title/display size distinguished by weight and spacing rather than a
/// separate bundled font family — no font assets were available to embed
/// in this environment, so both display and body text use the platform
/// system font (Roboto/San Francisco). Follow-up: swap [displayFamily] for
/// a bundled humanist/serif face if one is added to assets/fonts later.
class AppTypography {
  AppTypography._();

  static const String? displayFamily = null;

  static TextTheme textTheme(Color textColor, Color mutedColor) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 40,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
        height: 1.15,
        color: textColor,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 30,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        height: 1.2,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: textColor,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: mutedColor,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: textColor,
      ),
    );
  }
}
