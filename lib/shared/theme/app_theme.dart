import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
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
        displayLarge: textTheme.displayLarge?.copyWith(letterSpacing: 0, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
        displayMedium: textTheme.displayMedium?.copyWith(letterSpacing: 0, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
        displaySmall: textTheme.displaySmall?.copyWith(letterSpacing: 0, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
        headlineLarge: textTheme.headlineLarge?.copyWith(letterSpacing: 0, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
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
      displayLarge: textTheme.displayLarge?.copyWith(letterSpacing: 0, fontSize: 48, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
      displayMedium: textTheme.displayMedium?.copyWith(letterSpacing: 0, fontSize: 38, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
      displaySmall: textTheme.displaySmall?.copyWith(letterSpacing: 0, fontSize: 30, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
      headlineLarge: textTheme.headlineLarge?.copyWith(letterSpacing: 0, fontSize: 26, fontFamily: 'Unbounded', fontWeight: FontWeight.w700),
      headlineMedium: textTheme.headlineMedium?.copyWith(letterSpacing: 0, fontSize: 22),
      headlineSmall: textTheme.headlineSmall?.copyWith(letterSpacing: 0, fontSize: 19),
      titleLarge: textTheme.titleLarge?.copyWith(letterSpacing: 0, fontSize: 18),
      titleMedium: textTheme.titleMedium?.copyWith(letterSpacing: 0, fontSize: 14),
      titleSmall: textTheme.titleSmall?.copyWith(letterSpacing: 0, fontSize: 13),
      bodyLarge: textTheme.bodyLarge?.copyWith(letterSpacing: 0, fontSize: 14),
      bodyMedium: textTheme.bodyMedium?.copyWith(letterSpacing: 0, fontSize: 13),
      bodySmall: textTheme.bodySmall?.copyWith(letterSpacing: 0, fontSize: 11),
      labelLarge: textTheme.labelLarge?.copyWith(letterSpacing: 0, fontSize: 13),
      labelMedium: textTheme.labelMedium?.copyWith(letterSpacing: 0, fontSize: 11),
      labelSmall: textTheme.labelSmall?.copyWith(letterSpacing: 0, fontSize: 10),
    );
  }

  /// Minimal switch theme shared across all variants.
  static SwitchThemeData _switchTheme({required bool isDark}) {
    final onSurface = isDark ? AppColors.warmWhite : AppColors.warmBlack;
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.warmWhite;
        }
        return onSurface.withValues(alpha: isDark ? 0.6 : 0.3);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.warmWhite.withValues(alpha: 0.3);
        }
        return onSurface.withValues(alpha: 0.08);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.warmWhite.withValues(alpha: 0.15);
        }
        return onSurface.withValues(alpha: 0.1);
      }),
    );
  }

  /// Shared component theme builder. Applies all component themes using the
  /// provided [colorScheme], [accent], and variant-specific [colors].
  /// Dark variants also receive [listTileTheme] and [iconTheme].
  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    Color accent,
    _ThemeColors colors,
  ) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
    );

    return base.copyWith(
      textTheme: _adjustTextTheme(base.textTheme),
      scaffoldBackgroundColor: colors.scaffold,
      cardTheme: CardThemeData(
        color: colors.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismTokens.radiusMedium),
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
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: colors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: colors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PrismTokens.radiusXLarge),
          ),
        ),
        dragHandleColor: colors.dragHandleColor,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.dialogBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismTokens.radiusLarge),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.popupBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismTokens.radiusMedium),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: AppColors.warmWhite,
        elevation: 0,
        shape: const CircleBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.filledButtonBg,
          foregroundColor: colors.filledButtonFg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
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
      switchTheme: _switchTheme(isDark: colors.isDark),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.snackBarBg,
        contentTextStyle: const TextStyle(color: AppColors.warmWhite),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PrismTokens.radiusSmall),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 800),
        decoration: BoxDecoration(
          color: colors.isDark
              ? AppColors.warmWhite.withValues(alpha: 0.9)
              : AppColors.charcoal,
          borderRadius: BorderRadius.circular(PrismTokens.radiusSmall / 2),
        ),
        textStyle: TextStyle(
          color: colors.isDark ? AppColors.warmBlack : AppColors.warmWhite,
          fontSize: 12,
        ),
      ),
    );
  }

  static ThemeData light({Color? accentColor}) {
    final accent = accentColor ?? AppColors.prismPurpleLight;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: accent,
          // Warm parchment surfaces.
          surfaceContainerLowest: AppColors.warmOffWhite,
          surfaceContainerLow: AppColors.parchment,
          surfaceContainer: AppColors.parchmentElevated,
          surfaceContainerHigh: AppColors.parchmentStrong,
          surfaceContainerHighest: const Color(0xFFD9CEC0),
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
      filledButtonBg: AppColors.warmBlack.withValues(alpha: 0.06),
      filledButtonFg: AppColors.warmBlack.withValues(alpha: 0.8),
      iconButtonBg: AppColors.warmBlack.withValues(alpha: 0.06),
      iconButtonFg: AppColors.warmBlack.withValues(alpha: 0.8),
      textButtonFg: AppColors.warmBlack.withValues(alpha: 0.8),
      isDark: false,
    );

    return _buildTheme(colorScheme, accent, colors);
  }

  static ThemeData dark({Color? accentColor}) {
    final accent = accentColor ?? AppColors.prismPurple;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
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

    return _buildTheme(colorScheme, accent, colors);
  }

  /// Pure black OLED theme — saves battery on OLED screens.
  static ThemeData oled({Color? accentColor}) {
    final accent = accentColor ?? AppColors.prismPurple;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: accent,
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

    return _buildTheme(colorScheme, accent, colors);
  }

  /// Material You theme — uses the system's dynamic color palette.
  /// Falls back to the standard Prism theme if [dynamicScheme] is null.
  ///
  /// Routes through [_buildTheme] so Material You gets the same 15+
  /// component-theme customizations as Standard / OLED variants.
  static ThemeData materialYouLight(ColorScheme? dynamicScheme) {
    final colorScheme =
        dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: AppColors.prismPurple,
          brightness: Brightness.light,
        );

    final accent = colorScheme.primary;

    final colors = _ThemeColors(
      scaffold: colorScheme.surfaceContainerLowest,
      cardColor: colorScheme.surfaceContainerLow,
      fillColor: colorScheme.onSurface.withValues(alpha: 0.04),
      borderColor: colorScheme.onSurface.withValues(alpha: 0.1),
      focusBorderColor: accent.withValues(alpha: 0.6),
      dividerColor: colorScheme.onSurface.withValues(alpha: 0.06),
      sheetBg: colorScheme.surfaceContainerLow,
      dialogBg: colorScheme.surfaceContainerLow,
      popupBg: colorScheme.surfaceContainerLow,
      snackBarBg: colorScheme.inverseSurface,
      dragHandleColor: colorScheme.onSurface.withValues(alpha: 0.2),
      filledButtonBg: colorScheme.onSurface.withValues(alpha: 0.06),
      filledButtonFg: colorScheme.onSurface.withValues(alpha: 0.8),
      iconButtonBg: colorScheme.onSurface.withValues(alpha: 0.06),
      iconButtonFg: colorScheme.onSurface.withValues(alpha: 0.8),
      textButtonFg: colorScheme.onSurface.withValues(alpha: 0.8),
      isDark: false,
    );

    return _buildTheme(colorScheme, accent, colors);
  }

  static ThemeData materialYouDark(ColorScheme? dynamicScheme) {
    final colorScheme =
        dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: AppColors.prismPurple,
          brightness: Brightness.dark,
        );

    final accent = colorScheme.primary;

    final colors = _ThemeColors(
      scaffold: colorScheme.surfaceContainerLowest,
      cardColor: colorScheme.onSurface.withValues(alpha: 0.06),
      fillColor: colorScheme.onSurface.withValues(alpha: 0.06),
      borderColor: colorScheme.onSurface.withValues(alpha: 0.1),
      focusBorderColor: accent.withValues(alpha: 0.7),
      dividerColor: colorScheme.onSurface.withValues(alpha: 0.06),
      sheetBg: colorScheme.surfaceContainerHigh,
      dialogBg: colorScheme.surfaceContainerHigh,
      popupBg: colorScheme.surfaceContainerHigh,
      snackBarBg: colorScheme.inverseSurface,
      dragHandleColor: colorScheme.onSurface.withValues(alpha: 0.3),
      filledButtonBg: colorScheme.onSurface.withValues(alpha: 0.1),
      filledButtonFg: colorScheme.onSurface,
      iconButtonBg: colorScheme.onSurface.withValues(alpha: 0.1),
      iconButtonFg: colorScheme.onSurface,
      textButtonFg: colorScheme.onSurface.withValues(alpha: 0.8),
      isDark: true,
    );

    return _buildTheme(colorScheme, accent, colors);
  }
}
