import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/views/accent_color_presets.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';

void main() {
  Color colorFromHex(String hex) {
    return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
  }

  group('accentColorPresets', () {
    test(
      'offer polished soft and vibrant options that pass contrast checks',
      () {
        expect(accentColorPresets.length, greaterThanOrEqualTo(12));

        final saturations = <double>[];
        for (final preset in accentColorPresets) {
          final color = colorFromHex(preset.hex);
          saturations.add(HSLColor.fromColor(color).saturation);

          expect(
            classifyAccentLegibility(color),
            AccentLegibility.ok,
            reason: '${preset.hex} should work across light and dark mode.',
          );
        }

        expect(
          saturations.any((saturation) => saturation < 0.35),
          isTrue,
          reason:
              'The preset set should include softer, pastel-leaning colors.',
        );
        expect(
          saturations.any((saturation) => saturation > 0.65),
          isTrue,
          reason: 'The preset set should include vibrant accent colors.',
        );
      },
    );

    test('treat retired non-default swatches as custom colors', () {
      const retiredPresetHexes = [
        '#2563EB',
        '#16A34A',
        '#DC2626',
        '#EA580C',
        '#DB2777',
        '#0D9488',
        '#D97706',
        '#4F46E5',
        '#6B7280',
      ];

      for (final hex in retiredPresetHexes) {
        expect(isAccentColorPresetHex(hex), isFalse);
      }
    });

    test('keeps Prism Purple as the default while offering Prism Iris', () {
      expect(accentColorPresets.first.hex, prismDefaultAccentColorHex);
      expect(prismDefaultAccentColorHex, '#9070A0');
      expect(isAccentColorPresetHex('#8474B7'), isTrue);
    });
  });
}
