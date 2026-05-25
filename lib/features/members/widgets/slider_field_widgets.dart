// ## Accessibility
//
// **Editor**
// - Slider wrapped in Semantics(label: '{fieldName}').
// - Flutter's built-in Slider provides semanticFormatterCallback that
//   maps the raw double to a human-readable string:
//   - Labeled mode: '{nearestAnchorName}, {percent}%' (or just '{percent}%'
//     when no anchor label is set).
//   - Numeric mode: '{value}{unit}'.
// - showValueIndicator: ShowValueIndicator.always ensures the value bubble
//   is always visible, which also feeds the system accessibility value.
//
// **Display**
// - Same Slider with onChanged: null (read-only). Value indicator still
//   renders, giving screen readers the current value via the semantic formatter.
//
// **Compact**
// - Renders as a Row of SizedBox custom-painted track + Text suffix.
//   Screen readers announce the suffix text via the parent row's label.
//   No extra Semantics wrappers needed.
//
// Manual VoiceOver/TalkBack verification pending — pre-existing FFI compile
// chain blocks widget tests in this directory.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/definitions/slider_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/slider_gradient_presets.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

// ─── Editor ───────────────────────────────────────────────────────────────────

/// Builds the interactive slider editor widget. Called by the renderer registry.
Widget buildSliderEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return _SliderEditorWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

