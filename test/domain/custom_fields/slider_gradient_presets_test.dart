import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/slider_gradient_presets.dart';

void main() {
  group('kSliderGradientPresets', () {
    test('has 17 entries', () {
      expect(kSliderGradientPresets.length, equals(17));
    });

    test('palette category has six presets', () {
      final palette = kSliderGradientPresets.where(
        (p) => p.category == SliderGradientCategory.palette,
      ).toList();
      expect(palette.length, 6);
    });

    test('all preset IDs are unique', () {
      final ids = kSliderGradientPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('lookupGradientPreset', () {
    test('lookupGradientPreset("femme-masc") returns the correct entry', () {
      final preset = lookupGradientPreset('femme-masc');
      expect(preset, isNotNull);
      expect(preset!.id, 'femme-masc');
      expect(preset.category, SliderGradientCategory.identity);
      expect(preset.leftHex, '#E89BB8');
      expect(preset.centerHex, '#F0E6D6');
      expect(preset.rightHex, '#8FAA9A');
    });

    test('lookupGradientPreset("palette-rose-dusk") returns the correct entry', () {
      final preset = lookupGradientPreset('palette-rose-dusk');
      expect(preset, isNotNull);
      expect(preset!.id, 'palette-rose-dusk');
      expect(preset.category, SliderGradientCategory.palette);
      expect(preset.leftHex, '#F4B89E');
      expect(preset.centerHex, '#D17A8E');
      expect(preset.rightHex, '#5B4378');
    });

    test('lookupGradientPreset("nonexistent") returns null', () {
      expect(lookupGradientPreset('nonexistent'), isNull);
    });

    test('lookupGradientPreset(null) returns null', () {
      expect(lookupGradientPreset(null), isNull);
    });

    test('all presets are reachable via lookupGradientPreset', () {
      for (final preset in kSliderGradientPresets) {
        expect(lookupGradientPreset(preset.id), isNotNull);
      }
    });
  });

  group('lerpHsl', () {
    test('at t=0 returns a color approximately equal to left', () {
      const left = Color(0xFFFF0000); // red
      const right = Color(0xFF0000FF); // blue
      final result = lerpHsl(left, right, 0.0);
      // Should be red.
      expect(result.r, closeTo(1.0, 0.01));
      expect(result.b, closeTo(0.0, 0.01));
    });

    test('at t=1 returns a color approximately equal to right', () {
      const left = Color(0xFFFF0000); // red
      const right = Color(0xFF0000FF); // blue
      final result = lerpHsl(left, right, 1.0);
      // Should be blue.
      expect(result.r, closeTo(0.0, 0.01));
      expect(result.b, closeTo(1.0, 0.01));
    });

    test('at t=0.5 returns a midpoint color (not equal to either endpoint)', () {
      const left = Color(0xFFFF0000); // red (hue 0°)
      const right = Color(0xFF0000FF); // blue (hue 240°)
      final result = lerpHsl(left, right, 0.5);
      final hsl = HSLColor.fromColor(result);
      // The shorter path from 0° to 240° is actually longer than going through
      // 360°→0° path. But the standard red-to-blue: 0→240, diff=240>180,
      // so we go the short way: hA=0+360=360, hB=240; lerp at 0.5 → 300 (magenta).
      // Should be neither red nor blue — approximately magenta.
      expect(hsl.saturation, greaterThan(0.5));
      // Midpoint should differ from both endpoints.
      expect(result, isNot(left));
      expect(result, isNot(right));
    });

    test('chooses the shorter hue path (red to cyan goes via green, not purple)', () {
      // Red = hue 0°, cyan = hue 180°. Difference = 180°, shorter path is
      // through green (90° midpoint) rather than purple/yellow.
      const red = Color(0xFFFF0000); // hue 0°
      const cyan = Color(0xFF00FFFF); // hue 180°
      final mid = lerpHsl(red, cyan, 0.5);
      final hsl = HSLColor.fromColor(mid);
      // The midpoint hue should be around 90° (green/yellow-green), not 270° (purple).
      // Since abs(180-0)=180 (not >180), we take the direct path 0→180 → mid=90°.
      expect(hsl.hue, closeTo(90.0, 15.0));
    });

    test('shorter hue path: avoids muddy midpoint for red→blue via purple', () {
      // Red hue=0°, Blue hue=240°. Diff=240>180, so short path goes via 360→300
      // (magenta/purple), not through green.
      const red = Color(0xFFFF0000);
      const blue = Color(0xFF0000FF);
      final mid = lerpHsl(red, blue, 0.5);
      final hsl = HSLColor.fromColor(mid);
      // Midpoint should be around 300° (magenta), NOT around 120° (green).
      expect(hsl.hue, greaterThan(240.0));
    });
  });

  group('sliderGradientStops', () {
    const left = Color(0xFFFF0000);
    const center = Color(0xFF00FF00);
    const right = Color(0xFF0000FF);

    test('two-color ramp yields 11 stops ending at the endpoints', () {
      final stops = sliderGradientStops(left, null, right);
      expect(stops.length, 11);
      expect(stops.first, left);
      expect(stops.last, right);
    });

    test('three-color ramp yields 11 stops passing through center', () {
      final stops = sliderGradientStops(left, center, right);
      expect(stops.length, 11);
      expect(stops.first, left);
      expect(stops[5], center); // center lands on the middle stop
      expect(stops.last, right);
    });

    test('midpoint matches lerpHsl, not the sRGB midpoint', () {
      // This is the preview-vs-render parity guarantee: the preview chips
      // must sample the gradient with lerpHsl, never a plain sRGB blend.
      final stops = sliderGradientStops(left, null, right);
      expect(stops[5], lerpHsl(left, right, 0.5));
      expect(stops[5], isNot(Color.lerp(left, right, 0.5)));
    });

    test('stop positions are evenly spaced and span 0..1', () {
      final stops = sliderGradientStops(left, center, right);
      final positions = sliderGradientStopPositions(stops);
      expect(positions.length, stops.length);
      expect(positions.first, 0.0);
      expect(positions.last, 1.0);
      expect(positions[5], closeTo(0.5, 1e-9));
    });
  });
}
