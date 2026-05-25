import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/custom_fields/choice_option_palette.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

/// Modal sheet for creating or editing a custom field definition.
///
/// When [field] is provided the sheet operates in edit mode. Textual fields
/// (short text ↔ long text) can be switched between each other; color and
/// date types remain immutable once created because their storage shapes
/// differ.
///
/// When [parentFieldId] is set, the created field is nested under that group.
/// Has no effect in edit mode.
///
/// Use via [PrismSheet.showFullScreen].
class CreateEditFieldSheet extends ConsumerStatefulWidget {
  const CreateEditFieldSheet({
    super.key,
    this.field,
    this.parentFieldId,
    required this.scrollController,
  });

  final CustomField? field;

  /// When non-null, the new field will be created as a child of this group.
  /// Ignored in edit mode.
  final String? parentFieldId;

  final ScrollController scrollController;

  bool get isEditing => field != null;

  @override
  ConsumerState<CreateEditFieldSheet> createState() =>
      _CreateEditFieldSheetState();
}

class _CreateEditFieldSheetState extends ConsumerState<CreateEditFieldSheet> {
  static const _uuid = Uuid();

  static const _fieldTypeOptions = [
    CustomFieldType.text,
    CustomFieldType.longText,
    CustomFieldType.color,
    CustomFieldType.date,
    CustomFieldType.choice,
  ];

  late final TextEditingController _nameController;
  CustomFieldType _selectedType = CustomFieldType.text;
  DatePrecision _selectedPrecision = DatePrecision.full;

  // Choice config state — mutable copy of options for the UI.
  List<ChoiceOption> _choiceOptions = [];
  bool _choiceAllowsMultiple = false;
  bool _choiceAllowsOther = false;

  // Per-option text controllers, keyed by option ID.
  final Map<String, TextEditingController> _optionControllers = {};
  // Per-option focus nodes, keyed by option ID.
  final Map<String, FocusNode> _optionFocusNodes = {};

  bool _saving = false;
  late final String _initialName;
  late final CustomFieldType _initialType;
  late final DatePrecision _initialPrecision;

  bool get _isDirty =>
      _nameController.text != _initialName ||
      _selectedType != _initialType ||
      _selectedPrecision != _initialPrecision ||
      (_selectedType == CustomFieldType.choice && _isChoiceDirty);

