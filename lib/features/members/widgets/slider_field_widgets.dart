// Accessibility:
// - Slider relies on its built-in semantics; no outer Semantics(label:) wrap
//   (it would flow up to an ancestor and not decorate the Slider node). The
//   visible Text(field.name) above labels the surrounding row.
// - semanticFormatterCallback announces the value: labeled mode reads
//   '{anchorName}, {percent}%'; numeric mode reads '{value}{unit}'.
// - showValueIndicator: always keeps the editor bubble visible for sighted users.
//
// Display: static render object that paints the same track/thumb without
// Slider state or tickers. Compact: Row of painted track + Text suffix,
// announced via the parent row's label.
//
// Manual VoiceOver/TalkBack verification pending (FFI compile chain blocks
// widget tests in this directory).

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
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
    final parsed = sliderFieldDefinition.valueParser(
      widget.existingValue?.value,
    );
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
    final parsed = sliderFieldDefinition.valueParser(
      widget.existingValue?.value,
    );
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
        if (!identical(_state, priorStateDelete)) {
          return; // user edited mid-flight; let next cycle handle it
        }
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
        if (!identical(_state, priorStateSet)) {
          return; // user edited mid-flight; let next cycle handle it
        }
        _state = _state.onCommitSuccess(
          intent: CommitIntent.set,
          midpoint: _defaultMidpoint(_config()),
        );
        _controller?.markDirty(this, false);
    }
  }

  /// Compute the attributed anchor name + percent for labeled mode.
  String _labeledValueIndicator(
    double value,
    SliderConfig config,
    AppLocalizations l10n,
  ) {
    final center = config.centerLabel;
    final percent = value.round();

    final anchorName = attributedSliderAnchorLabel(value, config);
    if (anchorName == null || anchorName.isEmpty) {
      // No label set for this anchor — fall back to percent only.
      return '$percent%';
    }

    // Exactly on center: use centered variant.
    if (center != null && anchorName == center && (value - 50.0).abs() < 0.5) {
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
    final trackColors = isLabeled ? _resolveTrackColors(config) : null;

    final trackShape = isLabeled && trackColors != null
        ? _GradientSliderTrackShape(colors: trackColors.colors)
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
          shadowColor: _glassShadowColor(theme),
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
        semanticFormatterCallback: (_) => _state.semanticIsUnset
            ? l10n.customFieldSliderNotSet
            : indicatorLabel,
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

    final indicatorLabel = _indicatorLabel(clampedValue, config, context);

    // Parent containers (groups, compact rows, value cards) label children
    // themselves; skip our internal label when they do.
    final showInternalLabel = !CustomFieldDisplayScope.labelHandledFor(context);

    // Glass thumb, tinted by the gradient color at the current position.
    final valueFraction = (max > min)
        ? ((clampedValue - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;
    final positionTint = _gradientColorAt(trackColors, valueFraction);
    final divisions = _divisionsFor(
      isLabeled: isLabeled,
      config: config,
      min: min,
      max: max,
      step: isLabeled ? null : config.step,
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
        Semantics(
          container: true,
          value: indicatorLabel,
          child: _SliderDisplayTrack(
            fraction: valueFraction,
            divisions: divisions,
            isLabeled: isLabeled,
            trackColors: trackColors,
            thumbFillColor: _glassFillColorTinted(theme, positionTint),
            thumbBorderColor: _glassBorderColor(theme),
            thumbShadowColor: _glassShadowColor(theme),
            thumbLabel: isLabeled ? null : indicatorLabel,
            thumbLabelStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
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
      final name = attributedSliderAnchorLabel(value, config);
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

@visibleForTesting
Widget buildSliderDisplayPixelHarness({
  required SliderConfig config,
  required double value,
  required String indicatorLabel,
}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final isLabeled = config.mode == SliderMode.labeled;
      final min = isLabeled ? 0.0 : (config.min ?? 0.0);
      final max = isLabeled ? 100.0 : (config.max ?? 10.0);
      final fraction = (max > min)
          ? ((value - min) / (max - min)).clamp(0.0, 1.0)
          : 0.0;
      final trackColors = isLabeled ? _resolveTrackColors(config) : null;
      final positionTint = _gradientColorAt(trackColors, fraction);
      final divisions = _divisionsFor(
        isLabeled: isLabeled,
        config: config,
        min: min,
        max: max,
        step: isLabeled ? null : config.step,
      );
      return _SliderDisplayTrack(
        fraction: fraction,
        divisions: divisions,
        isLabeled: isLabeled,
        trackColors: trackColors,
        thumbFillColor: _glassFillColorTinted(theme, positionTint),
        thumbBorderColor: _glassBorderColor(theme),
        thumbShadowColor: _glassShadowColor(theme),
        thumbLabel: isLabeled ? null : indicatorLabel,
        thumbLabelStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      );
    },
  );
}

class _SliderDisplayTrack extends LeafRenderObjectWidget {
  const _SliderDisplayTrack({
    required this.fraction,
    required this.divisions,
    required this.isLabeled,
    required this.trackColors,
    required this.thumbFillColor,
    required this.thumbBorderColor,
    required this.thumbShadowColor,
    this.thumbLabel,
    this.thumbLabelStyle,
  });

  final double fraction;
  final int? divisions;
  final bool isLabeled;
  final _TrackColors? trackColors;
  final Color thumbFillColor;
  final Color thumbBorderColor;
  final Color thumbShadowColor;
  final String? thumbLabel;
  final TextStyle? thumbLabelStyle;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSliderDisplayTrack(
      fraction: fraction,
      divisions: divisions,
      isLabeled: isLabeled,
      trackColors: trackColors,
      thumbFillColor: thumbFillColor,
      thumbBorderColor: thumbBorderColor,
      thumbShadowColor: thumbShadowColor,
      thumbLabel: thumbLabel,
      thumbLabelStyle: thumbLabelStyle,
      sliderTheme: SliderTheme.of(context),
      theme: Theme.of(context),
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSliderDisplayTrack renderObject,
  ) {
    renderObject.update(
      fraction: fraction,
      divisions: divisions,
      isLabeled: isLabeled,
      trackColors: trackColors,
      thumbFillColor: thumbFillColor,
      thumbBorderColor: thumbBorderColor,
      thumbShadowColor: thumbShadowColor,
      thumbLabel: thumbLabel,
      thumbLabelStyle: thumbLabelStyle,
      sliderTheme: SliderTheme.of(context),
      theme: Theme.of(context),
      textDirection: Directionality.of(context),
    );
  }
}

class _RenderSliderDisplayTrack extends RenderBox {
  _RenderSliderDisplayTrack({
    required this.fraction,
    required this.divisions,
    required this.isLabeled,
    required this.trackColors,
    required this.thumbFillColor,
    required this.thumbBorderColor,
    required this.thumbShadowColor,
    required this.sliderTheme,
    required this.theme,
    required this.textDirection,
    this.thumbLabel,
    this.thumbLabelStyle,
  });

  double fraction;
  int? divisions;
  bool isLabeled;
  _TrackColors? trackColors;
  Color thumbFillColor;
  Color thumbBorderColor;
  Color thumbShadowColor;
  SliderThemeData sliderTheme;
  ThemeData theme;
  String? thumbLabel;
  TextStyle? thumbLabelStyle;
  TextDirection textDirection;

  static const double _sliderHeight = 48.0;

  void update({
    required double fraction,
    required int? divisions,
    required bool isLabeled,
    required _TrackColors? trackColors,
    required Color thumbFillColor,
    required Color thumbBorderColor,
    required Color thumbShadowColor,
    required SliderThemeData sliderTheme,
    required ThemeData theme,
    required TextDirection textDirection,
    String? thumbLabel,
    TextStyle? thumbLabelStyle,
  }) {
    final changed =
        this.fraction != fraction ||
        this.divisions != divisions ||
        this.isLabeled != isLabeled ||
        !_sameTrackColors(this.trackColors, trackColors) ||
        this.thumbFillColor != thumbFillColor ||
        this.thumbBorderColor != thumbBorderColor ||
        this.thumbShadowColor != thumbShadowColor ||
        this.sliderTheme != sliderTheme ||
        this.theme != theme ||
        this.textDirection != textDirection ||
        this.thumbLabel != thumbLabel ||
        this.thumbLabelStyle != thumbLabelStyle;
    if (!changed) return;

    this.fraction = fraction;
    this.divisions = divisions;
    this.isLabeled = isLabeled;
    this.trackColors = trackColors;
    this.thumbFillColor = thumbFillColor;
    this.thumbBorderColor = thumbBorderColor;
    this.thumbShadowColor = thumbShadowColor;
    this.sliderTheme = sliderTheme;
    this.theme = theme;
    this.textDirection = textDirection;
    this.thumbLabel = thumbLabel;
    this.thumbLabelStyle = thumbLabelStyle;
    markNeedsPaint();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _sliderHeight;

  @override
  double computeMaxIntrinsicHeight(double width) => _sliderHeight;

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth();
    size = constraints.constrain(Size(width, _sliderHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final thumbShape = _GlassThumbShape(
      fillColor: thumbFillColor,
      borderColor: thumbBorderColor,
      shadowColor: thumbShadowColor,
      label: thumbLabel,
      labelTextStyle: thumbLabelStyle,
    );
    final displayTheme = _displayTheme(thumbShape);
    final trackShape =
        displayTheme.trackShape ?? const RoundedRectSliderTrackShape();
    final isDiscrete = divisions != null;
    final thumbCenter = offset + Offset(size.width * fraction, size.height / 2);

    trackShape.paint(
      context,
      offset,
      parentBox: this,
      sliderTheme: displayTheme,
      enableAnimation: kAlwaysDismissedAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      isDiscrete: isDiscrete,
      isEnabled: false,
    );
    _paintTickMarks(
      context: context,
      offset: offset,
      displayTheme: displayTheme,
      trackShape: trackShape,
      thumbCenter: thumbCenter,
    );
    thumbShape.paint(
      context,
      thumbCenter,
      activationAnimation: kAlwaysDismissedAnimation,
      enableAnimation: kAlwaysDismissedAnimation,
      isDiscrete: isDiscrete,
      labelPainter: _emptyLabelPainter(),
      parentBox: this,
      sliderTheme: displayTheme,
      textDirection: textDirection,
      value: fraction,
      textScaleFactor: 1,
      sizeWithOverflow: size,
    );
  }

  void _paintTickMarks({
    required PaintingContext context,
    required Offset offset,
    required SliderThemeData displayTheme,
    required SliderTrackShape trackShape,
    required Offset thumbCenter,
  }) {
    final tickDivisions = divisions;
    final tickMarkShape = displayTheme.tickMarkShape;
    if (tickDivisions == null ||
        tickMarkShape == null ||
        identical(tickMarkShape, SliderTickMarkShape.noTickMark)) {
      return;
    }

    final trackRect = trackShape.getPreferredRect(
      parentBox: this,
      offset: offset,
      sliderTheme: displayTheme,
      isEnabled: false,
      isDiscrete: true,
    );
    final tickMarkWidth = tickMarkShape
        .getPreferredSize(isEnabled: false, sliderTheme: displayTheme)
        .width;
    final discreteTrackPadding = trackRect.height;
    final adjustedTrackWidth = trackRect.width - discreteTrackPadding;
    if (adjustedTrackWidth <= 0) return;
    // Flutter skips all tick marks when they are too dense. Profile display keeps
    // showTicks visible by sampling dense ranges while preserving both endpoints.
    final minTickSpacing = math.max(3.0 * tickMarkWidth, 1.0);
    final tickStride = math.max(
      1,
      (minTickSpacing * tickDivisions / adjustedTrackWidth).ceil(),
    );

    final dy = trackRect.center.dy;
    void paintTick(int index) {
      final value = index / tickDivisions;
      final dx =
          trackRect.left +
          value * adjustedTrackWidth +
          discreteTrackPadding / 2;
      tickMarkShape.paint(
        context,
        Offset(dx, dy),
        parentBox: this,
        sliderTheme: displayTheme,
        enableAnimation: kAlwaysDismissedAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        isEnabled: false,
      );
    }

    var lastPainted = -1;
    for (var i = 0; i <= tickDivisions; i += tickStride) {
      paintTick(i);
      lastPainted = i;
    }
    if (lastPainted != tickDivisions) {
      paintTick(tickDivisions);
    }
  }

  SliderTrackShape? _trackShape() {
    final colors = trackColors;
    if (!isLabeled || colors == null) return null;
    return _GradientSliderTrackShape(colors: colors.colors);
  }

  SliderThemeData _displayTheme(SliderComponentShape thumbShape) {
    final colors = theme.colorScheme;
    // Mirror Slider's current defaulting so the static renderer stays visually
    // identical to the disabled Slider it replaces.
    // ignore: deprecated_member_use
    final year2023 = sliderTheme.year2023 ?? true;
    final material3 = theme.useMaterial3;
    final defaultTrackHeight = material3 ? (year2023 ? 4.0 : 16.0) : 4.0;
    final defaultInactiveTrackColor = material3
        ? (year2023
              ? colors.surfaceContainerHighest
              : colors.secondaryContainer)
        : colors.primary.withValues(alpha: 0.24);
    final defaultDisabledActiveOpacity = material3 ? 0.38 : 0.32;
    final SliderTrackShape defaultTrackShape = material3 && !year2023
        ? const GappedSliderTrackShape()
        : const RoundedRectSliderTrackShape();
    final SliderTickMarkShape defaultTickMarkShape = material3 && !year2023
        ? const RoundSliderTickMarkShape(tickMarkRadius: 2.0)
        : const RoundSliderTickMarkShape();
    final defaultActiveTickMarkColor = material3
        ? (year2023
              ? colors.onPrimary.withValues(alpha: 0.38)
              : colors.onPrimary)
        : colors.onPrimary.withValues(alpha: 0.54);
    final defaultInactiveTickMarkColor = material3
        ? (year2023
              ? colors.onSurfaceVariant.withValues(alpha: 0.38)
              : colors.onSecondaryContainer)
        : colors.primary.withValues(alpha: 0.54);
    final defaultDisabledActiveTickMarkColor = material3
        ? (year2023
              ? colors.onSurface.withValues(alpha: 0.38)
              : colors.onInverseSurface)
        : colors.onPrimary.withValues(alpha: 0.12);
    final defaultDisabledInactiveTickMarkColor = material3
        ? (year2023
              ? colors.onSurface.withValues(alpha: 0.38)
              : colors.onSurface)
        : colors.onSurface.withValues(alpha: 0.12);

    return sliderTheme.copyWith(
      showValueIndicator: ShowValueIndicator.never,
      thumbShape: thumbShape,
      trackShape: _trackShape() ?? sliderTheme.trackShape ?? defaultTrackShape,
      tickMarkShape: sliderTheme.tickMarkShape ?? defaultTickMarkShape,
      trackHeight: isLabeled
          ? 8.0
          : (sliderTheme.trackHeight ?? defaultTrackHeight),
      trackGap: sliderTheme.trackGap ?? (material3 && !year2023 ? 6.0 : null),
      overlayShape: SliderComponentShape.noOverlay,
      activeTrackColor: sliderTheme.activeTrackColor ?? colors.primary,
      inactiveTrackColor:
          sliderTheme.inactiveTrackColor ?? defaultInactiveTrackColor,
      disabledActiveTrackColor:
          sliderTheme.disabledActiveTrackColor ??
          colors.onSurface.withValues(alpha: defaultDisabledActiveOpacity),
      disabledInactiveTrackColor:
          sliderTheme.disabledInactiveTrackColor ??
          colors.onSurface.withValues(alpha: 0.12),
      activeTickMarkColor:
          sliderTheme.activeTickMarkColor ?? defaultActiveTickMarkColor,
      inactiveTickMarkColor:
          sliderTheme.inactiveTickMarkColor ?? defaultInactiveTickMarkColor,
      disabledActiveTickMarkColor:
          sliderTheme.disabledActiveTickMarkColor ??
          defaultDisabledActiveTickMarkColor,
      disabledInactiveTickMarkColor:
          sliderTheme.disabledInactiveTickMarkColor ??
          defaultDisabledInactiveTickMarkColor,
    );
  }

  TextPainter _emptyLabelPainter() {
    return TextPainter(
      text: const TextSpan(text: ''),
      textDirection: textDirection,
    )..layout();
  }
}

bool _sameTrackColors(_TrackColors? a, _TrackColors? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return listEquals(a.colors, b.colors);
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
              colors: trackColors?.colors ??
                  [theme.colorScheme.primary, theme.colorScheme.primary],
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
      return attributedSliderAnchorLabel(value, config) ?? '';
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
  const _GradientSliderTrackShape({required this.colors});

  final List<Color> colors;

  static final Map<String, List<Color>> _colorCache = {};

  List<Color> _buildStops() {
    final key = colors.map((c) => c.toARGB32()).join('_');
    return _colorCache.putIfAbsent(
      key,
      () => sliderGradientStopsFromList(colors),
    );
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

    // Solid: all colors equal — paint as solid fill.
    if (colors.every((c) => c == colors.first)) {
      final paint = Paint()
        ..color = colors.first
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
    final gradient = LinearGradient(
      colors: stops,
      stops: sliderGradientStopPositions(stops),
    );
    final paint = Paint()
      ..shader = gradient.createShader(trackRect)
      ..style = PaintingStyle.fill;

    final radius = Radius.circular(trackRect.height / 2);
    context.canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), paint);
  }
}

// ─── Mini track painter (compact widget) ─────────────────────────────────────

class _MiniTrackPainter extends CustomPainter {
  const _MiniTrackPainter({
    required this.fraction,
    required this.colors,
    required this.isGradient,
    required this.trackColor,
    required this.backgroundColor,
  });

  final double fraction;
  final List<Color> colors;
  final bool isGradient;
  final Color trackColor;
  final Color backgroundColor;

  static final Map<String, List<Color>> _colorCache = {};

  List<Color> _buildStops() {
    final key = colors.map((c) => c.toARGB32()).join('_');
    return _colorCache.putIfAbsent(
      key,
      () => sliderGradientStopsFromList(colors),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 4.0;
    const dotRadius = 5.0;
    final trackY = size.height / 2;
    final trackRect = Rect.fromLTWH(
      0,
      trackY - trackHeight / 2,
      size.width,
      trackHeight,
    );
    const radius = Radius.circular(trackHeight / 2);

    // Background track.
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, radius), bgPaint);

    // Filled portion.
    final fillWidth = size.width * fraction;
    if (fillWidth > 0) {
      final fillRect = Rect.fromLTWH(
        0,
        trackY - trackHeight / 2,
        fillWidth,
        trackHeight,
      );
      Paint fillPaint;
      if (isGradient && !colors.every((c) => c == colors.first)) {
        final stops = _buildStops();
        final gradient = LinearGradient(
          colors: stops,
          stops: sliderGradientStopPositions(stops),
        );
        fillPaint = Paint()
          ..shader = gradient.createShader(trackRect)
          ..style = PaintingStyle.fill;
      } else {
        fillPaint = Paint()
          ..color = isGradient ? colors.first : trackColor
          ..style = PaintingStyle.fill;
      }
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, radius), fillPaint);
    }

    // Dot at current position. Sample the N-color gradient at [fraction] so
    // that interior hues are correct for > 2-color gradients.
    final dotX = math.max(
      dotRadius,
      math.min(size.width - dotRadius, size.width * fraction),
    );
    final dotPaint = Paint()
      ..color = isGradient
          ? _sampleGradientColors(colors, fraction)
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
      !listEquals(old.colors, colors) ||
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

Color _glassShadowColor(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return theme.colorScheme.shadow.withValues(alpha: isDark ? 0.36 : 0.22);
}

/// Sample an N-color list at [t] ∈ [0..1] using HSL interpolation.
///
/// The color list is divided into (N-1) equal segments; [t] selects a segment
/// and then interpolates within it. Works correctly for 2, 3, and N ≥ 4 colors.
Color _sampleGradientColors(List<Color> colors, double t) {
  assert(colors.isNotEmpty);
  if (colors.length == 1) return colors[0];
  final clamped = t.clamp(0.0, 1.0);
  final segments = colors.length - 1;
  final segIndex = (clamped * segments).floor().clamp(0, segments - 1);
  final segT = (clamped * segments - segIndex).clamp(0.0, 1.0);
  return lerpHsl(colors[segIndex], colors[segIndex + 1], segT);
}

/// Sample the gradient at the given fraction [0..1] using the same HSL
/// interpolation as the track shape. Returns null if there's no gradient
/// to sample (numeric mode, missing colors).
Color? _gradientColorAt(_TrackColors? trackColors, double fraction) {
  if (trackColors == null) return null;
  return _sampleGradientColors(trackColors.colors, fraction);
}

/// Blend a track-position color into the base glass fill so the thumb
/// picks up a hint of whatever it's sitting on.
Color _glassFillColorTinted(ThemeData theme, Color? positionTint) {
  final base = _glassFillColor(theme);
  if (positionTint == null) return base;
  return Color.alphaBlend(positionTint.withValues(alpha: 0.32), base);
}

/// Glass-styled slider thumb: translucent rounded pill with a hairline border.
/// Read-only profile values use the same shape so the static renderer preserves
/// the former disabled [Slider] geometry without creating a [Slider] state object.
class _GlassThumbShape extends SliderComponentShape {
  const _GlassThumbShape({
    required this.fillColor,
    required this.borderColor,
    required this.shadowColor,
    this.labelTextStyle,
    this.label,
    this.isUnset = false,
  });

  final Color fillColor;
  final Color borderColor;
  final Color shadowColor;
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
    final shadowRect = rrect.shift(const Offset(0, 1)).inflate(1);

    canvas.drawRRect(
      shadowRect,
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

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
/// dragging). Used only by the editor widget; read-only profile values use a
/// lightweight custom painter.
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

/// Attributes a labeled-slider [value] (0–100) to its owning anchor label.
///
/// Anchors split the range into equal-width buckets: with a center label that
/// is 1:1:1 (left owns 0–33⅓, center 33⅓–66⅔, right 66⅔–100); without one it
/// is 1:1 (crossover at 50). Returns null when the owning anchor has no label.
@visibleForTesting
String? attributedSliderAnchorLabel(double value, SliderConfig config) {
  // Compact rows pass the raw parsed value, which legacy/bad sync data may
  // carry as NaN or infinity. floor() throws on those, so bail to no label.
  if (!value.isFinite) return null;
  final labels = <String?>[
    config.leftLabel,
    if (config.centerLabel != null) config.centerLabel,
    config.rightLabel,
  ];
  final bucket = (value / 100.0 * labels.length).floor().clamp(
    0,
    labels.length - 1,
  );
  return labels[bucket];
}

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
///
/// [colors] is the authoritative N-color list. The legacy getters [left],
/// [center], [right] are kept so all existing call-sites continue to compile
/// unchanged.
class _TrackColors {
  const _TrackColors.fromList(this.colors) : assert(colors.length >= 1);

  /// Convenience constructor that mirrors the old 3-arg API. Builds the list
  /// as `[left, center, right]` (or `[left, right]` when center is null) so
  /// callers that still have discrete colors can construct easily.
  factory _TrackColors({
    required Color left,
    Color? center,
    required Color right,
  }) {
    final list =
        center != null ? [left, center, right] : [left, right];
    return _TrackColors.fromList(list);
  }

  final List<Color> colors;

  Color get left => colors.first;
  Color? get center => colors.length == 3 ? colors[1] : null;
  Color get right => colors.last;
}

/// Resolve the track colors from a [SliderConfig]. Priority:
///   1. Known preset (authoritative even if [gradientColorsHex] is also set).
///   2. [gradientColorsHex], when non-null and has ≥ 2 entries.
///      A non-null but empty or 1-element list falls through to legacy.
///      (Single-color would be a degenerate gradient; fall through is safer.)
///   3. Legacy [leftColorHex] / [rightColorHex] (+ optional center).
///   4. null — no gradient.
_TrackColors? _resolveTrackColors(SliderConfig config) {
  final preset = lookupGradientPreset(config.gradientPresetId);
  if (preset != null) {
    return _TrackColors(
      left: AppColors.fromHex(preset.leftHex),
      center: preset.centerHex != null
          ? AppColors.fromHex(preset.centerHex!)
          : null,
      right: AppColors.fromHex(preset.rightHex),
    );
  }

  // N-color path: gradientColorsHex must have at least 2 entries to be usable
  // as a gradient. Empty or single-element lists fall through to legacy.
  final hexList = config.gradientColorsHex;
  if (hexList != null && hexList.length >= 2) {
    final colorList = hexList.map(AppColors.fromHex).toList(growable: false);
    return _TrackColors.fromList(colorList);
  }

  if (config.leftColorHex != null && config.rightColorHex != null) {
    return _TrackColors(
      left: AppColors.fromHex(config.leftColorHex!),
      center: config.centerColorHex != null
          ? AppColors.fromHex(config.centerColorHex!)
          : null,
      right: AppColors.fromHex(config.rightColorHex!),
    );
  }
  return null;
}

// ─── Test seams ───────────────────────────────────────────────────────────────

/// Exposes [_resolveTrackColors] to widget tests without making the internal
/// class public. Returns the resolved color list, or null if unresolved.
@visibleForTesting
List<Color>? resolveTrackColorsForTest(SliderConfig config) =>
    _resolveTrackColors(config)?.colors;

/// Exposes [_sameTrackColors] comparison (via color lists) to widget tests.
@visibleForTesting
bool sameTrackColorsForTest(List<Color>? a, List<Color>? b) {
  final ta = a == null ? null : _TrackColors.fromList(a);
  final tb = b == null ? null : _TrackColors.fromList(b);
  return _sameTrackColors(ta, tb);
}
