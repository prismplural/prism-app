import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/choice_option_palette.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
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

class _ChoiceEditorWidgetState extends ConsumerState<_ChoiceEditorWidget> {
  late ChoiceFieldValue _currentValue;
  late TextEditingController _otherController;
  // Map from option ID → GlobalKey<BlurPopupAnchorState> for long-press menus.
  final Map<String, GlobalKey<BlurPopupAnchorState>> _popupKeys = {};

  @override
  void initState() {
    super.initState();
    _currentValue = _parseValue(widget.existingValue?.value);
    _otherController = TextEditingController(text: _currentValue.other ?? '');
  }

  @override
  void didUpdateWidget(covariant _ChoiceEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRaw = widget.existingValue?.value ?? '';
    final oldRaw = oldWidget.existingValue?.value ?? '';
    if (newRaw != oldRaw) {
      _currentValue = _parseValue(widget.existingValue?.value);
      final newOther = _currentValue.other ?? '';
      if (_otherController.text != newOther) {
        _otherController.text = newOther;
      }
    }
  }

  @override
  void dispose() {
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

  Future<void> _save(ChoiceFieldValue newValue) async {
    setState(() => _currentValue = newValue);

    final encoded = choiceFieldDefinition.valueEncoder(newValue);
    final notifier = ref.read(customFieldValueNotifierProvider.notifier);

    if (encoded.isEmpty) {
      // Empty selection + no other text → delete the stored value.
      final existingId = widget.existingValue?.id;
      if (existingId != null) {
        await notifier.deleteValue(existingId);
      }
    } else {
      await notifier.setValue(
        customFieldId: widget.field.id,
        memberId: widget.memberId,
        value: encoded,
        existingId: widget.existingValue?.id,
      );
    }
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
    unawaited(_save(_currentValue.copyWith(optionIds: selected)));
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
    final controller = TextEditingController(text: option.label);
    final confirmed = await PrismDialog.show<bool>(
      context: context,
      title: 'Edit option label',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
      builder: (ctx) => PrismTextField(
        controller: controller,
        autofocus: true,
        hintText: 'Option label',
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
    await ref
        .read(customFieldNotifierProvider.notifier)
        .writeTypedConfig(widget.field.id, updatedConfig);
  }

  Future<void> _cycleOptionColor(ChoiceConfig config, ChoiceOption option) async {
    final newColor = cycleChoicePaletteColor(option.colorHex);
    final updatedOptions = [
      for (final o in config.options)
        if (o.id == option.id) o.copyWith(colorHex: newColor) else o,
    ];
    final updatedConfig = config.copyWith(options: updatedOptions);
    await ref
        .read(customFieldNotifierProvider.notifier)
        .writeTypedConfig(widget.field.id, updatedConfig);
  }

  Future<void> _deleteOption(
    BuildContext context,
    ChoiceConfig config,
    ChoiceOption option,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete option',
      message:
          '"${option.label}" will be soft-deleted. Members who selected it '
          'will still see it (faded) but can no longer choose it. '
          'This affects all members.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: AppIcons.warningAmber,
    );
    if (!confirmed || !mounted) return;

    final updatedOptions = [
      for (final o in config.options)
        if (o.id == option.id) o.copyWith(isDeleted: true) else o,
    ];
    final updatedConfig = config.copyWith(options: updatedOptions);
    await ref
        .read(customFieldNotifierProvider.notifier)
        .writeTypedConfig(widget.field.id, updatedConfig);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config();
    if (config == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final allowsMultiple = config.allowsMultiple;
    final allowsOther = config.allowsOther;
    final isOtherSelected = _currentValue.optionIds.contains('__other__') ||
        (_currentValue.other?.isNotEmpty ?? false);

    // Separate active vs deleted options.
    final activeOptions = config.options.where((o) => !o.isDeleted).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    // Deleted options that are still selected for this member.
    final deletedButSelected = config.options.where(
      (o) => o.isDeleted && _currentValue.optionIds.contains(o.id),
    ).toList();

    final chips = <Widget>[
      for (final option in activeOptions)
        _buildOptionChip(context, theme, config, option, allowsMultiple),
      for (final option in deletedButSelected)
        _buildDeletedOptionChip(context, theme, option, allowsMultiple),
      if (allowsOther)
        _buildOtherChip(context, theme, isOtherSelected),
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
          PrismTextField(
            controller: _otherController,
            hintText: 'Specify…',
            autofocus: true,
            onChanged: (text) {
              unawaited(
                _save(_currentValue.copyWith(other: text.isEmpty ? null : text)),
              );
            },
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
    final isSelected = _currentValue.optionIds.contains(option.id);
    final color =
        option.colorHex != null ? AppColors.fromHex(option.colorHex!) : null;

    final popupKey = _popupKeyFor(option.id);

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
              title: const Text('Edit label'),
              onTap: () {
                close();
                unawaited(_editOptionLabel(context, config, option));
              },
            ),
          1 => PrismListRow(
              dense: true,
              leading: Icon(AppIcons.palette, size: 20),
              title: const Text('Change color'),
              onTap: () {
                close();
                unawaited(_cycleOptionColor(config, option));
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
              title: const Text('Delete'),
              onTap: () {
                close();
                unawaited(_deleteOption(context, config, option));
              },
            ),
        };
      },
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
    );
  }

  Widget _buildDeletedOptionChip(
    BuildContext context,
    ThemeData theme,
    ChoiceOption option,
    bool allowsMultiple,
  ) {
    final isSelected = _currentValue.optionIds.contains(option.id);
    return Tooltip(
      message: '(removed)',
      child: Opacity(
        opacity: 0.45,
        child: PrismChip(
          label: option.label,
          selected: isSelected,
          onTap: () => _toggleOption(option.id, allowsMultiple),
        ),
      ),
    );
  }

  Widget _buildOtherChip(
    BuildContext context,
    ThemeData theme,
    bool isSelected,
  ) {
    return PrismChip(
      label: 'Other…',
      selected: isSelected,
      onTap: () {
        if (isSelected) {
          // Deselect: clear other text.
          unawaited(_save(_currentValue.copyWith(other: null)));
          _otherController.clear();
        } else {
          // Select: mark as other-selected with empty text for now.
          unawaited(_save(_currentValue.copyWith(other: '')));
        }
      },
    );
  }
}

// ─── Display ──────────────────────────────────────────────────────────────────

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
    final config = field.typeConfig;
    if (config is! ChoiceConfig) {
      return Text(value.value);
    }

    final parsed = choiceFieldDefinition.valueParser(value.value);
    final choiceValue =
        parsed is ChoiceFieldValue ? parsed : const ChoiceFieldValue();

    if (choiceValue.optionIds.isEmpty &&
        (choiceValue.other == null || choiceValue.other!.isEmpty)) {
      return const SizedBox.shrink();
    }

    // Build a lookup map for fast access.
    final optionMap = {for (final o in config.options) o.id: o};

    final chips = <Widget>[];

    for (final id in choiceValue.optionIds.toList()..sort()) {
      final option = optionMap[id];
      if (option == null) continue;
      final color = option.colorHex != null
          ? AppColors.fromHex(option.colorHex!)
          : null;
      final isDeleted = option.isDeleted;

      Widget chip = PrismChip(
        label: option.label,
        selected: true,
        tintColor: color,
        onTap: null,
      );
      if (isDeleted) {
        chip = Tooltip(
          message: '(removed)',
          child: Opacity(opacity: 0.45, child: chip),
        );
      }
      chips.add(chip);
    }

    if (choiceValue.other != null && choiceValue.other!.isNotEmpty) {
      chips.add(
        PrismChip(
          label: 'Other: ${choiceValue.other}',
          selected: true,
          onTap: null,
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
    final config = field.typeConfig;
    if (config is! ChoiceConfig) {
      return Text(value.value);
    }

    final parsed = choiceFieldDefinition.valueParser(value.value);
    final choiceValue =
        parsed is ChoiceFieldValue ? parsed : const ChoiceFieldValue();

    // Build resolved label list (preserving a deterministic order).
    final optionMap = {for (final o in config.options) o.id: o};
    final resolvedLabels = <String>[];
    final resolvedOptions = <ChoiceOption>[];

    for (final id in choiceValue.optionIds.toList()..sort()) {
      final option = optionMap[id];
      if (option != null) {
        resolvedLabels.add(option.label);
        resolvedOptions.add(option);
      }
    }
    if (choiceValue.other != null && choiceValue.other!.isNotEmpty) {
      resolvedLabels.add('Other: ${choiceValue.other}');
    }

    if (resolvedLabels.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _chipFallbackWidth) {
          // Narrow context: plain text.
          final overflow = resolvedLabels.length > _maxVisibleChips
              ? '+${resolvedLabels.length - _maxVisibleChips} more'
              : null;
          final visibleLabels = resolvedLabels.take(_maxVisibleChips).join(', ');
          final fullText = overflow != null
              ? '$visibleLabels, $overflow'
              : visibleLabels;
          return Text(fullText, overflow: TextOverflow.ellipsis);
        }

        // Chip row: up to _maxVisibleChips, then "+N more" label.
        final visibleCount = resolvedOptions.length.clamp(0, _maxVisibleChips);
        final overflow =
            resolvedLabels.length > _maxVisibleChips
                ? resolvedLabels.length - _maxVisibleChips
                : 0;

        final chips = <Widget>[
          for (var i = 0; i < visibleCount; i++) ...[
            if (i < resolvedOptions.length)
              _buildMiniChip(context, resolvedOptions[i])
            else
              // "Other" pill — only appears at the end.
              PrismChip(
                label: resolvedLabels[i],
                selected: true,
                onTap: null,
              ),
          ],
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