  bool get _isChoiceDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! ChoiceConfig) {
      return _choiceOptions.isNotEmpty ||
          _choiceAllowsMultiple ||
          _choiceAllowsOther;
    }
    if (existingConfig.allowsMultiple != _choiceAllowsMultiple) return true;
    if (existingConfig.allowsOther != _choiceAllowsOther) return true;
    if (existingConfig.options.length != _choiceOptions.length) return true;
    for (var i = 0; i < _choiceOptions.length; i++) {
      final a = existingConfig.options[i];
      final b = _choiceOptions[i];
      if (a.id != b.id ||
          a.label != b.label ||
          a.colorHex != b.colorHex ||
          a.sortOrder != b.sortOrder ||
          a.isDeleted != b.isDeleted) {
        return true;
      }
    }
    return false;
  }

  /// Live options visible in the UI (non-deleted).
  List<ChoiceOption> get _visibleOptions =>
      _choiceOptions.where((o) => !o.isDeleted).toList();

  @override
  void initState() {
    super.initState();
    final f = widget.field;
    _nameController = TextEditingController(text: f?.name ?? '');
    if (f != null) {
      _selectedType = f.fieldType;
      _selectedPrecision = f.datePrecision ?? DatePrecision.full;
      // Hydrate choice config from existing field.
      if (f.typeConfig is ChoiceConfig) {
        final config = f.typeConfig! as ChoiceConfig;
        _choiceOptions = List.of(config.options);
        _choiceAllowsMultiple = config.allowsMultiple;
        _choiceAllowsOther = config.allowsOther;
      }
    }
    // Build controllers/focus nodes for any pre-existing options.
    for (final option in _choiceOptions) {
      _optionControllers[option.id] =
          TextEditingController(text: option.label);
      _optionFocusNodes[option.id] = FocusNode();
    }
    _initialName = _nameController.text;
    _initialType = _selectedType;
    _initialPrecision = _selectedPrecision;
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _optionControllers.values) {
      c.dispose();
    }
    for (final fn in _optionFocusNodes.values) {
      fn.dispose();
    }
    super.dispose();
  }

  // ── Choice helpers ──────────────────────────────────────────────────

  /// Add a new option with auto-color and request focus.
  void _addOption() {
    final id = _uuid.v4();
    final color = nextChoicePaletteColor(_visibleOptions.length);
    final maxSortOrder = _choiceOptions.isEmpty
        ? 0
        : _choiceOptions.map((o) => o.sortOrder).reduce((a, b) => a > b ? a : b);
    final newOption = ChoiceOption(
      id: id,
      label: '',
      colorHex: color,
      sortOrder: maxSortOrder + 1,
      isDeleted: false,
    );
    final controller = TextEditingController();
    final focusNode = FocusNode();
    setState(() {
      _choiceOptions = [..._choiceOptions, newOption];
      _optionControllers[id] = controller;
      _optionFocusNodes[id] = focusNode;
    });
    // Focus the new field after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusNode.requestFocus();
    });
  }

  /// Soft-delete an option by ID.
  void _removeOption(String id) {
    setState(() {
      _choiceOptions = _choiceOptions.map((o) {
        if (o.id == id) return o.copyWith(isDeleted: true);
        return o;
      }).toList();
    });
  }

  /// Cycle the color of an option.
  void _cycleOptionColor(String id) {
    setState(() {
      _choiceOptions = _choiceOptions.map((o) {
        if (o.id == id) {
          return o.copyWith(colorHex: cycleChoicePaletteColor(o.colorHex));
        }
        return o;
      }).toList();
    });
    Haptics.selection();
  }

  /// Update an option's label from its text controller.
  void _syncOptionLabel(String id) {
    final text = _optionControllers[id]?.text ?? '';
    setState(() {
      _choiceOptions = _choiceOptions.map((o) {
        if (o.id == id) return o.copyWith(label: text);
        return o;
      }).toList();
    });
  }

  /// Reorder handler from [ReorderableListView].
  void _reorderOptions(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final visible = _visibleOptions;
    final moved = visible[oldIndex];
    final reordered = List<ChoiceOption>.from(visible)
      ..removeAt(oldIndex)
      ..insert(newIndex, moved);
    // Assign new sortOrder values.
    final updatedVisible = reordered.asMap().entries.map((e) {
      return e.value.copyWith(sortOrder: e.key);
    }).toList();
    // Rebuild full options list: replace visible items, keep deleted items at end.
    final deleted = _choiceOptions.where((o) => o.isDeleted).toList();
    setState(() {
      _choiceOptions = [...updatedVisible, ...deleted];
    });
  }

  /// Build the current [ChoiceConfig] from UI state.
  ChoiceConfig _buildChoiceConfig() {
    // Sync all labels from controllers.
    final synced = _choiceOptions.map((o) {
      final label = _optionControllers[o.id]?.text ?? o.label;
      return o.copyWith(label: label);
    }).toList();
    return ChoiceConfig(
      options: synced,
      allowsMultiple: _choiceAllowsMultiple,
      allowsOther: _choiceAllowsOther,
    );
  }

  // ── Duplicate detection ─────────────────────────────────────────────

  /// Returns IDs of options whose labels are duplicated (case-insensitive).
  Set<String> _duplicateOptionIds() {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final option in _visibleOptions) {
      final normalized =
          (_optionControllers[option.id]?.text ?? option.label)
              .trim()
              .toLowerCase();
      if (normalized.isEmpty) continue;
      if (!seen.add(normalized)) {
        // Mark all options with this label.
        for (final o in _visibleOptions) {
          final l =
              (_optionControllers[o.id]?.text ?? o.label).trim().toLowerCase();
          if (l == normalized) duplicates.add(o.id);
        }
      }
    }
    return duplicates;
  }

  // ── Save ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    try {
      final notifier = ref.read(customFieldNotifierProvider.notifier);

      if (widget.isEditing) {
        final updated = widget.field!.copyWith(
          name: name,
          fieldType: _selectedType,
          datePrecision: _selectedType == CustomFieldType.date
              ? _selectedPrecision
              : null,
          typeConfig: _selectedType == CustomFieldType.choice
              ? _buildChoiceConfig()
              : null,
        );
        await notifier.updateField(updated);
      } else {
        await notifier.createField(
          name: name,
          fieldType: _selectedType,
          datePrecision: _selectedType == CustomFieldType.date
              ? _selectedPrecision
              : null,
          fieldTypeId: _selectedType == CustomFieldType.choice ? 'choice' : null,
          typeConfig: _selectedType == CustomFieldType.choice
              ? _buildChoiceConfig()
              : null,
          parentFieldId: widget.parentFieldId,
        );
      }

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.settingsCreateEditFieldSaveError(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _nameController.text.trim().isNotEmpty;

    return ListenableBuilder(
      listenable: _nameController,
      builder: (context, _) => UnsavedChangesGuard<bool>(
        hasUnsavedChanges: _isDirty,
        child: SafeArea(
          child: Column(
            children: [
              PrismSheetTopBar(
                title: widget.isEditing
                    ? context.l10n.settingsCreateEditFieldEditTitle
                    : widget.parentFieldId != null
                        ? context.l10n.customFieldGroupNewChildTitle
                        : context.l10n.settingsCreateEditFieldNewTitle,
                trailing: _saving
                    ? SizedBox(
                        width: PrismTokens.topBarActionSize,
                        height: PrismTokens.topBarActionSize,
                        child: Center(
                          child: PrismSpinner(
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                      )
                    : PrismGlassIconButton(
                        icon: AppIcons.check,
                        tooltip: context.l10n.save,
                        size: PrismTokens.topBarActionSize,
                        onPressed: canSave ? _save : null,
                      ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrismTokens.pageHorizontalPadding,
                  ),
                  children: [
                    PrismTextField(
                      controller: _nameController,
                      labelText: context.l10n.settingsCreateEditFieldNameLabel,
                      hintText: context.l10n.settingsCreateEditFieldNameHint,
                      autofocus: !widget.isEditing,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 24),

                    // Type picker
                    Text(
                      context.l10n.settingsCreateEditFieldTypeHeading,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (widget.isEditing) ...[
                      // In edit mode, allow switching between textual types
                      // (short text ↔ long text) since both store plain
                      // markdown strings. Color, date, and choice have
                      // different storage shapes and remain locked.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in _fieldTypeOptions)
                            PrismChip(
                              label: type.localizedLabel(context.l10n),
                              selected: type == _selectedType,
                              onTap: (_selectedType.isTextual && type.isTextual)
                                  ? () {
                                      setState(() => _selectedType = type);
                                      Haptics.selection();
                                    }
                                  : null,
                              avatar: Icon(_iconForType(type), size: 16),
                            ),
                        ],
                      ),
                      if (!_selectedType.isTextual) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.settingsCreateEditFieldTypeImmutable,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ] else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in _fieldTypeOptions)
                            PrismChip(
                              label: type.localizedLabel(context.l10n),
                              selected: type == _selectedType,
                              onTap: () {
                                setState(() => _selectedType = type);
                                Haptics.selection();
                              },
                              avatar: Icon(_iconForType(type), size: 16),
                            ),
                        ],
                      ),
                    ],

                    // Date precision picker
                    if (_selectedType == CustomFieldType.date) ...[
                      const SizedBox(height: 24),
                      Text(
                        context
                            .l10n
                            .settingsCreateEditFieldDatePrecisionHeading,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final precision in DatePrecision.values)
                            PrismChip(
                              label: precision.localizedLabel(context.l10n),
                              selected: precision == _selectedPrecision,
                              onTap: () {
                                setState(() => _selectedPrecision = precision);
                                Haptics.selection();
                              },
                            ),
                        ],
                      ),
                    ],

                    // Choice config
                    if (_selectedType == CustomFieldType.choice) ...[
                      const SizedBox(height: 24),
                      _ChoiceConfigSection(
                        visibleOptions: _visibleOptions,
                        allOptions: _choiceOptions,
                        optionControllers: _optionControllers,
                        optionFocusNodes: _optionFocusNodes,
                        allowsMultiple: _choiceAllowsMultiple,
                        allowsOther: _choiceAllowsOther,
                        duplicateIds: _duplicateOptionIds(),
                        onAddOption: _addOption,
                        onRemoveOption: _removeOption,
                        onCycleColor: _cycleOptionColor,
                        onLabelChanged: _syncOptionLabel,
                        onReorder: _reorderOptions,
                        onAllowsMultipleChanged: (v) =>
                            setState(() => _choiceAllowsMultiple = v),
                        onAllowsOtherChanged: (v) =>
                            setState(() => _choiceAllowsOther = v),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(CustomFieldType type) => switch (type) {
    CustomFieldType.text => AppIcons.textFields,
    CustomFieldType.longText => AppIcons.notes,
    CustomFieldType.color => AppIcons.palette,
    CustomFieldType.date => AppIcons.calendarToday,
    CustomFieldType.choice => AppIcons.checkBoxOutlined,
  };
}

// ── Choice config section ───────────────────────────────────────────────────

class _ChoiceConfigSection extends StatelessWidget {
  const _ChoiceConfigSection({
    required this.visibleOptions,
    required this.allOptions,
    required this.optionControllers,
    required this.optionFocusNodes,
    required this.allowsMultiple,
    required this.allowsOther,
    required this.duplicateIds,
    required this.onAddOption,
    required this.onRemoveOption,
    required this.onCycleColor,
    required this.onLabelChanged,
    required this.onReorder,
    required this.onAllowsMultipleChanged,
    required this.onAllowsOtherChanged,
  });

  final List<ChoiceOption> visibleOptions;
  final List<ChoiceOption> allOptions;
  final Map<String, TextEditingController> optionControllers;
  final Map<String, FocusNode> optionFocusNodes;
  final bool allowsMultiple;
  final bool allowsOther;
  final Set<String> duplicateIds;
  final VoidCallback onAddOption;
  final ValueChanged<String> onRemoveOption;
  final ValueChanged<String> onCycleColor;
  final ValueChanged<String> onLabelChanged;
  final void Function(int, int) onReorder;
  final ValueChanged<bool> onAllowsMultipleChanged;
  final ValueChanged<bool> onAllowsOtherChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.customFieldChoiceOptionsHeading,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        // Options list — reorderable.
        if (visibleOptions.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleOptions.length,
            buildDefaultDragHandles: false,
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final option = visibleOptions[index];
              final isDuplicate = duplicateIds.contains(option.id);
              return _ChoiceOptionRow(
                key: ValueKey(option.id),
                index: index,
                option: option,
                controller: optionControllers[option.id]!,
                focusNode: optionFocusNodes[option.id]!,
                isDuplicate: isDuplicate,
                onRemove: () => onRemoveOption(option.id),
                onCycleColor: () => onCycleColor(option.id),
                onLabelChanged: () => onLabelChanged(option.id),
              );
            },
          ),

        // Add option button.
        TextButton.icon(
          onPressed: onAddOption,
          icon: Icon(AppIcons.addCircle, size: 18),
          label: Text(l10n.customFieldChoiceAddOption),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),

        // Allow multiple toggle.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.customFieldChoiceAllowMultipleLabel,
            style: theme.textTheme.bodyMedium,
          ),
          value: allowsMultiple,
          onChanged: onAllowsMultipleChanged,
        ),

        // Allow other toggle.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.customFieldChoiceAllowOtherLabel,
            style: theme.textTheme.bodyMedium,
          ),
          value: allowsOther,
          onChanged: onAllowsOtherChanged,
        ),
      ],
    );
  }
}

