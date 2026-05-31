// ## Accessibility
//
// **Editor chips**
// - Each active option chip: Semantics(button: true, label: '{fieldName}, {option.label}, selected/not selected').
// - Each deleted-but-still-selected option chip: Semantics(button: true, label: '{fieldName}, {option.label}, selected/not selected, removed').
// - "Other…" chip: Semantics(button: true, label: '{fieldName}, Other, selected/not selected').
// - Other text field: Semantics(textField: true, label: 'Other, free text').
//
// **Display chips** (read-only profile view)
// - Selected option chips: Semantics(button: false, label: '{fieldName}, {option.label}, selected'[, removed]).
// - Other text pill: Semantics(button: false, label: '{fieldName}, Other: {text}').
//
// **Compact chips** (list-row)
// - Each visible option chip: Semantics(button: false, label: '{fieldName}, {label}, selected'[, removed]).
// - Other pill: Semantics(button: false, label: '{fieldName}, Other: {text}').
//
// Manual VoiceOver/TalkBack verification pending.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_color_picker_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

// ─── Editor ───────────────────────────────────────────────────────────────────

/// Builds the interactive choice editor widget. Called by the renderer registry.
Widget buildChoiceEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return _ChoiceEditorWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

/// Stateful editor for a Choice custom field. Renders a [Wrap] of tinted
/// chips — one per non-deleted option — plus an optional pinned "Other" chip
/// with an inline text entry.
///
/// Long-pressing any option chip opens a context menu to edit its label,
/// cycle its color, or soft-delete it (which writes through to the field
/// config via [writeTypedConfig]).
class _ChoiceEditorWidget extends ConsumerStatefulWidget {
  const _ChoiceEditorWidget({
    required this.field,
    required this.memberId,
    this.existingValue,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;

  @override
  ConsumerState<_ChoiceEditorWidget> createState() =>
      _ChoiceEditorWidgetState();
}

class _ChoiceEditorWidgetState extends ConsumerState<_ChoiceEditorWidget>
    with AutomaticKeepAliveClientMixin<_ChoiceEditorWidget>
    implements PendingFieldEditState {
  late ChoiceFieldValue _initialValue;
  late ChoiceFieldValue _currentValue;
  late TextEditingController _otherController;
  // Buffered "Other" text; flushed into _currentValue on focus loss or commit.
  String? _pendingOtherText;
  final Map<String, GlobalKey<BlurPopupAnchorState>> _popupKeys = {};
  CustomFieldsEditorController? _controller;
  bool _keepAlive = false;

  @override
  void initState() {
    super.initState();
    _initialValue = _parseValue(widget.existingValue?.value);
    _currentValue = _initialValue;
    _otherController = TextEditingController(text: _currentValue.other ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CustomFieldEditorScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.unregister(this);
    _controller = next;
    _controller?.register(this);
    _syncDirtyState();
  }

  @override
  void didUpdateWidget(covariant _ChoiceEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRaw = widget.existingValue?.value ?? '';
    final oldRaw = oldWidget.existingValue?.value ?? '';
    if (newRaw == oldRaw) return;
    // External update (sync stream). Adopt as the new baseline; an in-flight
    // local edit gets clobbered, which is rare and recoverable.
    final next = _parseValue(widget.existingValue?.value);
    setState(() {
      _initialValue = next;
      _currentValue = next;
    });
    final newOther = next.other ?? '';
    if (_otherController.text != newOther) {
      _otherController.text = newOther;
    }
    _syncDirtyState();
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    _otherController.dispose();
    super.dispose();
  }

  ChoiceFieldValue _parseValue(String? raw) {
    final parsed = choiceFieldDefinition.valueParser(raw);
    return parsed is ChoiceFieldValue ? parsed : const ChoiceFieldValue();
  }

  ChoiceConfig? _config() {
    final c = widget.field.typeConfig;
    return c is ChoiceConfig ? c : null;
  }

  GlobalKey<BlurPopupAnchorState> _popupKeyFor(String optionId) {
    return _popupKeys.putIfAbsent(
      optionId,
      GlobalKey<BlurPopupAnchorState>.new,
    );
  }

  bool get _isDirty {
    if (_currentValue != _initialValue) return true;
    // _pendingOtherText holds in-flight typing between keystrokes and blur;
    // include it so the dismiss guard sees unsaved text in the Other field.
    final pending = _pendingOtherText;
    return pending != null && pending.trim() != (_currentValue.other ?? '');
  }

  @override
  bool get wantKeepAlive => _keepAlive;

  void _syncDirtyState() {
    final dirty = _isDirty;
    _controller?.markDirty(this, dirty);
    if (_keepAlive == dirty) return;
    _keepAlive = dirty;
    updateKeepAlive();
  }

  void _stage(ChoiceFieldValue newValue) {
    if (newValue == _currentValue) return;
    setState(() => _currentValue = newValue);
    _syncDirtyState();
  }

  @override
  String get fieldId => widget.field.id;

  @override
  String get fieldDisplayName => widget.field.name;

  @override
  Future<void> commitPendingValue() async {
    // Flush unblurred Other text (Save tapped with keyboard still up).
    final pendingOther = _pendingOtherText;
    if (pendingOther != null) {
      _pendingOtherText = null;
      _currentValue = _currentValue.copyWith(other: pendingOther.trim());
    }
    if (_currentValue == _initialValue) return;
    final encoded = choiceFieldDefinition.valueEncoder(_currentValue);
    final notifier = ref.read(customFieldValueNotifierProvider.notifier);
    Object? failure;
    if (encoded.isEmpty) {
      final existingId = widget.existingValue?.id;
      if (existingId != null) {
        failure = await notifier.deleteValue(existingId);
      }
    } else {
      failure = await notifier.setValue(
        customFieldId: widget.field.id,
        memberId: widget.memberId,
        value: encoded,
        existingId: widget.existingValue?.id,
      );
    }
    // On failure: leave _initialValue alone and stay dirty so the bulk-commit
    // collects the error AND a re-touch re-stages and re-saves cleanly.
    if (failure != null) throw failure;
    _initialValue = _currentValue;
    _syncDirtyState();
  }

  void _toggleOption(String optionId, bool allowsMultiple) {
    final selected = Set<String>.of(_currentValue.optionIds);
    if (selected.contains(optionId)) {
      selected.remove(optionId);
    } else {
      if (!allowsMultiple) {
        selected.clear();
      }
      selected.add(optionId);
    }
    _stage(_currentValue.copyWith(optionIds: selected));
  }

  Future<void> _handleLongPress(
    BuildContext context,
    ChoiceConfig config,
    ChoiceOption option,
  ) async {
    _popupKeyFor(option.id).currentState?.show();
  }

  Future<void> _editOptionLabel(
    BuildContext context,
    ChoiceConfig config,
    ChoiceOption option,
  ) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: option.label);
    final confirmed = await PrismDialog.show<bool>(
      context: context,
      title: l10n.customFieldChoiceEditLabelDialogTitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.save),
        ),
      ],
      builder: (ctx) => PrismTextField(
        controller: controller,
        autofocus: true,
        hintText: l10n.customFieldChoiceOptionLabelHint,
        onSubmitted: (_) => Navigator.of(ctx).pop(true),
      ),
    );
    if (confirmed != true || !mounted) return;

    final newLabel = controller.text.trim();
    if (newLabel.isEmpty) return;

    final updatedOptions = [
      for (final o in config.options)
        if (o.id == option.id) o.copyWith(label: newLabel) else o,
    ];
    final updatedConfig = config.copyWith(options: updatedOptions);
    final err = await ref
        .read(customFieldNotifierProvider.notifier)
        .writeTypedConfig(widget.field.id, updatedConfig);
    if (err == null) return;
    if (!context.mounted) return;
    PrismToast.error(
      context,
      message: context.l10n.settingsCreateEditFieldSaveError(err.toString()),
    );
  }

  Future<void> _pickOptionColor(
    BuildContext context,
    ChoiceConfig config,
    ChoiceOption option,
  ) async {
    Color initial;
    try {
      initial = option.colorHex != null
          ? AppColors.fromHex(option.colorHex!)
          : Theme.of(context).colorScheme.primary;
    } catch (_) {
      initial = Theme.of(context).colorScheme.primary;
    }
    final newColor = await showPrismColorPickerDialog(
      context: context,
      initialColor: initial,
    );
    if (newColor == null || !mounted) return;
    final updatedOptions = [
      for (final o in config.options)
        if (o.id == option.id) o.copyWith(colorHex: newColor) else o,
    ];
    final updatedConfig = config.copyWith(options: updatedOptions);
    final err = await ref
        .read(customFieldNotifierProvider.notifier)
        .writeTypedConfig(widget.field.id, updatedConfig);
    if (err == null) return;
    if (!context.mounted) return;
    PrismToast.error(
      context,
      message: context.l10n.settingsCreateEditFieldSaveError(err.toString()),
    );
  }

  Future<void> _deleteOption(
    BuildContext context,
    ChoiceConfig config,
    ChoiceOption option,
  ) async {
    final l10n = context.l10n;
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: l10n.customFieldChoiceDeleteOptionTitle,
      message: l10n.customFieldChoiceDeleteOptionMessage(option.label),
      confirmLabel: l10n.customFieldChoiceDeleteMenuLabel,
      destructive: true,
      icon: AppIcons.warningAmber,
    );
    if (!confirmed || !mounted) return;

    final updatedOptions = [
      for (final o in config.options)
        if (o.id == option.id) o.copyWith(isDeleted: true) else o,
    ];
    final updatedConfig = config.copyWith(options: updatedOptions);
    final err = await ref
        .read(customFieldNotifierProvider.notifier)
        .writeTypedConfig(widget.field.id, updatedConfig);
    if (err == null) return;
    if (!context.mounted) return;
    PrismToast.error(
      context,
      message: context.l10n.settingsCreateEditFieldSaveError(err.toString()),
    );
  }

  /// Empty trimmed text stays as `''` so the Other selection survives;
  /// deselect only happens by tapping the chip.
  void _flushOtherText() {
    final pending = _pendingOtherText;
    _pendingOtherText = null;
    if (pending == null) return;
    _stage(_currentValue.copyWith(other: pending.trim()));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = context.l10n;
    final config = _config();
    if (config == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final allowsMultiple = config.allowsMultiple;
    final allowsOther = config.allowsOther;
    // null = never tapped; '' = tapped, no text yet; non-empty = typed.
    final isOtherSelected = _currentValue.other != null;

    // Separate active vs deleted options.
    final activeOptions = config.options.where((o) => !o.isDeleted).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    // Deleted options that are still selected for this member.
    final deletedButSelected = config.options
        .where((o) => o.isDeleted && _currentValue.optionIds.contains(o.id))
        .toList();

    final chips = <Widget>[
      for (final option in activeOptions)
        _buildOptionChip(context, theme, config, option, allowsMultiple),
      for (final option in deletedButSelected)
        _buildDeletedOptionChip(context, theme, option),
      if (allowsOther) _buildOtherChip(context, theme, isOtherSelected),
    ];

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
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: chips),
        if (allowsOther && isOtherSelected) ...[
          const SizedBox(height: 8),
          // Fix 3: Semantics wrapper for Other text field (accessibility HARD GATE).
          Semantics(
            textField: true,
            label: l10n.customFieldChoiceOtherSemanticLabel,
            child: Focus(
              // Fix 6: save on focus loss instead of on every keystroke.
              onFocusChange: (hasFocus) {
                if (!hasFocus) _flushOtherText();
              },
              child: PrismTextField(
                controller: _otherController,
                hintText: l10n.customFieldChoiceOtherTextHint,
                autofocus: true,
                minLines: 1,
                maxLines: 2,
                onChanged: (text) {
                  _pendingOtherText = text;
                  _syncDirtyState();
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOptionChip(
    BuildContext context,
    ThemeData theme,
    ChoiceConfig config,
    ChoiceOption option,
    bool allowsMultiple,
  ) {
    final l10n = context.l10n;
    final isSelected = _currentValue.optionIds.contains(option.id);
    final color = option.colorHex != null
        ? AppColors.fromHex(option.colorHex!)
        : null;

    final popupKey = _popupKeyFor(option.id);
    // Fix 3: spec-mandated Semantics for option chips in the editor.
    final semanticLabel =
        '${widget.field.name}, ${option.label}, '
        '${isSelected ? l10n.customFieldChoiceSelectedSuffix : l10n.customFieldChoiceNotSelectedSuffix}';

    return BlurPopupAnchor(
      key: popupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: BlurPopupDirection.down,
      width: 220,
      maxHeight: 180,
      itemCount: 3,
      itemBuilder: (ctx, index, close) {
        return switch (index) {
          0 => PrismListRow(
            dense: true,
            leading: Icon(AppIcons.edit, size: 20),
            title: Text(l10n.customFieldChoiceEditMenuLabel),
            onTap: () {
              close();
              unawaited(_editOptionLabel(context, config, option));
            },
          ),
          1 => PrismListRow(
            dense: true,
            leading: Icon(AppIcons.palette, size: 20),
            title: Text(l10n.customFieldChoiceChangeColorMenuLabel),
            onTap: () {
              close();
              unawaited(_pickOptionColor(context, config, option));
            },
          ),
          _ => PrismListRow(
            dense: true,
            destructive: true,
            leading: Icon(
              AppIcons.delete,
              size: 20,
              color: theme.colorScheme.error,
            ),
            title: Text(l10n.customFieldChoiceDeleteMenuLabel),
            onTap: () {
              close();
              unawaited(_deleteOption(context, config, option));
            },
          ),
        };
      },
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: GestureDetector(
          onLongPress: () => _handleLongPress(context, config, option),
          child: PrismChip(
            label: option.label,
            selected: isSelected,
            selectedColor: color,
            tintColor: isSelected ? color : null,
            onTap: () => _toggleOption(option.id, allowsMultiple),
          ),
        ),
      ),
    );
  }

  Widget _buildDeletedOptionChip(
    BuildContext context,
    ThemeData theme,
    ChoiceOption option,
  ) {
    final l10n = context.l10n;
    final isSelected = _currentValue.optionIds.contains(option.id);
    // Fix 3: Semantics for deleted option chips.
    final semanticLabel =
        '${widget.field.name}, ${option.label}, '
        '${isSelected ? l10n.customFieldChoiceSelectedSuffix : l10n.customFieldChoiceNotSelectedSuffix}, '
        '${l10n.customFieldChoiceRemovedSuffix}';
    return Tooltip(
      message: l10n.customFieldChoiceRemovedSuffix,
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Opacity(
          opacity: 0.45,
          child: PrismChip(
            label: option.label,
            selected: isSelected,
            // Fix 5: deleted chips are not tappable in editor.
            onTap: null,
          ),
        ),
      ),
    );
  }

  Widget _buildOtherChip(
    BuildContext context,
    ThemeData theme,
    bool isSelected,
  ) {
    final l10n = context.l10n;
    // Fix 3: Semantics for Other chip.
    final semanticLabel =
        '${widget.field.name}, ${l10n.customFieldChoiceOtherChipLabel}, '
        '${isSelected ? l10n.customFieldChoiceSelectedSuffix : l10n.customFieldChoiceNotSelectedSuffix}';
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PrismChip(
        label: l10n.customFieldChoiceOtherChipLabel,
        selected: isSelected,
        onTap: () {
          if (isSelected) {
            // Deselect: clear other text.
            _pendingOtherText = null;
            _otherController.clear();
            _stage(_currentValue.copyWith(other: null));
          } else {
            // Select: mark as other-selected with empty text for now.
            _stage(_currentValue.copyWith(other: ''));
          }
        },
      ),
    );
  }
}

// ─── Display ──────────────────────────────────────────────────────────────────

List<ChoiceOption> _selectedOptionsInSettingsOrder(
  ChoiceConfig config,
  ChoiceFieldValue value,
) {
  final selectedIds = value.optionIds;
  final indexedOptions = <MapEntry<int, ChoiceOption>>[];
  for (var i = 0; i < config.options.length; i++) {
    final option = config.options[i];
    if (selectedIds.contains(option.id)) {
      indexedOptions.add(MapEntry(i, option));
    }
  }
  return (indexedOptions..sort((a, b) {
        final sortOrderCompare = a.value.sortOrder.compareTo(b.value.sortOrder);
        if (sortOrderCompare != 0) return sortOrderCompare;
        return a.key.compareTo(b.key);
      }))
      .map((entry) => entry.value)
      .toList();
}

/// Builds the read-only display chip row for a Choice field value.
Widget buildChoiceDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _ChoiceDisplayWidget(field: field, value: value);
}

class _ChoiceDisplayWidget extends StatelessWidget {
  const _ChoiceDisplayWidget({required this.field, required this.value});

  final CustomField field;
  final CustomFieldValue value;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = field.typeConfig;
    if (config is! ChoiceConfig) {
      return Text(value.value);
    }

    final parsed = choiceFieldDefinition.valueParser(value.value);
    final choiceValue = parsed is ChoiceFieldValue
        ? parsed
        : const ChoiceFieldValue();

    if (choiceValue.optionIds.isEmpty &&
        (choiceValue.other == null || choiceValue.other!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final chips = <Widget>[];

    for (final option in _selectedOptionsInSettingsOrder(config, choiceValue)) {
      final color = option.colorHex != null
          ? AppColors.fromHex(option.colorHex!)
          : null;
      final isDeleted = option.isDeleted;

      // Fix 3: Semantics for display chips.
      final semanticLabel =
          '${field.name}, ${option.label}, '
          '${l10n.customFieldChoiceSelectedSuffix}'
          '${isDeleted ? ', ${l10n.customFieldChoiceRemovedSuffix}' : ''}';

      Widget chip = Semantics(
        button: false,
        label: semanticLabel,
        excludeSemantics: true,
        child: PrismChip(
          label: option.label,
          selected: true,
          tintColor: color,
          onTap: null,
        ),
      );
      if (isDeleted) {
        chip = Tooltip(
          message: l10n.customFieldChoiceRemovedSuffix,
          child: Opacity(opacity: 0.45, child: chip),
        );
      }
      chips.add(chip);
    }

    if (choiceValue.other != null && choiceValue.other!.isNotEmpty) {
      final otherLabel = l10n.customFieldChoiceOtherPrefix(choiceValue.other!);
      chips.add(
        Semantics(
          button: false,
          label: '${field.name}, $otherLabel',
          excludeSemantics: true,
          child: PrismChip(label: otherLabel, selected: true, onTap: null),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }
}

// ─── Compact ──────────────────────────────────────────────────────────────────

/// Builds the compact list-row chip display for a Choice field value.
Widget buildChoiceCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _ChoiceCompactWidget(field: field, value: value);
}

class _ChoiceCompactWidget extends StatelessWidget {
  const _ChoiceCompactWidget({required this.field, required this.value});

  static const _maxVisibleChips = 3;
  // Below this width threshold, fall back to plain text.
  static const _chipFallbackWidth = 200.0;

  final CustomField field;
  final CustomFieldValue value;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = field.typeConfig;
    if (config is! ChoiceConfig) {
      return Text(value.value);
    }

    final parsed = choiceFieldDefinition.valueParser(value.value);
    final choiceValue = parsed is ChoiceFieldValue
        ? parsed
        : const ChoiceFieldValue();

    final resolvedLabels = <String>[];
    final resolvedOptions = <ChoiceOption>[];

    for (final option in _selectedOptionsInSettingsOrder(config, choiceValue)) {
      resolvedLabels.add(option.label);
      resolvedOptions.add(option);
    }
    final hasOther = choiceValue.other != null && choiceValue.other!.isNotEmpty;
    if (hasOther) {
      resolvedLabels.add(l10n.customFieldChoiceOtherPrefix(choiceValue.other!));
    }

    if (resolvedLabels.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _chipFallbackWidth) {
          // Narrow context: plain text.
          final overflow = resolvedLabels.length > _maxVisibleChips
              ? '+${resolvedLabels.length - _maxVisibleChips} more'
              : null;
          final visibleLabels = resolvedLabels
              .take(_maxVisibleChips)
              .join(', ');
          final fullText = overflow != null
              ? '$visibleLabels, $overflow'
              : visibleLabels;
          return Text(fullText, overflow: TextOverflow.ellipsis);
        }

        final visibleCount = resolvedLabels.length.clamp(0, _maxVisibleChips);
        final overflow = resolvedLabels.length > _maxVisibleChips
            ? resolvedLabels.length - _maxVisibleChips
            : 0;

        final chips = <Widget>[
          for (var i = 0; i < visibleCount; i++)
            // Fix 2: branch on whether this index is an option or the Other text.
            if (i < resolvedOptions.length)
              // Fix 3: Semantics for compact option chips.
              Semantics(
                button: false,
                label:
                    '${field.name}, ${resolvedLabels[i]}, '
                    '${l10n.customFieldChoiceSelectedSuffix}'
                    '${resolvedOptions[i].isDeleted ? ', ${l10n.customFieldChoiceRemovedSuffix}' : ''}',
                excludeSemantics: true,
                child: _buildMiniChip(context, resolvedOptions[i]),
              )
            else
              // Other pill — now reachable.
              // Fix 3: Semantics for compact Other chip.
              Semantics(
                button: false,
                label: '${field.name}, ${resolvedLabels[i]}',
                excludeSemantics: true,
                child: PrismChip(
                  label: resolvedLabels[i],
                  selected: true,
                  onTap: null,
                ),
              ),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '+$overflow more',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ];

        return Wrap(spacing: 4, runSpacing: 2, children: chips);
      },
    );
  }

  Widget _buildMiniChip(BuildContext context, ChoiceOption option) {
    final color = option.colorHex != null
        ? AppColors.fromHex(option.colorHex!)
        : null;
    Widget chip = PrismChip(
      label: option.label,
      selected: true,
      tintColor: color,
      onTap: null,
    );
    if (option.isDeleted) {
      chip = Opacity(opacity: 0.45, child: chip);
    }
    return chip;
  }
}
