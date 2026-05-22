import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/system_settings.dart'
    show PaletteContrast, PaletteMood, PaletteSource;
import 'accent_legibility.dart';
import 'app_colors.dart';
import 'prism_shapes.dart';
import 'prism_theme_flavor.dart';
import 'prism_tokens.dart';

/// Holds all variant-specific colors so [AppTheme._buildTheme] can apply
/// the same component structure for light, dark, and OLED variants.
class _ThemeColors {
  const _ThemeColors({
    required this.scaffold,
    required this.cardColor,
    required this.fillColor,
    required this.borderColor,
    required this.focusBorderColor,
    required this.dividerColor,
    required this.sheetBg,
    required this.dialogBg,
    required this.popupBg,
    required this.snackBarBg,
    required this.dragHandleColor,
    required this.filledButtonBg,
    required this.filledButtonFg,
    required this.iconButtonBg,
    required this.iconButtonFg,
    required this.textButtonFg,
    required this.isDark,
  });

  final Color scaffold;
  final Color cardColor;
  final Color fillColor;
  final Color borderColor;
  final Color focusBorderColor;
  final Color dividerColor;
  final Color sheetBg;
  final Color dialogBg;
  final Color popupBg;
  final Color snackBarBg;
  final Color dragHandleColor;
  final Color filledButtonBg;
  final Color filledButtonFg;
  final Color iconButtonBg;
  final Color iconButtonFg;
  final Color textButtonFg;
  final bool isDark;
}

class AppTheme {
  AppTheme._();

