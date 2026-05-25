import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/custom_fields/choice_option_palette.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/custom_fields/scale_emoji_palette.dart';
import 'package:prism_plurality/domain/custom_fields/slider_gradient_presets.dart';
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

  late final TextEditingController _nameController;

  /// Canonical type identifier — the stable string ID from the registry.
  /// All type-conditional logic branches on this, not on [CustomFieldType].
  /// Defaults to 'text'; never 'group' when adding a child field (enforced
  /// in [initState]).
  late String _selectedTypeId;

  DatePrecision _selectedPrecision = DatePrecision.full;

  // Choice config state — mutable copy of options for the UI.
  List<ChoiceOption> _choiceOptions = [];
  bool _choiceAllowsMultiple = false;
  bool _choiceAllowsOther = false;

  // Per-option text controllers, keyed by option ID.
  final Map<String, TextEditingController> _optionControllers = {};
  // Per-option focus nodes, keyed by option ID.
  final Map<String, FocusNode> _optionFocusNodes = {};

  // Scale config state — mutable copy for the UI.
  String _scaleEmoji = '⭐';
  int _scaleSteps = 5;
  // Whether the "Advanced: any emoji" input is visible.
  bool _scaleShowCustomEmojiInput = false;
  late final TextEditingController _scaleCustomEmojiController;

  // Slider config state — mutable copy for the UI.
  SliderMode _sliderMode = SliderMode.labeled;
  late final TextEditingController _sliderLeftLabelController;
  late final TextEditingController _sliderRightLabelController;
  late final TextEditingController _sliderCenterLabelController;
  String? _sliderGradientPresetId = 'femme-masc';
  String? _sliderLeftColorHex;
  String? _sliderRightColorHex;
  String? _sliderCenterColorHex;
  bool _sliderSnapToPositions = true;
  bool _sliderShowAdvancedColors = false;
  late final TextEditingController _sliderMinController;
  late final TextEditingController _sliderMaxController;
  late final TextEditingController _sliderStepController;
  late final TextEditingController _sliderUnitController;
  bool _sliderShowTicks = false;

  bool _saving = false;
  late final String _initialName;
  late final String _initialTypeId;
  late final DatePrecision _initialPrecision;

  bool get _isDirty =>
      _nameController.text != _initialName ||
      _selectedTypeId != _initialTypeId ||
      _selectedPrecision != _initialPrecision ||
      (_selectedTypeId == 'choice' && _isChoiceDirty) ||
      (_selectedTypeId == 'scale' && _isScaleDirty) ||
      (_selectedTypeId == 'slider' && _isSliderDirty);

  bool get _isScaleDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! ScaleConfig || _selectedTypeId != 'scale') {
      return _scaleEmoji != '⭐' || _scaleSteps != 5;
    }
    return existingConfig.emoji != _scaleEmoji ||
        existingConfig.steps != _scaleSteps;
  }

  bool get _isSliderDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! SliderConfig || _selectedTypeId != 'slider') {
      return _sliderGradientPresetId != 'femme-masc' ||
          _sliderLeftLabelController.text.isNotEmpty ||
          _sliderRightLabelController.text.isNotEmpty ||
          _sliderCenterLabelController.text.isNotEmpty ||
          !_sliderSnapToPositions ||
          _sliderMinController.text != '0' ||
          _sliderMaxController.text != '10' ||
          _sliderStepController.text != '1' ||
          _sliderUnitController.text.isNotEmpty ||
          _sliderShowTicks;
    }
    String? toNullable(String s) => s.trim().isEmpty ? null : s.trim();
    return existingConfig.mode != _sliderMode ||
        existingConfig.leftLabel != toNullable(_sliderLeftLabelController.text) ||
        existingConfig.rightLabel != toNullable(_sliderRightLabelController.text) ||
        existingConfig.centerLabel != toNullable(_sliderCenterLabelController.text) ||
        existingConfig.gradientPresetId != _sliderGradientPresetId ||
        existingConfig.snapToPositions != _sliderSnapToPositions ||
        existingConfig.min != double.tryParse(_sliderMinController.text.trim()) ||
        existingConfig.max != double.tryParse(_sliderMaxController.text.trim()) ||
        existingConfig.step != double.tryParse(_sliderStepController.text.trim()) ||
        existingConfig.unit != toNullable(_sliderUnitController.text) ||
        existingConfig.showTicks != _sliderShowTicks;
  }

  bool get _isChoiceDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! ChoiceConfig || _selectedTypeId != 'choice') {
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
    _scaleCustomEmojiController = TextEditingController();
    _sliderLeftLabelController = TextEditingController();
    _sliderRightLabelController = TextEditingController();
    _sliderCenterLabelController = TextEditingController();
    _sliderMinController = TextEditingController(text: '0');
    _sliderMaxController = TextEditingController(text: '10');
    _sliderStepController = TextEditingController(text: '1');
    _sliderUnitController = TextEditingController();
    if (f != null) {
      // Derive canonical type ID. Prefer fieldTypeId (registry-first); fall
      // back to looking up the legacy enum's int in the registry.
      _selectedTypeId = f.fieldTypeId ??
          customFieldTypeRegistry
              .lookupByLegacyInt(f.fieldType.index)
              ?.id ??
          'text';
      _selectedPrecision = f.datePrecision ?? DatePrecision.full;
      // Hydrate choice config from existing field.
      if (f.typeConfig is ChoiceConfig) {
        final config = f.typeConfig! as ChoiceConfig;
        _choiceOptions = List.of(config.options);
        _choiceAllowsMultiple = config.allowsMultiple;
        _choiceAllowsOther = config.allowsOther;
      }
      // Hydrate scale config from existing field.
      if (f.typeConfig is ScaleConfig) {
        final config = f.typeConfig! as ScaleConfig;
        _scaleEmoji = config.emoji;
        _scaleSteps = config.steps;
      }
      // Hydrate slider config from existing field.
      if (f.typeConfig is SliderConfig) {
        final config = f.typeConfig! as SliderConfig;
        _sliderMode = config.mode;
        _sliderLeftLabelController.text = config.leftLabel ?? '';
        _sliderRightLabelController.text = config.rightLabel ?? '';
        _sliderCenterLabelController.text = config.centerLabel ?? '';
        _sliderGradientPresetId = config.gradientPresetId;
        _sliderLeftColorHex = config.leftColorHex;
        _sliderRightColorHex = config.rightColorHex;
        _sliderCenterColorHex = config.centerColorHex;
        _sliderSnapToPositions = config.snapToPositions;
        _sliderMinController.text = config.min?.toString() ?? '0';
        _sliderMaxController.text = config.max?.toString() ?? '10';
        _sliderStepController.text = config.step?.toString() ?? '1';
        _sliderUnitController.text = config.unit ?? '';
        _sliderShowTicks = config.showTicks;
      }
    } else {
      // New field: default to 'text'. When adding a child to a group,
      // force 'text' (never 'group') to prevent nested groups.
      _selectedTypeId = 'text';
    }
    // Build controllers/focus nodes for any pre-existing options.
    for (final option in _choiceOptions) {
      _optionControllers[option.id] =
          TextEditingController(text: option.label);
      _optionFocusNodes[option.id] = FocusNode();
    }
    _initialName = _nameController.text;
    _initialTypeId = _selectedTypeId;
    _initialPrecision = _selectedPrecision;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scaleCustomEmojiController.dispose();
    _sliderLeftLabelController.dispose();
    _sliderRightLabelController.dispose();
    _sliderCenterLabelController.dispose();
    _sliderMinController.dispose();
    _sliderMaxController.dispose();
    _sliderStepController.dispose();
    _sliderUnitController.dispose();
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

  // ── Scale helpers ───────────────────────────────────────────────────

  /// Build the current [ScaleConfig] from UI state.
  ScaleConfig _buildScaleConfig() {
    return ScaleConfig(emoji: _scaleEmoji, steps: _scaleSteps);
  }

  // ── Slider helpers ──────────────────────────────────────────────────

  String? _sliderTextToNull(TextEditingController c) {
    final s = c.text.trim();
    return s.isEmpty ? null : s;
  }

  /// Build the current [SliderConfig] from UI state.
  SliderConfig _buildSliderConfig() {
    if (_sliderMode == SliderMode.labeled) {
      return SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: _sliderTextToNull(_sliderLeftLabelController),
        rightLabel: _sliderTextToNull(_sliderRightLabelController),
        centerLabel: _sliderTextToNull(_sliderCenterLabelController),
        gradientPresetId: _sliderGradientPresetId,
        leftColorHex: _sliderLeftColorHex,
        rightColorHex: _sliderRightColorHex,
        centerColorHex: _sliderCenterColorHex,
        snapToPositions: _sliderSnapToPositions,
      );
    } else {
      return SliderConfig(
        mode: SliderMode.numeric,
        min: double.tryParse(_sliderMinController.text.trim()) ?? 0,
        max: double.tryParse(_sliderMaxController.text.trim()) ?? 10,
        step: double.tryParse(_sliderStepController.text.trim()) ?? 1,
        unit: _sliderTextToNull(_sliderUnitController),
        showTicks: _sliderShowTicks,
      );
    }
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

      // Derive the legacy enum value for back-compat storage.
      // Registry-only types (e.g. 'group', legacyIntValue=5) have an int
      // that is OUT OF RANGE for CustomFieldType.values (which only has 5
      // entries, indices 0-4). Guard with a range check and fall back to
      // CustomFieldType.text for any out-of-range or missing int.
      final def = customFieldTypeRegistry.lookupById(_selectedTypeId);
      final legacyInt = def?.legacyIntValue;
      final legacyFieldType =
          (legacyInt != null && legacyInt < CustomFieldType.values.length)
              ? CustomFieldType.values[legacyInt]
              : CustomFieldType.text;

      // Derive the typeConfig for types that need it.
      final CustomFieldTypeConfig? typeConfig = switch (_selectedTypeId) {
        'choice' => _buildChoiceConfig(),
        'scale' => _buildScaleConfig(),
        'slider' => _buildSliderConfig(),
        _ => null,
      };

      if (widget.isEditing) {
        final updated = widget.field!.copyWith(
          name: name,
          fieldType: legacyFieldType,
          fieldTypeId: _selectedTypeId,
          datePrecision:
              _selectedTypeId == 'date' ? _selectedPrecision : null,
          typeConfig: typeConfig,
        );
        await notifier.updateField(updated);
      } else {
        await notifier.createField(
          name: name,
          fieldType: legacyFieldType,
          datePrecision:
              _selectedTypeId == 'date' ? _selectedPrecision : null,
          fieldTypeId: _selectedTypeId,
          typeConfig: typeConfig,
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
                      // markdown strings. Other types have different storage
                      // shapes and remain locked once created.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final def
                              in customFieldTypeRegistry.definitions)
                            PrismChip(
                              label: _labelForDef(context, def),
                              selected: def.id == _selectedTypeId,
                              onTap: (def.allowsTextualSwitch &&
                                      _isCurrentTypeTextual)
                                  ? () {
                                      setState(
                                          () => _selectedTypeId = def.id);
                                      Haptics.selection();
                                    }
                                  : null,
                              avatar: Icon(def.icon, size: 16),
                            ),
                        ],
                      ),
                      if (!_isCurrentTypeTextual) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.settingsCreateEditFieldTypeImmutable,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ] else ...[
                      // When adding a child field (parentFieldId != null),
                      // hide 'group' to prevent nested groups.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final def
                              in customFieldTypeRegistry.definitions)
                            if (widget.parentFieldId == null ||
                                def.id != 'group')
                              PrismChip(
                                label: _labelForDef(context, def),
                                selected: def.id == _selectedTypeId,
                                onTap: () {
                                  setState(() => _selectedTypeId = def.id);
                                  Haptics.selection();
                                },
                                avatar: Icon(def.icon, size: 16),
                              ),
                        ],
                      ),
                    ],

                    // Date precision picker
                    if (_selectedTypeId == 'date') ...[
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
                    if (_selectedTypeId == 'choice') ...[
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

                    // Scale config
                    if (_selectedTypeId == 'scale') ...[
                      const SizedBox(height: 24),
                      _ScaleConfigSection(
                        selectedEmoji: _scaleEmoji,
                        steps: _scaleSteps,
                        showCustomEmojiInput: _scaleShowCustomEmojiInput,
                        customEmojiController: _scaleCustomEmojiController,
                        onEmojiSelected: (e) =>
                            setState(() => _scaleEmoji = e),
                        onToggleCustomEmoji: () => setState(
                          () => _scaleShowCustomEmojiInput =
                              !_scaleShowCustomEmojiInput,
                        ),
                        onStepsChanged: (v) =>
                            setState(() => _scaleSteps = v),
                      ),
                    ],

                    // Slider config
                    if (_selectedTypeId == 'slider') ...[
                      const SizedBox(height: 24),
                      _SliderConfigSection(
                        isEditMode: widget.isEditing,
                        selectedMode: _sliderMode,
                        leftLabelController: _sliderLeftLabelController,
                        rightLabelController: _sliderRightLabelController,
                        centerLabelController: _sliderCenterLabelController,
                        selectedPresetId: _sliderGradientPresetId,
                        leftColorHex: _sliderLeftColorHex,
                        rightColorHex: _sliderRightColorHex,
                        centerColorHex: _sliderCenterColorHex,
                        snapToPositions: _sliderSnapToPositions,
                        showAdvancedColors: _sliderShowAdvancedColors,
                        minController: _sliderMinController,
                        maxController: _sliderMaxController,
                        stepController: _sliderStepController,
                        unitController: _sliderUnitController,
                        showTicks: _sliderShowTicks,
                        onModeSelected: (m) =>
                            setState(() => _sliderMode = m),
                        onPresetSelected: (id) =>
                            setState(() => _sliderGradientPresetId = id),
                        onToggleAdvancedColors: () => setState(
                          () => _sliderShowAdvancedColors = !_sliderShowAdvancedColors,
                        ),
                        onLeftColorChanged: (hex) =>
                            setState(() => _sliderLeftColorHex = hex),
                        onRightColorChanged: (hex) =>
                            setState(() => _sliderRightColorHex = hex),
                        onCenterColorChanged: (hex) =>
                            setState(() => _sliderCenterColorHex = hex),
                        onSnapToPositionsChanged: (v) =>
                            setState(() => _sliderSnapToPositions = v),
                        onShowTicksChanged: (v) =>
                            setState(() => _sliderShowTicks = v),
                        onLabelChanged: () => setState(() {}),
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

  /// Whether the currently selected type supports textual switching.
  bool get _isCurrentTypeTextual =>
      customFieldTypeRegistry.lookupById(_selectedTypeId)?.allowsTextualSwitch ??
      false;

  /// Resolve a registry definition's labelL10nKey into the localized string.
  /// Bridge pattern: known keys map to AppLocalizations methods; unknown future
  /// types fall back to the key itself.
  ///
  /// TODO: replace with AppLocalizations.resolve(key) once available.
  String _labelForDef(BuildContext context, CustomFieldTypeDefinition def) {
    final l10n = context.l10n;
    return switch (def.labelL10nKey) {
      'customFieldTypeShortText' => l10n.customFieldTypeShortText,
      'customFieldTypeLongText' => l10n.customFieldTypeLongText,
      'customFieldTypeColor' => l10n.customFieldTypeColor,
      'customFieldTypeDate' => l10n.customFieldTypeDate,
      'customFieldTypeChoice' => l10n.customFieldTypeChoice,
      'customFieldTypeGroup' => l10n.customFieldTypeGroup,
      'customFieldTypeScale' => l10n.customFieldTypeScale,
      'customFieldTypeSlider' => l10n.customFieldTypeSlider,
      _ => def.labelL10nKey,
    };
  }
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

// ── Scale config section ────────────────────────────────────────────────────

class _ScaleConfigSection extends StatelessWidget {
  const _ScaleConfigSection({
    required this.selectedEmoji,
    required this.steps,
    required this.showCustomEmojiInput,
    required this.customEmojiController,
    required this.onEmojiSelected,
    required this.onToggleCustomEmoji,
    required this.onStepsChanged,
  });

  final String selectedEmoji;
  final int steps;
  final bool showCustomEmojiInput;
  final TextEditingController customEmojiController;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onToggleCustomEmoji;
  final ValueChanged<int> onStepsChanged;

  static const int _softWarnThreshold = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Emoji picker ──────────────────────────────────────────────
        Text(
          l10n.customFieldScaleEmojiHeading,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final emoji in kScaleEmojiPalette)
              _EmojiPickerButton(
                emoji: emoji,
                isSelected: selectedEmoji == emoji && !showCustomEmojiInput,
                onTap: () => onEmojiSelected(emoji),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onToggleCustomEmoji,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(l10n.customFieldScaleAdvancedEmoji),
        ),
        if (showCustomEmojiInput) ...[
          const SizedBox(height: 8),
          PrismTextField(
            controller: customEmojiController,
            hintText: l10n.customFieldScaleCustomEmojiHint,
            onChanged: (value) {
              // Use the raw input if non-empty (user typed/pasted an emoji).
              // We don't try to extract a single grapheme cluster here since
              // multi-codepoint emoji (ZWJ sequences) would be truncated.
              // The l10n hint text already instructs the user to type/paste
              // a single emoji.
              if (value.isNotEmpty) {
                onEmojiSelected(value);
              }
            },
          ),
        ],

        const SizedBox(height: 24),

        // ── Steps slider ─────────────────────────────────────────────
        Text(
          l10n.customFieldScaleStepsHeading,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: steps.toDouble(),
                min: 2,
                max: 10,
                divisions: 8,
                label: l10n.customFieldScaleStepsHelpFew(steps),
                onChanged: (v) => onStepsChanged(v.round()),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                l10n.customFieldScaleStepsHelpFew(steps),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        if (steps > _softWarnThreshold) ...[
          const SizedBox(height: 4),
          Text(
            l10n.customFieldScaleStepsHelpMany,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        // TODO(spec §2c): Per-step labels UI deferred to v2. The ScaleConfig
        // model already has a `stepLabels` field; the editor UI for populating
        // it was descoped from this batch to keep the surface tight. When
        // implemented, add a "Step labels" toggle here that reveals a list of
        // N text inputs, one per step.
      ],
    );
  }
}

/// A single tappable emoji button in the scale emoji palette picker.
class _EmojiPickerButton extends StatelessWidget {
  const _EmojiPickerButton({
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }
}

// ── Slider config section ───────────────────────────────────────────────────

class _SliderConfigSection extends StatelessWidget {
  const _SliderConfigSection({
    required this.isEditMode,
    required this.selectedMode,
    required this.leftLabelController,
    required this.rightLabelController,
    required this.centerLabelController,
    required this.selectedPresetId,
    required this.leftColorHex,
    required this.rightColorHex,
    required this.centerColorHex,
    required this.snapToPositions,
    required this.showAdvancedColors,
    required this.minController,
    required this.maxController,
    required this.stepController,
    required this.unitController,
    required this.showTicks,
    required this.onModeSelected,
    required this.onPresetSelected,
    required this.onToggleAdvancedColors,
    required this.onLeftColorChanged,
    required this.onRightColorChanged,
    required this.onCenterColorChanged,
    required this.onSnapToPositionsChanged,
    required this.onShowTicksChanged,
    required this.onLabelChanged,
  });

  final bool isEditMode;
  final SliderMode selectedMode;
  final TextEditingController leftLabelController;
  final TextEditingController rightLabelController;
  final TextEditingController centerLabelController;
  final String? selectedPresetId;
  final String? leftColorHex;
  final String? rightColorHex;
  final String? centerColorHex;
  final bool snapToPositions;
  final bool showAdvancedColors;
  final TextEditingController minController;
  final TextEditingController maxController;
  final TextEditingController stepController;
  final TextEditingController unitController;
  final bool showTicks;
  final ValueChanged<SliderMode> onModeSelected;
  final ValueChanged<String> onPresetSelected;
  final VoidCallback onToggleAdvancedColors;
  final ValueChanged<String?> onLeftColorChanged;
  final ValueChanged<String?> onRightColorChanged;
  final ValueChanged<String?> onCenterColorChanged;
  final ValueChanged<bool> onSnapToPositionsChanged;
  final ValueChanged<bool> onShowTicksChanged;
  final VoidCallback onLabelChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Mode chooser ───────────────────────────────────────────────
        Text(
          l10n.customFieldSliderModeHeading,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SliderModeCard(
                title: l10n.customFieldSliderModeLabeled,
                description: l10n.customFieldSliderModeLabeledDescription,
                icon: AppIcons.tuneOutlined,
                isSelected: selectedMode == SliderMode.labeled,
                isDisabled: isEditMode,
                onTap: isEditMode
                    ? null
                    : () => onModeSelected(SliderMode.labeled),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SliderModeCard(
                title: l10n.customFieldSliderModeNumeric,
                description: l10n.customFieldSliderModeNumericDescription,
                icon: AppIcons.tune,
                isSelected: selectedMode == SliderMode.numeric,
                isDisabled: isEditMode,
                onTap: isEditMode
                    ? null
                    : () => onModeSelected(SliderMode.numeric),
              ),
            ),
          ],
        ),
        if (isEditMode) ...[
          const SizedBox(height: 8),
          Text(
            l10n.customFieldSliderModeLockNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const SizedBox(height: 24),

        // ── Labeled sub-section ────────────────────────────────────────
        if (selectedMode == SliderMode.labeled) ...[
          PrismTextField(
            controller: leftLabelController,
            labelText: l10n.customFieldSliderLeftLabel,
            onChanged: (_) => onLabelChanged(),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: rightLabelController,
            labelText: l10n.customFieldSliderRightLabel,
            onChanged: (_) => onLabelChanged(),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: centerLabelController,
            labelText: l10n.customFieldSliderCenterLabel,
            onChanged: (_) => onLabelChanged(),
            textCapitalization: TextCapitalization.sentences,
          ),

          const SizedBox(height: 24),

          // Gradient preset picker.
          Text(
            l10n.customFieldSliderGradientHeading,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final category in SliderGradientCategory.values) ...[
            Text(
              _categoryLabel(l10n, category),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kSliderGradientPresets.where(
                  (p) => p.category == category,
                ))
                  _GradientPresetChip(
                    preset: preset,
                    isSelected: selectedPresetId == preset.id,
                    onTap: () => onPresetSelected(preset.id),
                    labelText: _presetLabel(l10n, preset.labelL10nKey),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Advanced: custom colors disclosure.
          TextButton(
            onPressed: onToggleAdvancedColors,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.customFieldSliderAdvancedColors),
          ),
          if (showAdvancedColors) ...[
            const SizedBox(height: 8),
            _ColorPickerRow(
              labelText: l10n.customFieldSliderLeftLabel,
              colorHex: leftColorHex,
              onColorChanged: onLeftColorChanged,
            ),
            const SizedBox(height: 8),
            if (centerLabelController.text.isNotEmpty) ...[
              _ColorPickerRow(
                labelText: l10n.customFieldSliderCenterLabel,
                colorHex: centerColorHex,
                onColorChanged: onCenterColorChanged,
              ),
              const SizedBox(height: 8),
            ],
            _ColorPickerRow(
              labelText: l10n.customFieldSliderRightLabel,
              colorHex: rightColorHex,
              onColorChanged: onRightColorChanged,
            ),
            const SizedBox(height: 8),
          ],

          // Snap to positions toggle.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.customFieldSliderSnapToPositions,
              style: theme.textTheme.bodyMedium,
            ),
            value: snapToPositions,
            onChanged: onSnapToPositionsChanged,
          ),
        ],

        // ── Numeric sub-section ────────────────────────────────────────
        if (selectedMode == SliderMode.numeric) ...[
          PrismTextField(
            controller: minController,
            labelText: l10n.customFieldSliderMin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onChanged: (_) => onLabelChanged(),
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: maxController,
            labelText: l10n.customFieldSliderMax,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onChanged: (_) => onLabelChanged(),
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: stepController,
            labelText: l10n.customFieldSliderStep,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onLabelChanged(),
          ),
          const SizedBox(height: 12),
          PrismTextField(
            controller: unitController,
            labelText: l10n.customFieldSliderUnit,
            onChanged: (_) => onLabelChanged(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.customFieldSliderShowTicks,
              style: theme.textTheme.bodyMedium,
            ),
            value: showTicks,
            onChanged: onShowTicksChanged,
          ),
        ],
      ],
    );
  }

  String _categoryLabel(AppLocalizations l10n, SliderGradientCategory category) {
    return switch (category) {
      SliderGradientCategory.genderExpression =>
        l10n.customFieldSliderCategoryGenderExpression,
      SliderGradientCategory.moodIntensity =>
        l10n.customFieldSliderCategoryMoodIntensity,
      SliderGradientCategory.temperature =>
        l10n.customFieldSliderCategoryTemperature,
      SliderGradientCategory.neutral =>
        l10n.customFieldSliderCategoryNeutral,
    };
  }

  String _presetLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'sliderGradientPresetFemmeMasc' => l10n.sliderGradientPresetFemmeMasc,
      'sliderGradientPresetSoftHard' => l10n.sliderGradientPresetSoftHard,
      'sliderGradientPresetHighLowGender' =>
        l10n.sliderGradientPresetHighLowGender,
      'sliderGradientPresetFeminineMasculineEnergy' =>
        l10n.sliderGradientPresetFeminineMasculineEnergy,
      'sliderGradientPresetCalmIntense' =>
        l10n.sliderGradientPresetCalmIntense,
      'sliderGradientPresetSadHappy' => l10n.sliderGradientPresetSadHappy,
      'sliderGradientPresetLowHighEnergy' =>
        l10n.sliderGradientPresetLowHighEnergy,
      'sliderGradientPresetSoftBold' => l10n.sliderGradientPresetSoftBold,
      'sliderGradientPresetCoolWarm' => l10n.sliderGradientPresetCoolWarm,
      'sliderGradientPresetDayNight' => l10n.sliderGradientPresetDayNight,
      'sliderGradientPresetSolidAccent' =>
        l10n.sliderGradientPresetSolidAccent,
      'sliderGradientPresetMonochrome' =>
        l10n.sliderGradientPresetMonochrome,
      _ => key,
    };
  }
}

