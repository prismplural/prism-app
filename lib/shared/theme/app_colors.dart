import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color prismPurple = Color(0xFFB498C2);
  static const Color prismPurpleLight = Color(0xFFA384B0);

  // Semantic warm palette
  static const Color warmWhite = Color(0xFFF0EDE6);
  static const Color warmBlack = Color(0xFF4A4540);
  static const Color warmOffWhite = Color(0xFFFDFBF6);

  // Warm surfaces — light mode (parchment)
  static const Color parchment = Color(0xFFF5F0E6);
  static const Color parchmentElevated = Color(0xFFEDE8DC);
  static const Color parchmentStrong = Color(0xFFE2DCD0);

  // Warm surfaces — dark mode (charcoal)
  static const Color charcoal = Color(0xFF33302B);
  static const Color charcoalElevated = Color(0xFF3B3732);
  static const Color charcoalSurface = Color(0xFF423E38);
  static const Color charcoalStrong = Color(0xFF4D4842);

  // Warm surfaces — OLED (pure black scaffold, warm-tinted elevations)
  static const Color oledSurface1 = Color(0xFF1A1612);
  static const Color oledSurface2 = Color(0xFF211D17);
  static const Color oledSurface3 = Color(0xFF292420);
  static const Color oledSurface4 = Color(0xFF312B25);

  // Feature accent spectrum — dark mode
  static const Color accentPurpleDark = Color(0xFFB498C2);
  static const Color accentRoseDark = Color(0xFFC98E8E);
  static const Color accentSageDark = Color(0xFF8DA399);
  static const Color accentBlueDark = Color(0xFF7A9BA8);
  static const Color accentAmberDark = Color(0xFFB58D67);
  static const Color accentLavenderDark = Color(0xFF9B8EAD);

  // Feature accent spectrum — light mode
  static const Color accentPurpleLight = Color(0xFF9070A0);
  static const Color accentRoseLight = Color(0xFFA06868);
  static const Color accentSageLight = Color(0xFF5A7E68);
  static const Color accentBlueLight = Color(0xFF4E7A8A);
  static const Color accentAmberLight = Color(0xFF8A6538);
  static const Color accentLavenderLight = Color(0xFF7A6E96);

  // Status
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Categories (muted accent spectrum)
  static const Color fronting = Color(0xFFB498C2); // purple
  static const Color coFronting = Color(0xFFC98E8E); // rose
  static const Color nearby = Color(0xFF8DA399); // sage
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