  // Flutter on iOS/macOS already defaults to SF Pro.
  // On Android it defaults to Roboto. No override needed.
  //
  // Linux has no single default — Flutter engine's built-in chain is
  // "Ubuntu", "Cantarell", "DejaVu Sans", "Liberation Sans", "Arial" (see
  // engine PR #16928). We mirror that chain explicitly, prepend "Adwaita
  // Sans" (GNOME 48+ default, March 2025), and append our bundled
  // NotoColorEmoji (registered via FontLoader in main.dart) for color
  // emoji — the system default on Linux distros is monochrome NotoEmoji,
  // if present at all.
  //
  // Applied via TextTheme.apply(fontFamilyFallback:), so:
  //   - null-fontFamily styles (body/label/title) use Adwaita Sans as the
  //     effective primary and fall through the list for missing glyphs.
  //   - Unbounded styles (display/headline) keep Unbounded as primary and
  //     only consult this list for codepoints Unbounded lacks (mainly
  //     emoji).
  static List<String>? get _linuxFontFamilyFallback {
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return const [
        'Adwaita Sans',
        'Ubuntu',
        'Cantarell',
        'DejaVu Sans',
        'Liberation Sans',
        'Arial',
        'NotoColorEmoji',
      ];
    }
    return null;
  }

  static bool get _isDesktopPlatform {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  /// Strip M3 default letter spacing. On desktop, also tighten font sizes —
  /// M3 defaults are sized for phones held at arm's length.
  static TextTheme _adjustTextTheme(TextTheme textTheme) {
    if (!_isDesktopPlatform) {
      // Mobile: only strip letter spacing, keep M3 default sizes.
      return TextTheme(
        displayLarge: textTheme.displayLarge?.copyWith(
          letterSpacing: 0.5,
          fontFamily: 'Unbounded',
          fontWeight: FontWeight.w700,
        ),
        displayMedium: textTheme.displayMedium?.copyWith(
          letterSpacing: 0.5,
          fontFamily: 'Unbounded',
          fontWeight: FontWeight.w700,
        ),
        displaySmall: textTheme.displaySmall?.copyWith(
          letterSpacing: 0.5,
          fontFamily: 'Unbounded',
          fontWeight: FontWeight.w700,
        ),
        headlineLarge: textTheme.headlineLarge?.copyWith(
          letterSpacing: 0.5,
          fontFamily: 'Unbounded',
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(letterSpacing: 0),
        headlineSmall: textTheme.headlineSmall?.copyWith(letterSpacing: 0),
        titleLarge: textTheme.titleLarge?.copyWith(letterSpacing: 0),
        titleMedium: textTheme.titleMedium?.copyWith(letterSpacing: 0),
        titleSmall: textTheme.titleSmall?.copyWith(letterSpacing: 0),
        bodyLarge: textTheme.bodyLarge?.copyWith(letterSpacing: 0),
        bodyMedium: textTheme.bodyMedium?.copyWith(letterSpacing: 0),
        bodySmall: textTheme.bodySmall?.copyWith(letterSpacing: 0),
        labelLarge: textTheme.labelLarge?.copyWith(letterSpacing: 0),
        labelMedium: textTheme.labelMedium?.copyWith(letterSpacing: 0),
        labelSmall: textTheme.labelSmall?.copyWith(letterSpacing: 0),
      );
    }

    // Desktop: strip letter spacing and tighten font sizes.
    return TextTheme(
      displayLarge: textTheme.displayLarge?.copyWith(
        letterSpacing: 0.5,
        fontSize: 48,
        fontFamily: 'Unbounded',
        fontWeight: FontWeight.w700,
      ),
      displayMedium: textTheme.displayMedium?.copyWith(
        letterSpacing: 0.5,
        fontSize: 38,
        fontFamily: 'Unbounded',
        fontWeight: FontWeight.w700,
      ),
      displaySmall: textTheme.displaySmall?.copyWith(
        letterSpacing: 0.5,
        fontSize: 30,
        fontFamily: 'Unbounded',
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: textTheme.headlineLarge?.copyWith(
        letterSpacing: 0.5,
        fontSize: 26,
        fontFamily: 'Unbounded',
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        letterSpacing: 0,
        fontSize: 22,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        letterSpacing: 0,
        fontSize: 19,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        letterSpacing: 0,
        fontSize: 18,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        letterSpacing: 0,
        fontSize: 14,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        letterSpacing: 0,
        fontSize: 13,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(letterSpacing: 0, fontSize: 14),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        letterSpacing: 0,
        fontSize: 13,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(letterSpacing: 0, fontSize: 11),
      labelLarge: textTheme.labelLarge?.copyWith(
        letterSpacing: 0,
        fontSize: 13,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        letterSpacing: 0,
        fontSize: 11,
      ),
      labelSmall: textTheme.labelSmall?.copyWith(
        letterSpacing: 0,
        fontSize: 10,
      ),
    );
  }

  static TextStyle _textStyleWithoutDisplayFont(TextStyle style) {
    return TextStyle(
      inherit: style.inherit,
      color: style.color,
      backgroundColor: style.backgroundColor,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      letterSpacing: 0,
      wordSpacing: style.wordSpacing,
      textBaseline: style.textBaseline,
      height: style.height,
      leadingDistribution: style.leadingDistribution,
      locale: style.locale,
      foreground: style.foreground,
      background: style.background,
      shadows: style.shadows,
      fontFeatures: style.fontFeatures,
      fontVariations: style.fontVariations,
      decoration: style.decoration,
      decorationColor: style.decorationColor,
      decorationStyle: style.decorationStyle,
      decorationThickness: style.decorationThickness,
      debugLabel: style.debugLabel,
      fontFamilyFallback: style.fontFamilyFallback,
      overflow: style.overflow,
    );
  }

  /// Remove Unbounded from display/headline roles so disabled display type uses
  /// the platform font instead of the bundled display font.
  static ThemeData withoutDisplayFont(ThemeData theme) {
    final textTheme = theme.textTheme;
    return theme.copyWith(
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge == null
            ? null
            : _textStyleWithoutDisplayFont(textTheme.displayLarge!),
        displayMedium: textTheme.displayMedium == null
            ? null
            : _textStyleWithoutDisplayFont(textTheme.displayMedium!),
        displaySmall: textTheme.displaySmall == null
            ? null
            : _textStyleWithoutDisplayFont(textTheme.displaySmall!),
        headlineLarge: textTheme.headlineLarge == null
            ? null
            : _textStyleWithoutDisplayFont(textTheme.headlineLarge!),
      ),
    );
  }

  static bool _isMonochromePaletteSeed(Color seedColor) {
    return HSLColor.fromColor(seedColor).saturation <= 0.05;
  }

  static DynamicSchemeVariant dynamicSchemeVariantForPalette(
    PaletteMood mood, {
    Color? seedColor,
  }) {
    if (seedColor != null && _isMonochromePaletteSeed(seedColor)) {
      return DynamicSchemeVariant.monochrome;
    }

    return switch (mood) {
      PaletteMood.tonal => DynamicSchemeVariant.tonalSpot,
      PaletteMood.vibrant => DynamicSchemeVariant.vibrant,
      PaletteMood.expressive => DynamicSchemeVariant.expressive,
      PaletteMood.fidelity => DynamicSchemeVariant.fidelity,
      PaletteMood.monochrome => DynamicSchemeVariant.monochrome,
    };
  }

  static double _contrastLevelFor(PaletteContrast contrast) {
    return switch (contrast) {
      PaletteContrast.soft => -0.25,
      PaletteContrast.standard => 0.0,
      PaletteContrast.high => 0.5,
    };
  }

  static ColorScheme _paletteColorScheme({
    required ColorScheme? dynamicScheme,
    required Brightness brightness,
    required PaletteSource source,
    required String seedColorHex,
    required PaletteMood mood,
    required PaletteContrast contrast,
  }) {
    if (source == PaletteSource.device && dynamicScheme != null) {
      if (mood == PaletteMood.tonal && contrast == PaletteContrast.standard) {
        return dynamicScheme;
      }
      return ColorScheme.fromSeed(
        seedColor: dynamicScheme.primary,
        brightness: brightness,
        dynamicSchemeVariant: dynamicSchemeVariantForPalette(
          mood,
          seedColor: dynamicScheme.primary,
        ),
        contrastLevel: _contrastLevelFor(contrast),
      );
    }
    final seedColor = AppColors.fromHex(seedColorHex);
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: dynamicSchemeVariantForPalette(
        mood,
        seedColor: seedColor,
      ),
      contrastLevel: _contrastLevelFor(contrast),
    );
  }

  static Color _tintPaletteSurface(Color base, Color accent, double alpha) {
    return Color.alphaBlend(accent.withValues(alpha: alpha), base);
  }

  static ColorScheme _paletteSurfaceTintedScheme(
    ColorScheme colorScheme,
    Color accent, {
    required bool isDark,
  }) {
    final lowestAlpha = isDark ? 0.08 : 0.11;
    final lowAlpha = isDark ? 0.11 : 0.15;
    final containerAlpha = isDark ? 0.14 : 0.18;
    final highAlpha = isDark ? 0.17 : 0.21;
    final highestAlpha = isDark ? 0.20 : 0.24;

    return colorScheme.copyWith(
      surface: _tintPaletteSurface(
        colorScheme.surface,
        accent,
        isDark ? lowAlpha : lowestAlpha,
      ),
      surfaceContainerLowest: _tintPaletteSurface(
        colorScheme.surfaceContainerLowest,
        accent,
        lowestAlpha,
      ),
      surfaceContainerLow: _tintPaletteSurface(
        colorScheme.surfaceContainerLow,
        accent,
        lowAlpha,
      ),
      surfaceContainer: _tintPaletteSurface(
        colorScheme.surfaceContainer,
        accent,
        containerAlpha,
      ),
      surfaceContainerHigh: _tintPaletteSurface(
        colorScheme.surfaceContainerHigh,
        accent,
        highAlpha,
      ),
      surfaceContainerHighest: _tintPaletteSurface(
        colorScheme.surfaceContainerHighest,
        accent,
        highestAlpha,
      ),
    );
  }

  static _ThemeColors _paletteThemeColors(
    ColorScheme colorScheme,
    Color accent, {
    required bool isDark,
  }) {
    if (isDark) {
      return _ThemeColors(
        scaffold: colorScheme.surfaceContainerLow,
        cardColor: colorScheme.surfaceContainer,
        fillColor: colorScheme.surfaceContainerHigh,
        borderColor: colorScheme.onSurface.withValues(alpha: 0.1),
        focusBorderColor: accent.withValues(alpha: 0.7),
        dividerColor: colorScheme.onSurface.withValues(alpha: 0.06),
        sheetBg: colorScheme.surfaceContainerHigh,
        dialogBg: colorScheme.surfaceContainerHigh,
        popupBg: colorScheme.surfaceContainerHigh,
        snackBarBg: colorScheme.inverseSurface,
        dragHandleColor: colorScheme.onSurface.withValues(alpha: 0.3),
        filledButtonBg: colorScheme.primary,
        filledButtonFg: colorScheme.onPrimary,
        iconButtonBg: colorScheme.primary.withValues(alpha: 0.16),
        iconButtonFg: colorScheme.primary,
        textButtonFg: colorScheme.primary,
        isDark: true,
      );
    }

    return _ThemeColors(
      scaffold: colorScheme.surfaceContainerLowest,
      cardColor: colorScheme.surfaceContainerLow,
      fillColor: colorScheme.primary.withValues(alpha: 0.05),
      borderColor: colorScheme.onSurface.withValues(alpha: 0.1),
      focusBorderColor: accent.withValues(alpha: 0.6),
      dividerColor: colorScheme.onSurface.withValues(alpha: 0.06),
      sheetBg: colorScheme.surfaceContainerLow,
      dialogBg: colorScheme.surfaceContainerLow,
      popupBg: colorScheme.surfaceContainerLow,
      snackBarBg: colorScheme.inverseSurface,
      dragHandleColor: colorScheme.onSurface.withValues(alpha: 0.2),
      filledButtonBg: colorScheme.primary,
      filledButtonFg: colorScheme.onPrimary,
      iconButtonBg: colorScheme.primary.withValues(alpha: 0.12),
      iconButtonFg: colorScheme.primary,
      textButtonFg: colorScheme.primary,
      isDark: false,
    );
  }

  static ThemeData _paletteThemeFromScheme({
    required ColorScheme baseColorScheme,
    Color? surfaceTintColor,
    required bool isDark,
    required PrismShapes shapes,
  }) {
    final accent = contrastAdjustedAccent(
      baseColorScheme.primary,
      isDark
          ? baseColorScheme.surfaceContainerLow
          : baseColorScheme.surfaceContainerLowest,
    );
    final surfaceTint = surfaceTintColor ?? baseColorScheme.primary;
    final colorScheme = _paletteSurfaceTintedScheme(
      baseColorScheme.copyWith(
        primary: accent,
        onPrimary: highContrastForeground(accent),
      ),
      surfaceTint,
      isDark: isDark,
    );

    return _buildTheme(
      colorScheme,
      accent,
      _paletteThemeColors(colorScheme, accent, isDark: isDark),
      shapes,
      PrismThemeFlavor.palette,
    );
  }

  /// Builds a seeded Palette-style theme for a local subtree, preserving the
  /// parent typography and shape settings while replacing the palette seed.
  static ThemeData localPaletteTheme(
    ThemeData baseTheme, {
    required Color seedColor,
    PaletteMood paletteMood = PaletteMood.tonal,
    PaletteContrast paletteContrast = PaletteContrast.standard,
  }) {
    final isDark = baseTheme.brightness == Brightness.dark;
    final shapes =
        baseTheme.extension<PrismShapes>() ??
        const PrismShapes(cornerStyle: CornerStyle.rounded);
    final localTheme = _paletteThemeFromScheme(
      baseColorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        dynamicSchemeVariant: dynamicSchemeVariantForPalette(
          paletteMood,
          seedColor: seedColor,
        ),
        contrastLevel: _contrastLevelFor(paletteContrast),
      ),
      surfaceTintColor: seedColor,
      isDark: isDark,
      shapes: shapes,
    );

    return localTheme.copyWith(
      textTheme: baseTheme.textTheme,
      primaryTextTheme: baseTheme.primaryTextTheme,
    );
  }

  /// Minimal switch theme shared across all variants.
  static SwitchThemeData _switchTheme({
    required ColorScheme colorScheme,
    required Color accent,
  }) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final unselectedTrack = colorScheme.surfaceContainerHighest;
    final unselectedThumb = isDark
        ? colorScheme.onSurfaceVariant
        : colorScheme.surfaceContainerLow;
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        if (states.contains(WidgetState.selected)) {
          return disabled
              ? colorScheme.onPrimary.withValues(alpha: 0.62)
              : colorScheme.onPrimary;
        }
        if (disabled) return colorScheme.onSurface.withValues(alpha: 0.24);
        return unselectedThumb;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        if (states.contains(WidgetState.selected)) {
          return disabled ? accent.withValues(alpha: 0.34) : accent;
        }
        return disabled
            ? unselectedTrack.withValues(alpha: 0.42)
            : unselectedTrack;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return colorScheme.outlineVariant;
      }),
    );
  }

  /// Shared component theme builder. Applies all component themes using the
  /// provided [colorScheme], [accent], and variant-specific [colors].
  /// Dark variants also receive [listTileTheme] and [iconTheme].
  ///
  /// [flavor] threads palette-vs-standard awareness into widgets via a
  /// [ThemeExtension] so decorative accent usage can be scaled back in
  /// standard mode without affecting palette mode.
  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    Color accent,
    _ThemeColors colors,
    PrismShapes shapes,
    PrismThemeFlavor flavor,
  ) {
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
    );

    return base.copyWith(
      splashFactory: isApple ? NoSplash.splashFactory : null,
      splashColor: isApple ? Colors.transparent : null,
      highlightColor: isApple ? Colors.transparent : null,
      textTheme: _adjustTextTheme(
        base.textTheme,
      ).apply(fontFamilyFallback: _linuxFontFamilyFallback),
      scaffoldBackgroundColor: colors.scaffold,
      cardColor: colors.cardColor,
      extensions: <ThemeExtension<dynamic>>[shapes, flavor],
      cardTheme: CardThemeData(
        color: colors.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusMedium),
          ),
        ),
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.isDark ? AppColors.warmWhite : null,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusLarge),
          ),
          borderSide: BorderSide(color: colors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusLarge),
          ),
          borderSide: BorderSide(color: colors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusLarge),
          ),
          borderSide: BorderSide(color: colors.focusBorderColor),
        ),
      ),
      listTileTheme: colors.isDark
          ? ListTileThemeData(
              iconColor: AppColors.warmWhite.withValues(alpha: 0.7),
              textColor: AppColors.warmWhite,
            )
          : null,
      iconTheme: colors.isDark
          ? IconThemeData(color: AppColors.warmWhite.withValues(alpha: 0.7))
          : null,
      dividerTheme: DividerThemeData(color: colors.dividerColor),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.sheetBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(shapes.radius(PrismTokens.radiusXLarge)),
          ),
        ),
        dragHandleColor: colors.dragHandleColor,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.dialogBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusLarge),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.popupBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusMedium),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: AppColors.warmWhite,
        elevation: 0,
        shape: shapes.circleOrSquareBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.filledButtonBg,
          foregroundColor: colors.filledButtonFg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              shapes.radius(PrismTokens.radiusSmall),
            ),
          ),
          elevation: 0,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: colors.iconButtonBg,
          foregroundColor: colors.iconButtonFg,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.textButtonFg),
      ),
      switchTheme: _switchTheme(colorScheme: colorScheme, accent: accent),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.snackBarBg,
        contentTextStyle: const TextStyle(color: AppColors.warmWhite),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusSmall),
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.cardColor,
        selectedColor: accent.withValues(alpha: 0.15),
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: colors.borderColor, width: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusSmall),
          ),
        ),
        labelStyle: TextStyle(
          color: colors.isDark ? AppColors.warmWhite : AppColors.warmBlack,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 800),
        decoration: BoxDecoration(
          color: colors.isDark
              ? AppColors.warmWhite.withValues(alpha: 0.9)
              : AppColors.charcoal,
          borderRadius: BorderRadius.circular(
            shapes.radius(PrismTokens.radiusSmall / 2),
          ),
        ),
        textStyle: TextStyle(
          color: colors.isDark ? AppColors.warmBlack : AppColors.warmWhite,
          fontSize: 12,
        ),
      ),
    );
  }

  static ThemeData light({
    Color? accentColor,
    CornerStyle cornerStyle = CornerStyle.rounded,
  }) {
    final requestedAccent = accentColor ?? AppColors.prismPurpleLight;
    final accent = contrastAdjustedAccent(requestedAccent, AppColors.parchment);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: requestedAccent,
          brightness: Brightness.light,
        ).copyWith(
          primary: accent,
          onPrimary: highContrastForeground(accent),
          // Warm parchment surfaces.
          surface: AppColors.warmOffWhite,
          surfaceContainerLowest: AppColors.warmOffWhite,
          surfaceContainerLow: AppColors.parchment,
          surfaceContainer: AppColors.parchmentElevated,
          surfaceContainerHigh: AppColors.parchmentStrong,
          surfaceContainerHighest: const Color(0xFFD8C9B5),
          onSurface: AppColors.warmBlack,
        );

    final colors = _ThemeColors(
      scaffold: AppColors.parchment,
      cardColor: AppColors.warmOffWhite,
      fillColor: AppColors.warmBlack.withValues(alpha: 0.04),
      borderColor: AppColors.warmBlack.withValues(alpha: 0.1),
      focusBorderColor: accent.withValues(alpha: 0.6),
      dividerColor: AppColors.warmBlack.withValues(alpha: 0.06),
      sheetBg: AppColors.parchment,
      dialogBg: AppColors.warmOffWhite,
      popupBg: AppColors.warmOffWhite,
      snackBarBg: AppColors.charcoal,
      dragHandleColor: AppColors.warmBlack.withValues(alpha: 0.2),
      filledButtonBg: AppColors.parchmentElevated.withValues(alpha: 0.82),
      filledButtonFg: AppColors.warmBlack.withValues(alpha: 0.8),
      iconButtonBg: AppColors.parchmentElevated.withValues(alpha: 0.82),
      iconButtonFg: AppColors.warmBlack.withValues(alpha: 0.8),
      textButtonFg: AppColors.warmBlack.withValues(alpha: 0.8),
      isDark: false,
    );

    return _buildTheme(
      colorScheme,
      accent,
      colors,
      PrismShapes(cornerStyle: cornerStyle),
      PrismThemeFlavor.standard,
    );
  }

  static ThemeData dark({
    Color? accentColor,
    CornerStyle cornerStyle = CornerStyle.rounded,
  }) {
    final requestedAccent = accentColor ?? AppColors.prismPurple;
    final accent = contrastAdjustedAccent(requestedAccent, AppColors.charcoal);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: requestedAccent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          onPrimary: highContrastForeground(accent),
          surface: AppColors.charcoal,
          onSurface: AppColors.warmWhite,
          surfaceContainerLowest: const Color(0xFF2B2723),
          surfaceContainerLow: AppColors.charcoal,
          surfaceContainer: AppColors.charcoalElevated,
          surfaceContainerHigh: AppColors.charcoalSurface,
          surfaceContainerHighest: AppColors.charcoalStrong,
        );

    final colors = _ThemeColors(
      scaffold: AppColors.charcoal,
      cardColor: AppColors.warmWhite.withValues(alpha: 0.06),
      fillColor: AppColors.warmWhite.withValues(alpha: 0.06),
      borderColor: AppColors.warmWhite.withValues(alpha: 0.1),
      focusBorderColor: accent.withValues(alpha: 0.7),
      dividerColor: AppColors.warmWhite.withValues(alpha: 0.06),
      sheetBg: AppColors.charcoalElevated,
      dialogBg: AppColors.charcoalElevated,
      popupBg: AppColors.charcoalElevated,
      snackBarBg: AppColors.charcoalStrong,
      dragHandleColor: AppColors.warmWhite.withValues(alpha: 0.3),
      filledButtonBg: AppColors.warmWhite.withValues(alpha: 0.1),
      filledButtonFg: AppColors.warmWhite,
      iconButtonBg: AppColors.warmWhite.withValues(alpha: 0.1),
      iconButtonFg: AppColors.warmWhite,
      textButtonFg: AppColors.warmWhite.withValues(alpha: 0.8),
      isDark: true,
    );

    return _buildTheme(
      colorScheme,
      accent,
      colors,
      PrismShapes(cornerStyle: cornerStyle),
      PrismThemeFlavor.standard,
    );
  }

  /// Pure black OLED theme — saves battery on OLED screens.
  static ThemeData oled({
    Color? accentColor,
    CornerStyle cornerStyle = CornerStyle.rounded,
  }) {
    final requestedAccent = accentColor ?? AppColors.prismPurple;
    final accent = contrastAdjustedAccent(requestedAccent, Colors.black);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: requestedAccent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
          onPrimary: highContrastForeground(accent),
          surface: Colors.black,
          onSurface: AppColors.warmWhite,
          surfaceContainerLowest: Colors.black,
          surfaceContainerLow: AppColors.oledSurface1,
          surfaceContainer: AppColors.oledSurface2,
          surfaceContainerHigh: AppColors.oledSurface3,
          surfaceContainerHighest: AppColors.oledSurface4,
        );

    final colors = _ThemeColors(
      scaffold: Colors.black,
      cardColor: AppColors.warmWhite.withValues(alpha: 0.05),
      fillColor: AppColors.warmWhite.withValues(alpha: 0.05),
      borderColor: AppColors.warmWhite.withValues(alpha: 0.08),
      focusBorderColor: accent.withValues(alpha: 0.7),
      dividerColor: AppColors.warmWhite.withValues(alpha: 0.05),
      sheetBg: AppColors.oledSurface1,
      dialogBg: AppColors.oledSurface1,
      popupBg: AppColors.oledSurface1,
      snackBarBg: AppColors.oledSurface2,
      dragHandleColor: AppColors.warmWhite.withValues(alpha: 0.3),
      filledButtonBg: AppColors.warmWhite.withValues(alpha: 0.08),
      filledButtonFg: AppColors.warmWhite,
      iconButtonBg: AppColors.warmWhite.withValues(alpha: 0.08),
      iconButtonFg: AppColors.warmWhite,
      textButtonFg: AppColors.warmWhite.withValues(alpha: 0.8),
      isDark: true,
    );

    return _buildTheme(
      colorScheme,
      accent,
      colors,
      PrismShapes(cornerStyle: cornerStyle),
      PrismThemeFlavor.standard,
    );
  }

  /// Palette theme. Uses device colors when requested and available,
  /// otherwise builds a seeded Material color scheme.
  ///
  /// Routes through [_buildTheme] so Palette keeps the shared Prism component
  /// styling.
  static ThemeData materialYouLight(
    ColorScheme? dynamicScheme, {
    CornerStyle cornerStyle = CornerStyle.rounded,
    PaletteSource paletteSource = PaletteSource.device,
    String paletteSeedColorHex = '#9070A0',
    PaletteMood paletteMood = PaletteMood.tonal,
    PaletteContrast paletteContrast = PaletteContrast.standard,
  }) {
    final seedColor = AppColors.fromHex(paletteSeedColorHex);
    final baseColorScheme = _paletteColorScheme(
      dynamicScheme: dynamicScheme,
      brightness: Brightness.light,
      source: paletteSource,
      seedColorHex: paletteSeedColorHex,
      mood: paletteMood,
      contrast: paletteContrast,
    );

    return _paletteThemeFromScheme(
      baseColorScheme: baseColorScheme,
      surfaceTintColor:
          paletteSource == PaletteSource.custom || dynamicScheme == null
          ? seedColor
          : null,
      isDark: false,
      shapes: PrismShapes(cornerStyle: cornerStyle),
    );
  }

  static ThemeData materialYouDark(
    ColorScheme? dynamicScheme, {
    CornerStyle cornerStyle = CornerStyle.rounded,
    PaletteSource paletteSource = PaletteSource.device,
    String paletteSeedColorHex = '#9070A0',
    PaletteMood paletteMood = PaletteMood.tonal,
    PaletteContrast paletteContrast = PaletteContrast.standard,
  }) {
    final seedColor = AppColors.fromHex(paletteSeedColorHex);
    final baseColorScheme = _paletteColorScheme(
      dynamicScheme: dynamicScheme,
      brightness: Brightness.dark,
      source: paletteSource,
      seedColorHex: paletteSeedColorHex,
      mood: paletteMood,
      contrast: paletteContrast,
    );

    return _paletteThemeFromScheme(
      baseColorScheme: baseColorScheme,
      surfaceTintColor:
          paletteSource == PaletteSource.custom || dynamicScheme == null
          ? seedColor
          : null,
      isDark: true,
      shapes: PrismShapes(cornerStyle: cornerStyle),
    );
  }
}