// ── Slider mode card ────────────────────────────────────────────────────────

class _SliderModeCard extends StatelessWidget {
  const _SliderModeCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isDisabled
                      ? theme.colorScheme.onSurfaceVariant
                      : isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isDisabled
                          ? theme.colorScheme.onSurfaceVariant
                          : isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (isDisabled)
                  Icon(
                    AppIcons.lock,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gradient preset chip ─────────────────────────────────────────────────────

class _GradientPresetChip extends StatelessWidget {
  const _GradientPresetChip({
    required this.preset,
    required this.isSelected,
    required this.onTap,
    required this.labelText,
  });

  final SliderGradientPreset preset;
  final bool isSelected;
  final VoidCallback onTap;
  final String labelText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leftColor = AppColors.fromHex(preset.leftHex);
    final rightColor = AppColors.fromHex(preset.rightHex);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 80,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: leftColor == rightColor
                      ? null
                      : LinearGradient(colors: [leftColor, rightColor]),
                  color: leftColor == rightColor ? leftColor : null,
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
              if (isSelected)
                Positioned.fill(
                  child: Center(
                    child: Icon(
                      AppIcons.check,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 80,
            child: Text(
              labelText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Color picker row ─────────────────────────────────────────────────────────

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.labelText,
    required this.colorHex,
    required this.onColorChanged,
  });

  final String labelText;
  final String? colorHex;
  final ValueChanged<String?> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color currentColor;
    try {
      currentColor = colorHex != null
          ? AppColors.fromHex(colorHex!)
          : theme.colorScheme.primary;
    } catch (_) {
      currentColor = theme.colorScheme.primary;
    }

    return Row(
      children: [
        GestureDetector(
          onTap: () async {
            // Simple color picker: cycle through a basic palette
            // matching the slider gradient presets pattern.
            final picked = await showDialog<Color>(
              context: context,
              builder: (ctx) => _SimpleColorPickerDialog(
                initialColor: currentColor,
              ),
            );
            if (picked != null) {
              final hex =
                  '#${picked.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
              onColorChanged(hex);
            }
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: currentColor,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          labelText,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ── Simple color picker dialog ────────────────────────────────────────────────

/// A simple grid color picker for override colors in the slider advanced section.
class _SimpleColorPickerDialog extends StatelessWidget {
  const _SimpleColorPickerDialog({required this.initialColor});

  final Color initialColor;

  static const _palette = [
    Color(0xFFF4A6C8), Color(0xFFC8B1E4), Color(0xFF7BA5D8),
    Color(0xFFF7B5B5), Color(0xFFA8B4C2), Color(0xFF3D4756),
    Color(0xFFE36BB0), Color(0xFFA0A0A0), Color(0xFFE08DA8),
    Color(0xFF3C8E96), Color(0xFF7BAA7E), Color(0xFFD6534D),
    Color(0xFF5479AE), Color(0xFFE4C44F), Color(0xFF8A8A8A),
    Color(0xFFE69248), Color(0xFFD8C7E0), Color(0xFF2D1B36),
    Color(0xFF5B92C9), Color(0xFFE08D5E), Color(0xFFF4D86E),
    Color(0xFF1E2444), Color(0xFF7B5EA8), Color(0xFFE4DEEC),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        context.l10n.customFieldSliderAdvancedColors,
        style: theme.textTheme.titleMedium,
      ),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final color in _palette)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: color == initialColor
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: color == initialColor ? 3 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
      ],
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
