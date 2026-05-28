// Accessibility:
// - Slider relies on its built-in semantics; no outer Semantics(label:) wrap
//   (it would flow up to an ancestor and not decorate the Slider node). The
//   visible Text(field.name) above labels the surrounding row.
// - semanticFormatterCallback announces the value: labeled mode reads
//   '{anchorName}, {percent}%'; numeric mode reads '{value}{unit}'.
// - showValueIndicator: always keeps the bubble visible for sighted users.
//
// Display: same Slider with onChanged: null. Compact: Row of painted track +
// Text suffix, announced via the parent row's label.
//
// Manual VoiceOver/TalkBack verification pending (FFI compile chain blocks
// widget tests in this directory).

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
import 'package:prism_plurality/features/members/widgets/custom_field_display_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/features/members/widgets/slider_edit_state.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';

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

// Reserved trailing slot so the slider row stays stable when × toggles.
const double _kClearButtonSlotSize = 32.0;

class _SliderEditorWidgetState extends ConsumerState<_SliderEditorWidget>
    implements PendingFieldEditState {
  late SliderEditState _state;
  CustomFieldsEditorController? _controller;

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
    final parsedValue = (parsed is SliderFieldValue) ? parsed.value : null;
    if (parsedValue != null) {
      _state = SliderEditState.loaded(value: parsedValue);
    } else {
      _state = SliderEditState.pristine(midpoint: _defaultMidpoint(config));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CustomFieldEditorScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.unregister(this);
    _controller = next;
    _controller?.register(this);
    _controller?.markDirty(this, _isDirty);
  }

  @override
  void didUpdateWidget(covariant _SliderEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRaw = widget.existingValue?.value ?? '';
    final oldRaw = oldWidget.existingValue?.value ?? '';
    if (newRaw == oldRaw) return;
    final parsed = sliderFieldDefinition.valueParser(widget.existingValue?.value);
    final next = (parsed is SliderFieldValue) ? parsed.value : null;
    setState(() {
      _state = _state.onExternalReload(
        newValue: next,
        midpoint: _defaultMidpoint(_config()),
      );
    });
    _controller?.markDirty(this, _isDirty);
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    super.dispose();
  }

  bool get _isDirty => _state.isDirty;

  @override
  String get fieldId => widget.field.id;

  @override
  String get fieldDisplayName => widget.field.name;

  @override
  Future<void> commitPendingValue() async {
    final notifier = ref.read(customFieldValueNotifierProvider.notifier);
    switch (_state.commitIntent) {
      case CommitIntent.noop:
        return;
      case CommitIntent.delete:
        final existingId = widget.existingValue?.id;
        if (existingId == null) {
          // Nothing to delete; normalize local state to pristine.
          _state = _state.onCommitSuccess(
            intent: CommitIntent.delete,
            midpoint: _defaultMidpoint(_config()),
          );
          _controller?.markDirty(this, false);
          return;
        }
        final priorStateDelete = _state;
        final deleteFailure = await notifier.deleteValue(existingId);
        if (deleteFailure != null) throw deleteFailure;
        if (!mounted) return;
        if (!identical(_state, priorStateDelete)) return; // user edited mid-flight; let next cycle handle it
        _state = _state.onCommitSuccess(
          intent: CommitIntent.delete,
          midpoint: _defaultMidpoint(_config()),
        );
        _controller?.markDirty(this, false);
      case CommitIntent.set:
        final encoded = sliderFieldDefinition.valueEncoder(
          SliderFieldValue(value: _state.currentValue),
        );
        final priorStateSet = _state;
        final setFailure = await notifier.setValue(
          customFieldId: widget.field.id,
          memberId: widget.memberId,
          value: encoded,
          existingId: widget.existingValue?.id,
        );
        if (setFailure != null) throw setFailure;
        if (!mounted) return;
        if (!identical(_state, priorStateSet)) return; // user edited mid-flight; let next cycle handle it
        _state = _state.onCommitSuccess(
          intent: CommitIntent.set,
          midpoint: _defaultMidpoint(_config()),
        );
        _controller?.markDirty(this, false);
    }
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
      return l10n.customFieldSliderValueLabelCentered(anchorName, percent);
    }

    return l10n.customFieldSliderValueLabel(anchorName, percent);
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
    final rawMin = isLabeled ? 0.0 : (config.min ?? 0.0);
    final rawMax = isLabeled ? 100.0 : (config.max ?? 10.0);
    // Defensive guard: bad legacy data may carry NaN, infinity, or min >= max.
    // The config UI now blocks these, but row-level bad data could still slip
    // through sync from older builds. Snap to sane defaults so Slider can't
    // crash. NaN comparisons are always false in IEEE 754, so isFinite must
    // come first.
    final (double min, double max) = (rawMin.isFinite && rawMax.isFinite)
        ? (rawMin < rawMax ? (rawMin, rawMax) : (rawMin, rawMin + 1.0))
        : (0.0, isLabeled ? 100.0 : 10.0);
    final step = isLabeled ? null : config.step;

    // Clamp current value to valid range.
    final clampedValue = _state.currentValue.isFinite
        ? _state.currentValue.clamp(min, max)
        : min;

    final divisions = _divisionsFor(
      isLabeled: isLabeled,
      config: config,
      min: min,
      max: max,
      step: step,
    );

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

    // No outer Semantics(label:) wrap here: the visible Text(field.name) above
    // already labels the surrounding row, and Slider's internal
    // Semantics(container: true) is a fresh boundary — an outer
    // Semantics(container: false) label would flow upward to an ancestor
    // instead of decorating the Slider. semanticFormatterCallback below is
    // what announces the current value to assistive tech.
    final editorFraction = (max > min)
        ? ((clampedValue - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;
    final editorPositionTint = _gradientColorAt(trackColors, editorFraction);
    final slider = SliderTheme(
      data: theme.sliderTheme.copyWith(
        // ignore: deprecated_member_use — spec §2d requires always-visible indicator
        showValueIndicator: ShowValueIndicator.always,
        valueIndicatorShape: _GlassValueIndicatorShape(
          fillColor: _glassFillColorTinted(theme, editorPositionTint),
          borderColor: _glassBorderColor(theme),
        ),
        valueIndicatorTextStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
        // No overlay + zero-width glass thumb removes the track's edge
        // inset, so the track aligns with sibling content. Thumb fill
        // picks up the gradient color at the current value's position.
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: _GlassThumbShape(
          fillColor: _glassFillColorTinted(theme, editorPositionTint),
          borderColor: _glassBorderColor(theme),
          isUnset: _state.semanticIsUnset,
        ),
        trackShape: trackShape,
        trackHeight: isLabeled ? 8.0 : null,
      ),
      child: Slider(
        value: clampedValue,
        min: min,
        max: max,
        divisions: divisions,
        label: indicatorLabel,
        semanticFormatterCallback: (_) =>
            _state.semanticIsUnset ? l10n.customFieldSliderNotSet : indicatorLabel,
        onChanged: (v) => setState(() => _state = _state.onDrag(v)),
        onChangeEnd: (v) {
          setState(() => _state = _state.onDragEnd(v));
          _controller?.markDirty(this, _state.isDirty);
        },
      ),
    );

    final sliderRow = Row(
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80),
            child: slider,
          ),
        ),
        SizedBox(
          width: _kClearButtonSlotSize,
          height: _kClearButtonSlotSize,
          child: _state.canClear
              ? PrismFieldIconButton(
                  icon: AppIcons.clear,
                  tooltip: l10n.customFieldSliderClearTooltip,
                  onPressed: () {
                    setState(() => _state = _state.onClear());
                    _controller?.markDirty(this, _state.isDirty);
                  },
                )
              : null,
        ),
      ],
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
        sliderRow,
        if (isLabeled) ...[
          const SizedBox(height: 6),
          _SliderLabelRow(config: config),
        ],
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
    final rawMin = isLabeled ? 0.0 : (config.min ?? 0.0);
    final rawMax = isLabeled ? 100.0 : (config.max ?? 10.0);
    // Defensive guard: see _SliderEditorWidgetState.build for rationale.
    final (double min, double max) = (rawMin.isFinite && rawMax.isFinite)
        ? (rawMin < rawMax ? (rawMin, rawMax) : (rawMin, rawMin + 1.0))
        : (0.0, isLabeled ? 100.0 : 10.0);
    final clampedValue = currentValue.isFinite
        ? currentValue.clamp(min, max)
        : min;

    final trackColors = isLabeled ? _resolveTrackColors(config) : null;

    final trackShape = isLabeled && trackColors != null
        ? _GradientSliderTrackShape(
            leftColor: trackColors.left,
            centerColor: trackColors.center,
            rightColor: trackColors.right,
          )
        : null;

    final indicatorLabel = _indicatorLabel(clampedValue, config, context);

    final divisions = _divisionsFor(
      isLabeled: isLabeled,
      config: config,
      min: min,
      max: max,
      step: isLabeled ? null : config.step,
    );

    // Parent containers (groups, compact rows, value cards) label children
    // themselves; skip our internal label when they do.
    final showInternalLabel = !CustomFieldDisplayScope.labelHandledFor(context);

    // Glass thumb, tinted by the gradient color at the current position.
    // Numeric mode paints the value text inside the thumb since Flutter's
    // built-in ShowValueIndicator skips painting for read-only sliders.
    final valueFraction = (max > min)
        ? ((clampedValue - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;
    final positionTint = _gradientColorAt(trackColors, valueFraction);
    final thumbShape = _GlassThumbShape(
      fillColor: _glassFillColorTinted(theme, positionTint),
      borderColor: _glassBorderColor(theme),
      labelTextStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
      label: isLabeled ? null : indicatorLabel,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showInternalLabel) ...[
          Text(
            field.name,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // No outer Semantics(label:) wrap — see _SliderEditorWidgetState.build
        // for rationale. The visible Text(field.name) above (or the
        // group-level header) provides the label;
        // semanticFormatterCallback announces the current value.
        SliderTheme(
          data: theme.sliderTheme.copyWith(
            showValueIndicator: ShowValueIndicator.never,
            thumbShape: thumbShape,
            trackShape: trackShape,
            trackHeight: isLabeled ? 8.0 : null,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: clampedValue,
            min: min,
            max: max,
            divisions: divisions,
            label: indicatorLabel,
            semanticFormatterCallback: (_) => indicatorLabel,
            onChanged: null, // read-only
          ),
        ),
        if (isLabeled) ...[
          const SizedBox(height: 6),
          _SliderLabelRow(config: config),
        ],
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
/// Mini-track widget with filled bar + dot + word suffix. [trackWidth]
/// defaults to a width that reads well in narrow list rows; surfaces with
/// more horizontal room can pass a larger value.
Widget buildSliderCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value, {
  double trackWidth = 60,
}) {
  return _SliderCompactWidget(
    field: field,
    value: value,
    trackWidth: trackWidth,
  );
}

class _SliderCompactWidget extends StatelessWidget {
  const _SliderCompactWidget({
    required this.field,
    required this.value,
    this.trackWidth = 60,
  });

  final CustomField field;
  final CustomFieldValue value;
  final double trackWidth;

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
          width: trackWidth,
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

// ─── Glass slider component shapes ────────────────────────────────────────────

/// Translucent fill for the glass thumb / value indicator. Painted to
/// canvas, so no [BackdropFilter] — uses higher alpha and an [onSurface]
/// tint to keep readable over colorful gradient tracks.
Color _glassFillColor(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  final base = theme.colorScheme.surfaceContainerHigh.withValues(
    alpha: isDark ? 0.62 : 0.88,
  );
  final tint = theme.colorScheme.onSurface.withValues(
    alpha: isDark ? 0.22 : 0.10,
  );
  return Color.alphaBlend(tint, base);
}

Color _glassBorderColor(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return theme.colorScheme.outlineVariant.withValues(
    alpha: isDark ? 0.85 : 0.65,
  );
}

/// Sample the gradient at the given fraction [0..1] using the same HSL
/// interpolation as the track shape. Returns null if there's no gradient
/// to sample (numeric mode, missing colors).
Color? _gradientColorAt(_TrackColors? trackColors, double fraction) {
  if (trackColors == null) return null;
  final t = fraction.clamp(0.0, 1.0);
  final center = trackColors.center;
  if (center == null) {
    return lerpHsl(trackColors.left, trackColors.right, t);
  }
  if (t < 0.5) return lerpHsl(trackColors.left, center, t * 2);
  return lerpHsl(center, trackColors.right, (t - 0.5) * 2);
}

/// Blend a track-position color into the base glass fill so the thumb
/// picks up a hint of whatever it's sitting on.
Color _glassFillColorTinted(ThemeData theme, Color? positionTint) {
  final base = _glassFillColor(theme);
  if (positionTint == null) return base;
  return Color.alphaBlend(positionTint.withValues(alpha: 0.45), base);
}

/// Glass-styled slider thumb: translucent rounded pill with a hairline
/// border. When [label] is non-null the thumb expands horizontally to fit
/// the text — used by the read-only display widget for numeric mode, since
/// Flutter's [ShowValueIndicator] doesn't paint for disabled sliders.
class _GlassThumbShape extends SliderComponentShape {
  const _GlassThumbShape({
    required this.fillColor,
    required this.borderColor,
    this.labelTextStyle,
    this.label,
    this.isUnset = false,
  });

  final Color fillColor;
  final Color borderColor;
  final TextStyle? labelTextStyle;
  final String? label;
  // Dims the thumb fill to ~40% alpha to signal "no value".
  final bool isUnset;

  static const double _bareSize = 22.0;
  static const double _pillHeight = 22.0;
  static const double _pillHorizontalPadding = 10.0;

  /// Zero WIDTH skips the slider's per-thumb track inset, so the track
  /// sits flush with its parent column's content edges. Real HEIGHT keeps
  /// the slider's intrinsic row from collapsing. [paint] draws at the
  /// real visual size; the small overflow at extreme values bleeds into
  /// the surrounding card padding.
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(0, _visualSize().height);

  Size _visualSize() {
    if (label == null) return const Size(_bareSize, _bareSize);
    final painter = _measureLabel();
    final width = painter.width + (_pillHorizontalPadding * 2);
    return Size(math.max(width, _bareSize), _pillHeight);
  }

  TextPainter _measureLabel() {
    return TextPainter(
      text: TextSpan(text: label, style: labelTextStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final size = _visualSize();
    final rect = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
    final radius = Radius.circular(size.height / 2);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    final effectiveFill = isUnset
        ? fillColor.withValues(alpha: fillColor.a * 0.4)
        : fillColor;
    canvas.drawRRect(rrect, Paint()..color = effectiveFill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (label != null) {
      final painter = _measureLabel();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }
}

/// Glass-styled value indicator (the popup that floats above the thumb while
/// dragging). Used by the editor widget; the display widget hides the
/// built-in indicator and paints the value directly in [_GlassThumbShape].
class _GlassValueIndicatorShape extends SliderComponentShape {
  const _GlassValueIndicatorShape({
    required this.fillColor,
    required this.borderColor,
  });

  final Color fillColor;
  final Color borderColor;

  static const double _height = 26.0;
  static const double _horizontalPadding = 10.0;
  static const double _verticalGapAboveThumb = 8.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(0, _height + _verticalGapAboveThumb);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final opacity = activationAnimation.value;
    if (opacity <= 0) return;

    final width = labelPainter.width + (_horizontalPadding * 2);
    final pillCenter = Offset(
      center.dx,
      center.dy - (_height / 2) - _verticalGapAboveThumb,
    );
    final rect = Rect.fromCenter(
      center: pillCenter,
      width: width,
      height: _height,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_height / 2),
    );

    canvas.drawRRect(
      rrect,
      Paint()..color = fillColor.withValues(alpha: fillColor.a * opacity),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withValues(alpha: borderColor.a * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final textOpacity = (labelPainter.text?.style?.color?.a ?? 1.0) * opacity;
    final originalSpan = labelPainter.text;
    if (originalSpan is TextSpan && originalSpan.style != null) {
      labelPainter.text = TextSpan(
        text: originalSpan.text,
        style: originalSpan.style!.copyWith(
          color: originalSpan.style!.color?.withValues(alpha: textOpacity),
        ),
      );
      labelPainter.layout();
    }
    labelPainter.paint(
      canvas,
      pillCenter - Offset(labelPainter.width / 2, labelPainter.height / 2),
    );
  }
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

    if (left.isEmpty && right.isEmpty && center == null) {
      return const SizedBox.shrink();
    }

    // The slider's zero-inset thumb makes its track land flush with the
    // parent's content edges, so anchor labels sit flush there too.
    return Row(
      children: [
        Text(left, style: labelStyle, overflow: TextOverflow.ellipsis),
        if (center != null) ...[
          const Spacer(),
          Text(center, style: labelStyle, overflow: TextOverflow.ellipsis),
        ],
        const Spacer(),
        Text(right, style: labelStyle, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Labeled mode snaps via `snapToPositions`; numeric mode snaps and draws
/// ticks only when `showTicks` is on. Returns null for a continuous slider.
int? _divisionsFor({
  required bool isLabeled,
  required SliderConfig config,
  required double min,
  required double max,
  required double? step,
}) {
  if (isLabeled) {
    if (!config.snapToPositions) return null;
    return config.centerLabel != null ? 4 : 2;
  }
  if (!config.showTicks || step == null || step <= 0) return null;
  final range = max - min;
  if (range <= 0) return null;
  final divisions = (range / step).round();
  return divisions > 0 ? divisions : null;
}

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
