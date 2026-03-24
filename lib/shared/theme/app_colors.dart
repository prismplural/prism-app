import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color prismPurple = Color(0xFFAF8EE9);

  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Categories
  static const Color fronting = Color(0xFF8B5CF6);
  static const Color coFronting = Color(0xFFA78BFA);
  static const Color nearby = Color(0xFFC4B5FD);
  static const Color dormant = Color(0xFF94A3B8);

  /// Generate a distinct color for a member at [index] in a list.
  ///
  /// Distributes hues evenly around the color wheel, starting opposite
  /// the accent color so generated colors contrast with the brand palette.
  static Color generatedColor(
      int index, Color accentColor, Brightness brightness) {
    // Start 180° from the accent so the first generated color contrasts well,
    // then space subsequent colors by the golden angle for max separation.
    final accentHue = HSLColor.fromColor(accentColor).hue;
    final hue = (accentHue + 180.0 + index * 137.508) % 360;
    final saturation = brightness == Brightness.light ? 0.55 : 0.50;
    final lightness = brightness == Brightness.light ? 0.45 : 0.65;
    return HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
  }

  /// Parse a hex color string (with or without leading '#') into a [Color].
  ///
  /// Returns [prismPurple] if parsing fails (e.g. corrupted DB data).
  static Color fromHex(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.startsWith('#')) {
        hex = hex.substring(1);
      }
      if (hex.length == 6) {
        buffer.write('FF');
      }
      buffer.write(hex);
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return prismPurple;
    }
  }
}
