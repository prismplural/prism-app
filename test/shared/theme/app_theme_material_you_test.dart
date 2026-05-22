import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';

void main() {
  group('Material You theme controls', () {
    test(
      'local palette theme reseeds Prism components without changing type',
      () {
        final base = AppTheme.light(accentColor: const Color(0xFF9070A0))
            .copyWith(
              textTheme: Typography.material2021().black.apply(
                fontFamily: 'Inter',
              ),
            );
        final theme = AppTheme.localPaletteTheme(
          base,
          seedColor: const Color(0xFF16A34A),
          paletteMood: PaletteMood.vibrant,
        );
        final untintedScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF16A34A),
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        );

        expect(theme.textTheme, base.textTheme);
        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.primary, isNot(base.colorScheme.primary));
        expect(
          theme.scaffoldBackgroundColor,
          theme.colorScheme.surfaceContainerLowest,
        );
        expect(theme.cardColor, theme.colorScheme.surfaceContainerLow);
        expect(
          theme.scaffoldBackgroundColor,
          Color.alphaBlend(
            const Color(0xFF16A34A).withValues(alpha: 0.16),
            untintedScheme.surfaceContainerLowest,
          ),
        );

        final filledButtonStyle = theme.filledButtonTheme.style!;
        expect(
          filledButtonStyle.backgroundColor!.resolve(const <WidgetState>{}),
          theme.colorScheme.primary,
        );
        expect(
          theme.switchTheme.trackColor!.resolve(const {WidgetState.selected}),
          theme.colorScheme.primary,
        );
      },
    );

    test('local palette theme follows dark surface tinting', () {
      final base = AppTheme.dark(accentColor: const Color(0xFF9070A0));
      final theme = AppTheme.localPaletteTheme(
        base,
        seedColor: const Color(0xFF2563EB),
        paletteMood: PaletteMood.expressive,
      );
      final untintedScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      );

      expect(theme.brightness, Brightness.dark);
      expect(
        theme.scaffoldBackgroundColor,
        theme.colorScheme.surfaceContainerLow,
      );
      expect(theme.cardColor, theme.colorScheme.surfaceContainer);
      expect(
        theme.scaffoldBackgroundColor,
        Color.alphaBlend(
          const Color(0xFF2563EB).withValues(alpha: 0.14),
          untintedScheme.surfaceContainerLow,
        ),
      );
      expect(
        theme.switchTheme.thumbColor!.resolve(const <WidgetState>{}),
        theme.colorScheme.onSurfaceVariant,
      );
    });

    test('local palette theme keeps neutral member colors monochrome', () {
      final base = AppTheme.light(accentColor: const Color(0xFF9070A0));

      for (final seed in const [
        Color(0xFFFFFFFF),
        Color(0xFF808080),
        Color(0xFF000000),
      ]) {
        for (final mood in PaletteMood.values) {
          final theme = AppTheme.localPaletteTheme(
            base,
            seedColor: seed,
            paletteMood: mood,
          );

          for (final entry in _paletteAccentRoles(theme.colorScheme).entries) {
            expect(
              _hslSaturation(entry.value),
              lessThan(0.01),
              reason:
                  '${entry.key} should stay monochrome for ${seed.toARGB32().toRadixString(16)} in ${mood.name}',
            );
          }
        }
      }
    });

    test('custom palette themes keep neutral colors monochrome', () {
      for (final entry in const {
        '#FFFFFF': Color(0xFFFFFFFF),
        '#808080': Color(0xFF808080),
        '#000000': Color(0xFF000000),
      }.entries) {
        for (final mood in PaletteMood.values) {
          final theme = AppTheme.materialYouLight(
            null,
            paletteSource: PaletteSource.custom,
            paletteSeedColorHex: entry.key,
            paletteMood: mood,
          );

          for (final role in _paletteAccentRoles(theme.colorScheme).entries) {
            expect(
              _hslSaturation(role.value),
              lessThan(0.01),
              reason:
                  '${role.key} should stay monochrome for ${entry.key} in ${mood.name}',
            );
          }
        }
      }
    });

    test('local palette surfaces tint from bright member colors', () {
      final base = AppTheme.light(accentColor: const Color(0xFF9070A0));
      const yellow = Color(0xFFFFD000);
      final yellowTheme = AppTheme.localPaletteTheme(
        base,
        seedColor: yellow,
        paletteMood: PaletteMood.fidelity,
      );
      final untintedScheme = ColorScheme.fromSeed(
        seedColor: yellow,
        brightness: Brightness.light,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );

      expect(
        HSLColor.fromColor(yellowTheme.colorScheme.primary).hue,
        closeTo(HSLColor.fromColor(yellow).hue, 10),
      );
      expect(
        yellowTheme.scaffoldBackgroundColor,
        Color.alphaBlend(
          yellow.withValues(alpha: 0.16),
          untintedScheme.surfaceContainerLowest,
        ),
      );
    });

    test('light palette surfaces are tinted toward the custom seed color', () {
      const seed = Color(0xFF16A34A);
      final theme = AppTheme.materialYouLight(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#16A34A',
        paletteMood: PaletteMood.vibrant,
      );
      final untintedScheme = ColorScheme.fromSeed(
        seedColor: seed,
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
        theme.scaffoldBackgroundColor,
        Color.alphaBlend(
          seed.withValues(alpha: 0.16),
          untintedScheme.surfaceContainerLowest,
        ),
      );
      expect(
        theme.cardColor,
        Color.alphaBlend(
          seed.withValues(alpha: 0.21),
          untintedScheme.surfaceContainerLow,
        ),
      );
      expect(
        theme.colorScheme.surfaceContainerHighest,
        Color.alphaBlend(
          seed.withValues(alpha: 0.33),
          untintedScheme.surfaceContainerHighest,
        ),
      );
      expect(
        _rgbDistance(theme.scaffoldBackgroundColor, seed),
        lessThan(_rgbDistance(untintedScheme.surfaceContainerLowest, seed)),
      );
      expect(
        _rgbDistance(theme.cardColor, seed),
        lessThan(_rgbDistance(untintedScheme.surfaceContainerLow, seed)),
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
      'dark palette switch off-state stays visible at every contrast level',
      () {
        for (final contrast in PaletteContrast.values) {
          final theme = AppTheme.materialYouDark(
            null,
            paletteSource: PaletteSource.custom,
            paletteSeedColorHex: '#9070A0',
            paletteMood: PaletteMood.tonal,
            paletteContrast: contrast,
          );

          final track = theme.switchTheme.trackColor!.resolve(
            const <WidgetState>{},
          )!;
          final thumb = theme.switchTheme.thumbColor!.resolve(
            const <WidgetState>{},
          )!;

          expect(
            thumb,
            theme.colorScheme.onSurfaceVariant,
            reason: 'contrast ${contrast.name}',
          );
          expect(
            contrastRatio(thumb, track),
            greaterThanOrEqualTo(prismMinimumAccentContrast),
            reason: 'contrast ${contrast.name}',
          );
        }
      },
    );

    test(
      'dark palette surfaces are lifted and tinted toward the custom seed color',
      () {
        const seed = Color(0xFF2563EB);
        final theme = AppTheme.materialYouDark(
          null,
          paletteSource: PaletteSource.custom,
          paletteSeedColorHex: '#2563EB',
          paletteMood: PaletteMood.expressive,
        );
        final untintedScheme = ColorScheme.fromSeed(
          seedColor: seed,
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
          theme.scaffoldBackgroundColor,
          Color.alphaBlend(
            seed.withValues(alpha: 0.14),
            untintedScheme.surfaceContainerLow,
          ),
        );
        expect(
          theme.cardColor,
          Color.alphaBlend(
            seed.withValues(alpha: 0.18),
            untintedScheme.surfaceContainer,
          ),
        );
        expect(
          theme.colorScheme.surfaceContainerHighest,
          Color.alphaBlend(
            seed.withValues(alpha: 0.26),
            untintedScheme.surfaceContainerHighest,
          ),
        );
        expect(
          _rgbDistance(theme.scaffoldBackgroundColor, seed),
          lessThan(_rgbDistance(untintedScheme.surfaceContainerLow, seed)),
        );
        expect(
          _rgbDistance(theme.cardColor, seed),
          lessThan(_rgbDistance(untintedScheme.surfaceContainer, seed)),
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

Map<String, Color> _paletteAccentRoles(ColorScheme scheme) => {
  'primary': scheme.primary,
  'primaryContainer': scheme.primaryContainer,
  'secondary': scheme.secondary,
  'secondaryContainer': scheme.secondaryContainer,
  'tertiary': scheme.tertiary,
  'tertiaryContainer': scheme.tertiaryContainer,
};

double _rgbDistance(Color a, Color b) {
  final red = a.r - b.r;
  final green = a.g - b.g;
  final blue = a.b - b.b;
  return (red * red) + (green * green) + (blue * blue);
}

double _hslSaturation(Color color) => HSLColor.fromColor(color).saturation;
