import 'package:flutter/material.dart';

enum SliderGradientCategory {
  identity,
  moodIntensity,
  temperature,
  palette,
  neutral,
}

class SliderGradientPreset {
  const SliderGradientPreset({
    required this.id,
    required this.labelL10nKey,
    required this.category,
    required this.leftHex,
    this.centerHex,
    required this.rightHex,
  });

  final String id;
  final String labelL10nKey;
  final SliderGradientCategory category;
  final String leftHex;
  final String? centerHex;
  final String rightHex;
}

const List<SliderGradientPreset> kSliderGradientPresets = [
  // Identity — gender-axis presets recolored to break the pink↔blue stereotype (NOT pride-flag palettes).
  SliderGradientPreset(
    id: 'femme-masc',
    labelL10nKey: 'sliderGradientPresetFemmeMasc',
    category: SliderGradientCategory.identity,
    leftHex: '#E89BB8',
    centerHex: '#F0E6D6',
    rightHex: '#8FAA9A',
  ),
  SliderGradientPreset(
    id: 'high-low-gender',
    labelL10nKey: 'sliderGradientPresetHighLowGender',
    category: SliderGradientCategory.identity,
    leftHex: '#F0D070',
    rightHex: '#5B4378',
  ),

  // Mood / intensity
  SliderGradientPreset(
    id: 'soft-hard',
    labelL10nKey: 'sliderGradientPresetSoftHard',
    category: SliderGradientCategory.moodIntensity,
    leftHex: '#F4EBD8',
    centerHex: '#A89B8C',
    rightHex: '#3A2E4D',
  ),
  SliderGradientPreset(
    id: 'calm-intense',
    labelL10nKey: 'sliderGradientPresetCalmIntense',
    category: SliderGradientCategory.moodIntensity,
    leftHex: '#7BAA7E', // sage
    rightHex: '#D6534D', // red
  ),
  SliderGradientPreset(
    id: 'sad-happy',
    labelL10nKey: 'sliderGradientPresetSadHappy',
    category: SliderGradientCategory.moodIntensity,
    leftHex: '#5479AE', // blue
    rightHex: '#E4C44F', // yellow
  ),
  SliderGradientPreset(
    id: 'low-high-energy',
    labelL10nKey: 'sliderGradientPresetLowHighEnergy',
    category: SliderGradientCategory.moodIntensity,
    leftHex: '#8A8A8A', // gray
    rightHex: '#E69248', // orange
  ),
  SliderGradientPreset(
    id: 'soft-bold',
    labelL10nKey: 'sliderGradientPresetSoftBold',
    category: SliderGradientCategory.moodIntensity,
    leftHex: '#D8C7E0',
    rightHex: '#2D1B36',
  ),

  // Temperature
  SliderGradientPreset(
    id: 'cool-warm',
    labelL10nKey: 'sliderGradientPresetCoolWarm',
    category: SliderGradientCategory.temperature,
    leftHex: '#5B92C9',
    rightHex: '#E08D5E',
  ),
  SliderGradientPreset(
    id: 'day-night',
    labelL10nKey: 'sliderGradientPresetDayNight',
    category: SliderGradientCategory.temperature,
    leftHex: '#F4D86E', // sun
    rightHex: '#1E2444', // deep navy
  ),

  // Palette — curated color-story presets not tied to any axis meaning
  SliderGradientPreset(
    id: 'palette-rose-dusk',
    labelL10nKey: 'sliderGradientPresetPaletteRoseDusk',
    category: SliderGradientCategory.palette,
    leftHex: '#F4B89E',
    centerHex: '#D17A8E',
    rightHex: '#5B4378',
  ),
  SliderGradientPreset(
    id: 'palette-sage-meadow',
    labelL10nKey: 'sliderGradientPresetPaletteSageMeadow',
    category: SliderGradientCategory.palette,
    leftHex: '#C5D9B5',
    rightHex: '#4A6B47',
  ),
  SliderGradientPreset(
    id: 'palette-last-light',
    labelL10nKey: 'sliderGradientPresetPaletteLastLight',
    category: SliderGradientCategory.palette,
    leftHex: '#F0C166',
    centerHex: '#E68769',
    rightHex: '#8F4438',
  ),
  SliderGradientPreset(
    id: 'palette-amber-fire',
    labelL10nKey: 'sliderGradientPresetPaletteAmberFire',
    category: SliderGradientCategory.palette,
    leftHex: '#F0D88E',
    rightHex: '#C44848',
  ),
  SliderGradientPreset(
    id: 'palette-mauve-bloom',
    labelL10nKey: 'sliderGradientPresetPaletteMauveBloom',
    category: SliderGradientCategory.palette,
    leftHex: '#EAD9E8',
    rightHex: '#5B4378',
  ),
  SliderGradientPreset(
    id: 'palette-warm-ink',
    labelL10nKey: 'sliderGradientPresetPaletteWarmInk',
    category: SliderGradientCategory.palette,
    leftHex: '#F4EBD8',
    rightHex: '#3A2E2A',
  ),

  // Neutral
  SliderGradientPreset(
    id: 'solid-accent',
    labelL10nKey: 'sliderGradientPresetSolidAccent',
    category: SliderGradientCategory.neutral,
    leftHex: '#7B5EA8', // single color (left and right same)
    rightHex: '#7B5EA8',
  ),
  SliderGradientPreset(
    id: 'monochrome',
    labelL10nKey: 'sliderGradientPresetMonochrome',
    category: SliderGradientCategory.neutral,
    leftHex: '#E4DEEC', // light
    rightHex: '#3A2E4D', // dark of same hue family
  ),
];

SliderGradientPreset? lookupGradientPreset(String? id) {
  if (id == null) return null;
  for (final p in kSliderGradientPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// HSL interpolation between two colors. Drop-in for [Color.lerp] when you
/// need perceptually smoother gradients across hue (avoids the muddy
/// brown/gray midpoints that sRGB lerp produces).
Color lerpHsl(Color a, Color b, double t) {
  final hslA = HSLColor.fromColor(a);
  final hslB = HSLColor.fromColor(b);
  // Choose the shorter path around the hue circle.
  var hA = hslA.hue;
  var hB = hslB.hue;
  if ((hB - hA).abs() > 180) {
    if (hB > hA) {
      hA += 360;
    } else {
      hB += 360;
    }
  }
  final h = ((hA + (hB - hA) * t) % 360 + 360) % 360;
  final s = hslA.saturation + (hslB.saturation - hslA.saturation) * t;
  final l = hslA.lightness + (hslB.lightness - hslA.lightness) * t;
  return HSLColor.fromAHSL(1.0, h, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0))
      .toColor();
}