/// Stateful editor for a Slider custom field.
/// Renders a [Slider] with a gradient track for labeled mode or solid for
/// numeric mode. Saves on [onChangeEnd] to avoid heavy writes during drag.
class _SliderEditorWidget extends ConsumerStatefulWidget {
  const _SliderEditorWidget({
    required this.field,
    required this.memberId,
    this.existingValue,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;

  @override
  ConsumerState<_SliderEditorWidget> createState() =>
      _SliderEditorWidgetState();
}

class _SliderEditorWidgetState extends ConsumerState<_SliderEditorWidget> {
  late double _currentValue;

  SliderConfig _config() {
    final c = widget.field.typeConfig;
    if (c is SliderConfig) return c;
    // Default: labeled mode with solid-accent preset.
    return const SliderConfig(
      mode: SliderMode.labeled,
      gradientPresetId: 'solid-accent',
    );
  }

  double _defaultMidpoint(SliderConfig config) {
    if (config.mode == SliderMode.numeric) {
      final min = config.min ?? 0.0;
      final max = config.max ?? 10.0;
      return (min + max) / 2.0;
    }
    return 50.0; // labeled mode: 0..100, midpoint = 50
  }

  @override
  void initState() {
    super.initState();
    final config = _config();
    final parsed = sliderFieldDefinition.valueParser(widget.existingValue?.value);
    if (parsed is SliderFieldValue && parsed.value != null) {
      _currentValue = parsed.value!;
    } else {
      _currentValue = _defaultMidpoint(config);
    }
  }

  Future<void> _persistValue(double value) async {
    final encoded = sliderFieldDefinition
        .valueEncoder(SliderFieldValue(value: value));
    final notifier = ref.read(customFieldValueNotifierProvider.notifier);
    await notifier.setValue(
      customFieldId: widget.field.id,
      memberId: widget.memberId,
      value: encoded,
      existingId: widget.existingValue?.id,
    );
  }

  /// Compute the nearest anchor name + percent for labeled mode.
  String _labeledValueIndicator(
    double value,
    SliderConfig config,
    AppLocalizations l10n,
  ) {
    final left = config.leftLabel;
    final right = config.rightLabel;
    final center = config.centerLabel;
    final percent = value.round();

    // Build list of anchors with their positions.
    final anchors = <({double position, String? label})>[
      (position: 0.0, label: left),
      if (center != null) (position: 50.0, label: center),
      (position: 100.0, label: right),
    ];

    // Find the nearest anchor.
    var nearest = anchors.first;
    var minDist = (value - nearest.position).abs();
    for (final anchor in anchors) {
      final dist = (value - anchor.position).abs();
      if (dist < minDist) {
        minDist = dist;
        nearest = anchor;
      }
    }

    final anchorName = nearest.label;
    if (anchorName == null || anchorName.isEmpty) {
      // No label set for this anchor — fall back to percent only.
      return '$percent%';
    }

    // Exactly on center: use centered variant.
    if (center != null &&
        anchorName == center &&
        (value - 50.0).abs() < 0.5) {
      return l10n.customFieldSliderValueLabelCentered(
        anchor: anchorName,
        percent: percent,
      );
    }

    return l10n.customFieldSliderValueLabel(
      anchor: anchorName,
      percent: percent,
    );
  }

  /// Compute display text for numeric mode.
  String _numericValueIndicator(double value, SliderConfig config) {
    final step = config.step ?? 1.0;
    final unit = config.unit ?? '';
    final decimals = _stepDecimals(step);
    final formatted = value.toStringAsFixed(decimals);
    return '$formatted$unit';
  }

  /// Number of decimal places to show for a given step value.
  int _stepDecimals(double step) {
    final str = step.toString();
    final dotIndex = str.indexOf('.');
    if (dotIndex < 0) return 0;
    // Count meaningful trailing digits after the decimal.
    final afterDot = str.substring(dotIndex + 1);
    // Trim trailing zeros.
    var len = afterDot.length;
    while (len > 0 && afterDot[len - 1] == '0') {
      len--;
    }
    return len;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final config = _config();

    final isLabeled = config.mode == SliderMode.labeled;
    final min = isLabeled ? 0.0 : (config.min ?? 0.0);
    final max = isLabeled ? 100.0 : (config.max ?? 10.0);
    final step = isLabeled ? null : config.step;

    // Clamp current value to valid range.
    final clampedValue = _currentValue.clamp(min, max);

    // Compute divisions.
    int? divisions;
    if (isLabeled) {
      if (config.snapToPositions) {
        // 3 snaps (0/50/100) when no center; 5 snaps (0/25/50/75/100) with center.
        divisions = config.centerLabel != null ? 4 : 2;
      }
      // else continuous (divisions = null)
    } else if (step != null && step > 0) {
      final range = max - min;
      if (range > 0) {
        divisions = (range / step).round();
        if (divisions <= 0) divisions = null;
      }
    }

    // Value indicator label.
    final indicatorLabel = isLabeled
        ? _labeledValueIndicator(clampedValue, config, l10n)
        : _numericValueIndicator(clampedValue, config);

    // Build gradient colors for labeled mode.
    final trackColors = isLabeled
        ? _resolveTrackColors(config)
        : null;

    final trackShape = isLabeled && trackColors != null
        ? _GradientSliderTrackShape(
            leftColor: trackColors.left,
            centerColor: trackColors.center,
            rightColor: trackColors.right,
          )
        : null;

    final slider = SliderTheme(
      data: theme.sliderTheme.copyWith(
        // ignore: deprecated_member_use — spec §2d requires always-visible indicator
        showValueIndicator: ShowValueIndicator.always,
        trackShape: trackShape,
        trackHeight: isLabeled ? 8.0 : null,
      ),
      child: Semantics(
        label: widget.field.name,
        child: Slider(
          value: clampedValue,
          min: min,
          max: max,
          divisions: divisions,
          label: indicatorLabel,
          semanticFormatterCallback: (_) => indicatorLabel,
          onChanged: (v) => setState(() => _currentValue = v),
          onChangeEnd: (v) {
            setState(() => _currentValue = v);
            unawaited(_persistValue(v));
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.field.name,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        slider,
        if (isLabeled) _SliderLabelRow(config: config),
      ],
    );
  }
}

// ─── Display ──────────────────────────────────────────────────────────────────

/// Builds the read-only display widget for a Slider field value.
Widget buildSliderDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _SliderDisplayWidget(field: field, value: value);
}

class _SliderDisplayWidget extends StatelessWidget {
  const _SliderDisplayWidget({required this.field, required this.value});

  final CustomField field;
  final CustomFieldValue value;

  SliderConfig _config() {
    final c = field.typeConfig;
    if (c is SliderConfig) return c;
    return const SliderConfig(
      mode: SliderMode.labeled,
      gradientPresetId: 'solid-accent',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _config();

    final parsed = sliderFieldDefinition.valueParser(value.value);
    if (parsed is! SliderFieldValue || parsed.value == null) {
      return const SizedBox.shrink();
    }
    final currentValue = parsed.value!;

    final isLabeled = config.mode == SliderMode.labeled;
    final min = isLabeled ? 0.0 : (config.min ?? 0.0);
    final max = isLabeled ? 100.0 : (config.max ?? 10.0);
    final clampedValue = currentValue.clamp(min, max);

    final trackColors = isLabeled ? _resolveTrackColors(config) : null;

    final trackShape = isLabeled && trackColors != null
        ? _GradientSliderTrackShape(
            leftColor: trackColors.left,
            centerColor: trackColors.center,
            rightColor: trackColors.right,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          field.name,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: theme.sliderTheme.copyWith(
            // ignore: deprecated_member_use — spec §2d requires always-visible indicator
        showValueIndicator: ShowValueIndicator.always,
            trackShape: trackShape,
            trackHeight: isLabeled ? 8.0 : null,
          ),
          child: Slider(
            value: clampedValue,
            min: min,
            max: max,
            label: _indicatorLabel(clampedValue, config, context),
            onChanged: null, // read-only
          ),
        ),
        if (isLabeled) _SliderLabelRow(config: config),
      ],
    );
  }

  String _indicatorLabel(
    double value,
    SliderConfig config,
    BuildContext context,
  ) {
    if (config.mode == SliderMode.labeled) {
      final percent = value.round();
      final anchors = <({double position, String? label})>[
        (position: 0.0, label: config.leftLabel),
        if (config.centerLabel != null)
          (position: 50.0, label: config.centerLabel),
        (position: 100.0, label: config.rightLabel),
      ];
      var nearest = anchors.first;
      var minDist = (value - nearest.position).abs();
      for (final anchor in anchors) {
        final dist = (value - anchor.position).abs();
        if (dist < minDist) {
          minDist = dist;
          nearest = anchor;
        }
      }
      final name = nearest.label;
      if (name == null || name.isEmpty) return '$percent%';
      return '$name, $percent%';
    } else {
      final step = config.step ?? 1.0;
      final unit = config.unit ?? '';
      final decimals = _stepDecimals(step);
      return '${value.toStringAsFixed(decimals)}$unit';
    }
  }

  int _stepDecimals(double step) {
    final str = step.toString();
    final dotIndex = str.indexOf('.');
    if (dotIndex < 0) return 0;
    final afterDot = str.substring(dotIndex + 1);
    var len = afterDot.length;
    while (len > 0 && afterDot[len - 1] == '0') {
      len--;
    }
    return len;
  }
}

// ─── Compact ──────────────────────────────────────────────────────────────────

/// Builds the compact list-row display for a Slider field value.
/// Shows a 60dp mini-track widget with filled bar + dot + word suffix.
Widget buildSliderCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _SliderCompactWidget(field: field, value: value);
}

class _SliderCompactWidget extends StatelessWidget {
  const _SliderCompactWidget({required this.field, required this.value});

