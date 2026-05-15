import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';

void main() {
  group('Material You theme controls', () {
    test('light palette surfaces are tinted toward the accent color', () {
      final theme = AppTheme.materialYouLight(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#16A34A',
        paletteMood: PaletteMood.vibrant,
      );
      final untintedScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF16A34A),
        brightness: Brightness.light,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      );

      expect(
        theme.scaffoldBackgroundColor,
        theme.colorScheme.surfaceContainerLowest,
      );
      expect(theme.cardColor, theme.colorScheme.surfaceContainerLow);
      expect(
        theme.scaffoldBackgroundColor,
        isNot(untintedScheme.surfaceContainerLowest),
      );
      expect(theme.cardColor, isNot(untintedScheme.surfaceContainerLow));
      expect(
        _rgbDistance(theme.scaffoldBackgroundColor, theme.colorScheme.primary),
        lessThan(
          _rgbDistance(
            untintedScheme.surfaceContainerLowest,
            theme.colorScheme.primary,
          ),
        ),
      );
      expect(
        _rgbDistance(theme.cardColor, theme.colorScheme.primary),
        lessThan(
          _rgbDistance(
            untintedScheme.surfaceContainerLow,
            theme.colorScheme.primary,
          ),
        ),
      );
    });

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

    test(
      'dark palette surfaces are lifted and tinted toward the accent color',
      () {
        final theme = AppTheme.materialYouDark(
          null,
          paletteSource: PaletteSource.custom,
          paletteSeedColorHex: '#2563EB',
          paletteMood: PaletteMood.expressive,
        );
        final untintedScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.expressive,
        );

        expect(
          theme.scaffoldBackgroundColor,
          theme.colorScheme.surfaceContainerLow,
        );
        expect(theme.cardColor, theme.colorScheme.surfaceContainer);
        expect(
          theme.scaffoldBackgroundColor,
          isNot(untintedScheme.surfaceContainerLow),
        );
        expect(theme.cardColor, isNot(untintedScheme.surfaceContainer));
        expect(
          _rgbDistance(
            theme.scaffoldBackgroundColor,
            theme.colorScheme.primary,
          ),
          lessThan(
            _rgbDistance(
              untintedScheme.surfaceContainerLow,
              theme.colorScheme.primary,
            ),
          ),
        );
        expect(
          _rgbDistance(theme.cardColor, theme.colorScheme.primary),
          lessThan(
            _rgbDistance(
              untintedScheme.surfaceContainer,
              theme.colorScheme.primary,
            ),
          ),
        );
        expect(
          relativeLuminance(theme.scaffoldBackgroundColor),
          greaterThan(
            relativeLuminance(theme.colorScheme.surfaceContainerLowest),
          ),
        );
      },
    );
  });
}

double _rgbDistance(Color a, Color b) {
  final red = a.r - b.r;
  final green = a.g - b.g;
  final blue = a.b - b.b;
  return (red * red) + (green * green) + (blue * blue);
}