// ── Single option row ───────────────────────────────────────────────────────

class _ChoiceOptionRow extends StatelessWidget {
  const _ChoiceOptionRow({
    super.key,
    required this.index,
    required this.option,
    required this.controller,
    required this.focusNode,
    required this.isDuplicate,
    required this.onRemove,
    required this.onCycleColor,
    required this.onLabelChanged,
  });

  final int index;
  final ChoiceOption option;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isDuplicate;
  final VoidCallback onRemove;
  final VoidCallback onCycleColor;
  final VoidCallback onLabelChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    Color? swatchColor;
    try {
      if (option.colorHex != null) {
        swatchColor = AppColors.fromHex(option.colorHex!);
      }
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Drag handle.
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: l10n.customFieldChoiceReorderHandleTooltip,
              child: Icon(
                AppIcons.dragHandle,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Color swatch button.
          Tooltip(
            message: l10n.customFieldChoiceColorCycleTooltip,
            child: GestureDetector(
              onTap: onCycleColor,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: swatchColor ?? theme.colorScheme.primary,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Label text field.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PrismTextField(
                  controller: controller,
                  focusNode: focusNode,
                  hintText: l10n.customFieldChoiceOptionPlaceholder,
                  fieldStyle: PrismTextFieldStyle.borderless,
                  onChanged: (_) => onLabelChanged(),
                  textCapitalization: TextCapitalization.sentences,
                ),
                if (isDuplicate) ...[
                  const SizedBox(height: 2),
                  _DuplicateWarningChip(
                    label: l10n.customFieldChoiceDuplicateLabel,
                  ),
                ],
              ],
            ),
          ),

          // Remove button.
          IconButton(
            icon: Icon(AppIcons.close, size: 18),
            tooltip: l10n.customFieldChoiceRemoveOptionTooltip,
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ── Duplicate warning chip ──────────────────────────────────────────────────

class _DuplicateWarningChip extends StatelessWidget {
  const _DuplicateWarningChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: errorColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