  final CustomField field;
  final CustomFieldValue value;

  SliderConfig _config() {
    final c = field.typeConfig;
    if (c is SliderConfig) return c;
    return const SliderConfig(
      mode: SliderMode.labeled,
      gradientPresetId: 'solid-accent',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _config();

    final parsed = sliderFieldDefinition.valueParser(value.value);
    if (parsed is! SliderFieldValue || parsed.value == null) {
      return const SizedBox.shrink();
    }
    final currentValue = parsed.value!;

    final isLabeled = config.mode == SliderMode.labeled;
    final min = isLabeled ? 0.0 : (config.min ?? 0.0);
    final max = isLabeled ? 100.0 : (config.max ?? 10.0);
    final fraction = max > min
        ? ((currentValue - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;

    final trackColors = isLabeled ? _resolveTrackColors(config) : null;

    // Compute suffix.
    final suffix = _computeSuffix(currentValue, config);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 16,
          child: CustomPaint(
            painter: _MiniTrackPainter(
              fraction: fraction,
              leftColor: trackColors?.left ?? theme.colorScheme.primary,
              centerColor: trackColors?.center,
              rightColor: trackColors?.right ?? theme.colorScheme.primary,
              isGradient: isLabeled,
              trackColor: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        if (suffix.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            suffix,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  String _computeSuffix(double value, SliderConfig config) {
    if (config.mode == SliderMode.labeled) {
      // Nearest anchor name.
      final anchors = <({double position, String? label})>[
        (position: 0.0, label: config.leftLabel),
        if (config.centerLabel != null)
          (position: 50.0, label: config.centerLabel),
        (position: 100.0, label: config.rightLabel),
      ];
      var nearest = anchors.first;
      var minDist = (value - nearest.position).abs();
      for (final anchor in anchors) {
        final dist = (value - anchor.position).abs();
        if (dist < minDist) {
          minDist = dist;
          nearest = anchor;
        }
      }
      return nearest.label ?? '';
    } else {
      final step = config.step ?? 1.0;
      final unit = config.unit ?? '';
      final decimals = _stepDecimals(step);
      return '${value.toStringAsFixed(decimals)}$unit';
    }
  }

  int _stepDecimals(double step) {
    final str = step.toString();
    final dotIndex = str.indexOf('.');
    if (dotIndex < 0) return 0;
    final afterDot = str.substring(dotIndex + 1);
    var len = afterDot.length;
    while (len > 0 && afterDot[len - 1] == '0') {
      len--;
    }
    return len;
  }
}

// ─── Gradient track shape ─────────────────────────────────────────────────────

/// A [SliderTrackShape] that paints an HSL-interpolated gradient for labeled
/// mode. For numeric mode, the solid default is used (pass null instead).
///
/// Gradient colors are computed with 11 HSL-sampled stops for smooth hue
/// travel, then cached by the color tuple to avoid per-build allocations.
class _GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  const _GradientSliderTrackShape({
    required this.leftColor,
    this.centerColor,
    required this.rightColor,
  });

  final Color leftColor;
  final Color? centerColor;
  final Color rightColor;

  /// Cache keyed by a string representation of the color tuple.
  static final Map<String, List<Color>> _colorCache = {};

  List<Color> _buildStops() {
    final key = '${leftColor.toARGB32()}_${centerColor?.toARGB32()}_${rightColor.toARGB32()}';
    return _colorCache.putIfAbsent(key, () {
      final center = centerColor;
      if (center == null) {
        // 11 stops: left → right.
        return [
          for (var i = 0; i <= 10; i++) lerpHsl(leftColor, rightColor, i / 10),
        ];
      } else {
        // 6 stops left → center, 5 stops center → right (11 total).
        return [
          for (var i = 0; i <= 5; i++) lerpHsl(leftColor, center, i / 5),
          for (var i = 1; i <= 5; i++) lerpHsl(center, rightColor, i / 5),
        ];
      }
    });
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // Let the parent paint the inactive track first.
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    // Now paint the gradient over the full track rect (active portion).
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    // Solid accent: both colors equal — paint as solid fill.
    if (leftColor == rightColor && centerColor == null) {
      final paint = Paint()
        ..color = leftColor
        ..style = PaintingStyle.fill;
      final radius = Radius.circular(trackRect.height / 2);
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(trackRect, radius),
        paint,
      );
      return;
    }

    // Full-width gradient over the entire track.
    final stops = _buildStops();
    final stopPositions = [
      for (var i = 0; i < stops.length; i++) i / (stops.length - 1),
    ];
    final gradient = LinearGradient(
      colors: stops,
      stops: stopPositions,
    );
    final paint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;

    final radius = Radius.circular(trackRect.height / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      paint,
    );
  }
}

// ─── Mini track painter (compact widget) ─────────────────────────────────────

class _MiniTrackPainter extends CustomPainter {
  const _MiniTrackPainter({
    required this.fraction,
    required this.leftColor,
    this.centerColor,
    required this.rightColor,
    required this.isGradient,
    required this.trackColor,
    required this.backgroundColor,
  });

  final double fraction;
  final Color leftColor;
  final Color? centerColor;
  final Color rightColor;
  final bool isGradient;
  final Color trackColor;
  final Color backgroundColor;

  static final Map<String, List<Color>> _colorCache = {};

  List<Color> _buildStops() {
    final key = '${leftColor.toARGB32()}_${centerColor?.toARGB32()}_${rightColor.toARGB32()}';
    return _colorCache.putIfAbsent(key, () {
      final center = centerColor;
      if (center == null) {
        return [
          for (var i = 0; i <= 10; i++) lerpHsl(leftColor, rightColor, i / 10),
        ];
      } else {
        return [
          for (var i = 0; i <= 5; i++) lerpHsl(leftColor, center, i / 5),
          for (var i = 1; i <= 5; i++) lerpHsl(center, rightColor, i / 5),
        ];
      }
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 4.0;
    const dotRadius = 5.0;
    final trackY = size.height / 2;
    final trackRect = Rect.fromLTWH(0, trackY - trackHeight / 2, size.width, trackHeight);
    const radius = Radius.circular(trackHeight / 2);

    // Background track.
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), bgPaint);

    // Filled portion.
    final fillWidth = size.width * fraction;
    if (fillWidth > 0) {
      final fillRect = Rect.fromLTWH(0, trackY - trackHeight / 2, fillWidth, trackHeight);
      Paint fillPaint;
      if (isGradient && leftColor != rightColor) {
        final stops = _buildStops();
        final stopPositions = [
          for (var i = 0; i < stops.length; i++) i / (stops.length - 1),
        ];
        final gradient = LinearGradient(
          colors: stops,
          stops: stopPositions,
        );
        fillPaint = Paint()
          ..shader = gradient.createShader(trackRect)
          ..style = PaintingStyle.fill;
      } else {
        fillPaint = Paint()
          ..color = isGradient ? leftColor : trackColor
          ..style = PaintingStyle.fill;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),
        fillPaint,
      );
    }

    // Dot at current position.
    final dotX = math.max(dotRadius, math.min(size.width - dotRadius, size.width * fraction));
    final dotPaint = Paint()
      ..color = isGradient
          ? lerpHsl(leftColor, rightColor, fraction)
          : trackColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(dotX, trackY), dotRadius, dotPaint);
    // Outline on dot.
    final outlinePaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(dotX, trackY), dotRadius, outlinePaint);
  }

  @override
  bool shouldRepaint(_MiniTrackPainter old) =>
      old.fraction != fraction ||
      old.leftColor != leftColor ||
      old.centerColor != centerColor ||
      old.rightColor != rightColor ||
      old.isGradient != isGradient;
}

// ─── Slider label row ─────────────────────────────────────────────────────────

/// Renders left / center / right labels below the slider for labeled mode.
class _SliderLabelRow extends StatelessWidget {
  const _SliderLabelRow({required this.config});

  final SliderConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final left = config.leftLabel ?? '';
    final right = config.rightLabel ?? '';
    final center = config.centerLabel;

    if (left.isEmpty && right.isEmpty && center == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 0),
      child: Row(
        children: [
          Text(left, style: labelStyle, overflow: TextOverflow.ellipsis),
          if (center != null) ...[
            const Spacer(),
            Text(center, style: labelStyle, overflow: TextOverflow.ellipsis),
          ],
          const Spacer(),
          Text(right, style: labelStyle, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Resolved track colors from a [SliderConfig].
class _TrackColors {
  const _TrackColors({
    required this.left,
    this.center,
    required this.right,
  });
  final Color left;
  final Color? center;
  final Color right;
}

/// Resolve the track colors from a [SliderConfig]. Prefers custom hex colors
/// (from "Advanced: custom colors" override), falling back to the preset.
_TrackColors? _resolveTrackColors(SliderConfig config) {
  // Custom colors take priority over presets.
  if (config.leftColorHex != null && config.rightColorHex != null) {
    return _TrackColors(
      left: AppColors.fromHex(config.leftColorHex!),
      center: config.centerColorHex != null
          ? AppColors.fromHex(config.centerColorHex!)
          : null,
      right: AppColors.fromHex(config.rightColorHex!),
    );
  }
  // Fall back to preset.
  final preset = lookupGradientPreset(config.gradientPresetId);
  if (preset != null) {
    return _TrackColors(
      left: AppColors.fromHex(preset.leftHex),
      center: preset.centerHex != null ? AppColors.fromHex(preset.centerHex!) : null,
      right: AppColors.fromHex(preset.rightHex),
    );
  }
  return null;
}
