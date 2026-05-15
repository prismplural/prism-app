import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';

void main() {
  group('Material You theme controls', () {
    test('light palette controls use palette-derived colors', () {
      final theme = AppTheme.materialYouLight(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#16A34A',
        paletteMood: PaletteMood.vibrant,
      );

      expect(
        theme.switchTheme.trackColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.surfaceContainerHighest,
      );
      expect(
        theme.switchTheme.thumbColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.surfaceContainerLow,
      );
      expect(
        theme.switchTheme.trackColor!.resolve(const {WidgetState.selected}),
        theme.colorScheme.primary,
      );

      final filledButtonStyle = theme.filledButtonTheme.style!;
      expect(
        filledButtonStyle.backgroundColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.primary,
      );
      expect(
        filledButtonStyle.foregroundColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.onPrimary,
      );

      final iconButtonStyle = theme.iconButtonTheme.style!;
      expect(
        iconButtonStyle.backgroundColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.primary.withValues(alpha: 0.12),
      );
      expect(
        iconButtonStyle.foregroundColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.primary,
      );
    });

    test('dark palette scaffold uses a lifted surface background', () {
      final theme = AppTheme.materialYouDark(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#2563EB',
        paletteMood: PaletteMood.expressive,
      );

      expect(
        theme.scaffoldBackgroundColor,
        theme.colorScheme.surfaceContainerLow,
      );
      expect(
        relativeLuminance(theme.scaffoldBackgroundColor),
        greaterThan(
          relativeLuminance(theme.colorScheme.surfaceContainerLowest),
        ),
      );
    });
  });
}
