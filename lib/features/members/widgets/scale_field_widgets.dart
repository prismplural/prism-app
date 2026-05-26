// ## Accessibility
//
// **Editor**
// - Emoji row wrapped in Semantics(slider: true, value: '{fieldName}, {step}/{total}',
//   label: '{fieldName}', onLongPress: clear) so screen readers treat the row
//   as a single interactive slider widget.
// - SemanticsService.sendAnnouncement fires "{fieldName} cleared" when the
//   user long-presses to clear, giving immediate feedback to VoiceOver/TalkBack.
//
// **Display**
// - Outer Semantics(label: '{fieldName}, {step}/{total} stars', excludeSemantics: true)
//   collapses the individual emoji glyph children into a single readable value.
//
// **Compact**
// - Renders as plain Text('{emoji} {step}/{total}') — inherits parent row's
//   semantics; no extra wrapper needed.
//
// Manual VoiceOver/TalkBack verification pending — pre-existing FFI compile
// chain blocks widget tests in this directory.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/definitions/scale_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ─── Editor ───────────────────────────────────────────────────────────────────

/// Builds the interactive scale editor widget. Called by the renderer registry.
Widget buildScaleEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return _ScaleEditorWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

/// Stateful editor for a Scale custom field. Renders a row of N emoji glyphs
/// with 48dp tap targets; tapping a glyph sets the rating; a trailing × button
/// and long-press on the row both clear the value.
class _ScaleEditorWidget extends ConsumerStatefulWidget {
  const _ScaleEditorWidget({
    required this.field,
    required this.memberId,
    this.existingValue,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;

  @override
  ConsumerState<_ScaleEditorWidget> createState() => _ScaleEditorWidgetState();
}

class _ScaleEditorWidgetState extends ConsumerState<_ScaleEditorWidget>
    implements PendingFieldEditState {
  // The index (0-based) of the emoji that was JUST tapped and is briefly scaled up.
  int? _animatingIndex;
  // null = cleared or never set.
  int? _step;
  int? _initialStep;
  CustomFieldsEditorController? _controller;

  @override
  void initState() {
    super.initState();
    _initialStep = _parseValue(widget.existingValue?.value).step;
    _step = _initialStep;
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
  void didUpdateWidget(covariant _ScaleEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRaw = widget.existingValue?.value ?? '';
    final oldRaw = oldWidget.existingValue?.value ?? '';
    if (newRaw == oldRaw) return;
    final nextStep = _parseValue(widget.existingValue?.value).step;
    setState(() {
      _initialStep = nextStep;
      _step = nextStep;
    });
    _controller?.markDirty(this, _isDirty);
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    super.dispose();
  }

  ScaleFieldValue _parseValue(String? raw) {
    final parsed = scaleFieldDefinition.valueParser(raw);
    return parsed is ScaleFieldValue ? parsed : const ScaleFieldValue();
  }

  ScaleConfig _config() {
    final c = widget.field.typeConfig;
    return c is ScaleConfig ? c : const ScaleConfig();
  }

  bool get _isDirty => _step != _initialStep;

  void _setStep(int step) {
    if (_step == step) return;
    setState(() => _step = step);
    _controller?.markDirty(this, _isDirty);
  }

  void _clearValue() {
    if (_step == null) return;
    setState(() => _step = null);
    _controller?.markDirty(this, _isDirty);
  }

  @override
  Future<void> commitPendingValue() async {
    if (_step == _initialStep) return;
    final notifier = ref.read(customFieldValueNotifierProvider.notifier);
    final step = _step;
    if (step == null || step < 1) {
      final existingId = widget.existingValue?.id;
      if (existingId != null) {
        await notifier.deleteValue(existingId);
      }
    } else {
      final encoded = scaleFieldDefinition.valueEncoder(
        ScaleFieldValue(step: step),
      );
      await notifier.setValue(
        customFieldId: widget.field.id,
        memberId: widget.memberId,
        value: encoded,
        existingId: widget.existingValue?.id,
      );
    }
    _initialStep = _step;
    _controller?.markDirty(this, false);
  }

  void _triggerAnimatingStep(int index) {
    setState(() => _animatingIndex = index);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _animatingIndex = null);
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    try {
      final view = View.maybeOf(context);
      if (view == null) return;
      unawaited(
        SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
      );
    } catch (_) {
      // Best-effort — screen-reader hints, not a contract.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final config = _config();
    final emoji = config.emoji;
    final steps = config.steps;

    final selectedStep = _step;
    final hasValue = selectedStep != null && selectedStep >= 1;

    final disableAnimations = MediaQuery.of(context).disableAnimations;

    final emojiRow = Wrap(
      children: List.generate(steps, (i) {
        final isActive = hasValue && (i + 1) <= selectedStep;
        final isAnimating = _animatingIndex == i;
        final scaleValue = (!disableAnimations && isAnimating) ? 1.2 : 1.0;

        final emojiWidget = RepaintBoundary(
          child: AnimatedScale(
            scale: scaleValue,
            duration: isAnimating
                ? const Duration(milliseconds: 150)
                : const Duration(milliseconds: 200),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Opacity(
                  opacity: isActive ? 1.0 : 0.4,
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ),
          ),
        );

        return GestureDetector(
          onTap: () {
            _triggerAnimatingStep(i);
            _setStep(i + 1);
          },
          child: emojiWidget,
        );
      }),
    );

    final semanticsLabel = hasValue
        ? l10n.customFieldScaleSemanticLabel(
            widget.field.name,
            selectedStep,
            steps,
          )
        : widget.field.name;

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
        Row(
          children: [
            Expanded(
              child: Semantics(
                slider: true,
                value: semanticsLabel,
                label: widget.field.name,
                onLongPress: hasValue
                    ? () {
                        _clearValue();
                        _announce(l10n.customFieldScaleClearedAnnouncement);
                      }
                    : null,
                child: GestureDetector(
                  onLongPress: hasValue
                      ? () {
                          _clearValue();
                          _announce(l10n.customFieldScaleClearedAnnouncement);
                        }
                      : null,
                  child: emojiRow,
                ),
              ),
            ),
            if (hasValue)
              Tooltip(
                message: l10n.customFieldScaleClearTooltip,
                child: IconButton(
                  icon: Icon(AppIcons.close, size: 18),
                  onPressed: _clearValue,
                  color: theme.colorScheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Display ──────────────────────────────────────────────────────────────────

/// Builds the read-only display widget for a Scale field value.
Widget buildScaleDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _ScaleDisplayWidget(field: field, value: value);
}

class _ScaleDisplayWidget extends StatelessWidget {
  const _ScaleDisplayWidget({required this.field, required this.value});

  final CustomField field;
  final CustomFieldValue value;

  ScaleConfig _config() {
    final c = field.typeConfig;
    return c is ScaleConfig ? c : const ScaleConfig();
  }

  ScaleFieldValue _parseValue(String? raw) {
    final parsed = scaleFieldDefinition.valueParser(raw);
    return parsed is ScaleFieldValue ? parsed : const ScaleFieldValue();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final config = _config();
    final emoji = config.emoji;
    final steps = config.steps;

    final currentValue = _parseValue(value.value);
    final selectedStep = currentValue.step;
    final hasValue = selectedStep != null && selectedStep >= 1;

    if (!hasValue) return const SizedBox.shrink();

    final semanticsLabel = l10n.customFieldScaleSemanticLabel(
      field.name,
      selectedStep,
      steps,
    );

    // Parent containers (groups, compact rows, value cards) label children
    // themselves; skip our internal label when they do.
    final showInternalLabel = !CustomFieldDisplayScope.labelHandledFor(context);

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
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
          Wrap(
            children: List.generate(steps, (i) {
              final isActive = (i + 1) <= selectedStep;
              return RepaintBoundary(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Opacity(
                      opacity: isActive ? 1.0 : 0.4,
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Compact ──────────────────────────────────────────────────────────────────

/// Builds the compact list-row display for a Scale field value.
/// Shows "{emoji} {step}/{total}" on a single line when value is set,
/// otherwise returns [SizedBox.shrink].
Widget buildScaleCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _ScaleCompactWidget(field: field, value: value);
}

/// Mini visual rendering — a row of emojis at [emojiSize], dimmed for steps
/// past the selected value. Returns [SizedBox.shrink] when no value is set.
Widget buildScaleMini(
  BuildContext context,
  CustomField field,
  CustomFieldValue value, {
  double emojiSize = 14,
}) {
  return _ScaleMiniWidget(
    field: field,
    value: value,
    emojiSize: emojiSize,
  );
}

class _ScaleMiniWidget extends StatelessWidget {
  const _ScaleMiniWidget({
    required this.field,
    required this.value,
    required this.emojiSize,
  });

  final CustomField field;
  final CustomFieldValue value;
  final double emojiSize;

  @override
  Widget build(BuildContext context) {
    final config = field.typeConfig is ScaleConfig
        ? field.typeConfig! as ScaleConfig
        : const ScaleConfig();
    final parsed = scaleFieldDefinition.valueParser(value.value);
    final selectedStep = parsed is ScaleFieldValue ? parsed.step : null;
    if (selectedStep == null || selectedStep < 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < config.steps; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Opacity(
            opacity: (i + 1) <= selectedStep ? 1.0 : 0.35,
            child: Text(
              config.emoji,
              style: TextStyle(fontSize: emojiSize),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScaleCompactWidget extends StatelessWidget {
  const _ScaleCompactWidget({required this.field, required this.value});

  final CustomField field;
  final CustomFieldValue value;

  ScaleConfig _config() {
    final c = field.typeConfig;
    return c is ScaleConfig ? c : const ScaleConfig();
  }

  ScaleFieldValue _parseValue(String? raw) {
    final parsed = scaleFieldDefinition.valueParser(raw);
    return parsed is ScaleFieldValue ? parsed : const ScaleFieldValue();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config();
    final emoji = config.emoji;
    final steps = config.steps;

    final currentValue = _parseValue(value.value);
    final selectedStep = currentValue.step;
    final hasValue = selectedStep != null && selectedStep >= 1;

    if (!hasValue) return const SizedBox.shrink();

    return Text(
      '$emoji $selectedStep/$steps',
      overflow: TextOverflow.ellipsis,
    );
  }
}
