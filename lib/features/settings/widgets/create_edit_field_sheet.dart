import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
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
import 'package:prism_plurality/shared/utils/custom_field_type_labels.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
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
  // null = Auto; resolved by effectiveDisplayLayout at render time.
  DisplayLayout? _scaleDisplayLayout;
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
  bool _sliderSnapToPositions = false;
  late final TextEditingController _sliderMinController;
  late final TextEditingController _sliderMaxController;
  late final TextEditingController _sliderStepController;
  late final TextEditingController _sliderUnitController;
  bool _sliderShowTicks = false;

  // Group config state.
  bool _groupHideTitleOnProfile = false;

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
      (_selectedTypeId == 'slider' && _isSliderDirty) ||
      (_selectedTypeId == 'group' && _isGroupDirty);

  bool get _isGroupDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! GroupConfig || _selectedTypeId != 'group') {
      return _groupHideTitleOnProfile;
    }
    return existingConfig.hideTitleOnProfile != _groupHideTitleOnProfile;
  }

  bool get _isScaleDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! ScaleConfig || _selectedTypeId != 'scale') {
      return _scaleEmoji != '⭐' ||
          _scaleSteps != 5 ||
          _scaleDisplayLayout != null;
    }
    return existingConfig.emoji != _scaleEmoji ||
        existingConfig.steps != _scaleSteps ||
        existingConfig.displayLayout != _scaleDisplayLayout;
  }

  bool get _isSliderDirty {
    final existingConfig = widget.field?.typeConfig;
    if (existingConfig is! SliderConfig || _selectedTypeId != 'slider') {
      return _sliderGradientPresetId != 'femme-masc' ||
          _sliderLeftLabelController.text.isNotEmpty ||
          _sliderRightLabelController.text.isNotEmpty ||
          _sliderCenterLabelController.text.isNotEmpty ||
          _sliderSnapToPositions ||
          _sliderMinController.text != '0' ||
          _sliderMaxController.text != '10' ||
          _sliderStepController.text != '1' ||
          _sliderUnitController.text.isNotEmpty ||
          _sliderShowTicks;
    }
    if (existingConfig.mode != _sliderMode) return true;
    String? toNullable(String s) => s.trim().isEmpty ? null : s.trim();
    // Mode is locked in edit mode; only diff the fields that mode actually
    // uses. The unused side is hydrated to placeholder defaults, so
    // comparing it would always look dirty.
    if (_sliderMode == SliderMode.labeled) {
      return existingConfig.leftLabel !=
              toNullable(_sliderLeftLabelController.text) ||
          existingConfig.rightLabel !=
              toNullable(_sliderRightLabelController.text) ||
          existingConfig.centerLabel !=
              toNullable(_sliderCenterLabelController.text) ||
          existingConfig.gradientPresetId != _sliderGradientPresetId ||
          existingConfig.leftColorHex != _sliderLeftColorHex ||
          existingConfig.rightColorHex != _sliderRightColorHex ||
          existingConfig.centerColorHex != _sliderCenterColorHex ||
          existingConfig.snapToPositions != _sliderSnapToPositions;
    }
    return existingConfig.min !=
            double.tryParse(_sliderMinController.text.trim()) ||
        existingConfig.max !=
            double.tryParse(_sliderMaxController.text.trim()) ||
        existingConfig.step !=
            double.tryParse(_sliderStepController.text.trim()) ||
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
        _scaleDisplayLayout = config.displayLayout;
        _scaleShowCustomEmojiInput = !kScaleEmojiPalette.contains(config.emoji);
        if (_scaleShowCustomEmojiInput) {
          _scaleCustomEmojiController.text = config.emoji;
        }
      }
      // Hydrate group config from existing field.
      if (f.typeConfig is GroupConfig) {
        final config = f.typeConfig! as GroupConfig;
        _groupHideTitleOnProfile = config.hideTitleOnProfile;
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
  ///
  /// Preserves the existing config's `extra` (forward-compat keys from
  /// future peers) via copyWith when editing.
  ScaleConfig _buildScaleConfig() {
    final existing = widget.field?.typeConfig;
    if (existing is ScaleConfig) {
      return existing.copyWith(
        emoji: _scaleEmoji,
        steps: _scaleSteps,
        displayLayout: _scaleDisplayLayout,
      );
    }
    return ScaleConfig(
      emoji: _scaleEmoji,
      steps: _scaleSteps,
      displayLayout: _scaleDisplayLayout,
    );
  }

  // ── Group helpers ───────────────────────────────────────────────────

  /// copyWith preserves `icon` and any forward-compat `extra` keys.
  GroupConfig _buildGroupConfig() {
    final existing = widget.field?.typeConfig;
    if (existing is GroupConfig) {
      return existing.copyWith(hideTitleOnProfile: _groupHideTitleOnProfile);
    }
    return GroupConfig(hideTitleOnProfile: _groupHideTitleOnProfile);
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

  // ── Slider numeric validation ───────────────────────────────────────

  /// Returns a validation error message when the numeric slider config is
  /// invalid, or null when it is valid. Used to show inline errors and to
  /// disable the Save button.
  String? _sliderNumericError(AppLocalizations l10n) {
    if (_selectedTypeId != 'slider' || _sliderMode != SliderMode.numeric) {
      return null;
    }
    final min = double.tryParse(_sliderMinController.text.trim());
    final max = double.tryParse(_sliderMaxController.text.trim());
    final step = double.tryParse(_sliderStepController.text.trim());
    // Reject NaN and infinity — `NaN >= max` is always false, so a missing
    // isFinite check would let bad values reach the runtime Slider and crash.
    if (min == null || max == null || !min.isFinite || !max.isFinite) {
      return l10n.customFieldSliderNumericRangeError;
    }
    if (min >= max) {
      return l10n.customFieldSliderMinMaxError;
    }
    if (step != null && (!step.isFinite || step <= 0)) {
      return l10n.customFieldSliderStepError;
    }
    return null;
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
    // Groups are the only type allowed to save without a name.
    if (name.isEmpty && _selectedTypeId != 'group') return;

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
        'group' => _buildGroupConfig(),
        _ => null,
      };

      if (widget.isEditing) {
        final existing = widget.field!;
        // Dispatch patch methods per changed field so the wire emit covers
        // only what actually changed; stale values in this snapshot can't
        // clobber peers' concurrent edits (parent_field_id, display_order).
        final nameChanged = existing.name != name;
        final newPrecision =
            _selectedTypeId == 'date' ? _selectedPrecision : null;
        final precisionChanged = existing.datePrecision != newPrecision;
        // typeConfig equality: domain CustomField is `@freezed`, so structural
        // equality applies. For null↔null/non-null, == handles it.
        final configChanged = existing.typeConfig != typeConfig;
        // Textual type-switch (text ↔ longText) changes the type id/enum.
        // This is the only case where we still need a full-row update because
        // the storage shape's stable type identity itself is moving.
        final typeIdChanged = existing.fieldTypeId != _selectedTypeId ||
            existing.fieldType != legacyFieldType;

        if (typeIdChanged) {
          // Re-fetch the raw row: `existing` may be a promoted snapshot
          // (parentFieldId nulled by topLevelCustomFieldsProvider). Without
          // this, the diff would emit parent_field_id=null and destroy the
          // on-disk parent reference.
          final repo = ref.read(customFieldsRepositoryProvider);
          final raw = await repo.getFieldById(existing.id);
          if (raw == null) {
            throw StateError(
              'Field ${existing.id} no longer exists; cannot update.',
            );
          }
          final updated = raw.copyWith(
            name: name,
            fieldType: legacyFieldType,
            fieldTypeId: _selectedTypeId,
            datePrecision: newPrecision,
            typeConfig: typeConfig,
          );
          final err = await notifier.updateField(updated);
          if (err != null) throw err;
        } else {
          // Fire each changed-only patch in order. The wrappers swallow the
          // throw via AsyncValue.guard and return the caught error; re-throw
          // the first non-null so the outer try/catch surfaces it.
          if (nameChanged) {
            final err = await notifier.renameField(existing.id, name);
            if (err != null) throw err;
          }
          if (precisionChanged) {
            final err = await notifier.setFieldDatePrecision(
              existing.id,
              newPrecision,
            );
            if (err != null) throw err;
          }
          if (configChanged && typeConfig != null) {
            final err = await notifier.writeTypedConfig(existing.id, typeConfig);
            if (err != null) throw err;
          }
        }
      } else {
        // Must check the return — InvalidFieldTypeException would otherwise
        // be swallowed and the sheet would pop with a success Haptic.
        final err = await notifier.createField(
          name: name,
          fieldType: legacyFieldType,
          datePrecision:
              _selectedTypeId == 'date' ? _selectedPrecision : null,
          fieldTypeId: _selectedTypeId,
          typeConfig: typeConfig,
          parentFieldId: widget.parentFieldId,
        );
        if (err != null) throw err;
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
    final l10n = context.l10n;
    final sliderError = _sliderNumericError(l10n);
    final hasNameOrIsGroup =
        _nameController.text.trim().isNotEmpty || _selectedTypeId == 'group';
    final canSave = hasNameOrIsGroup && sliderError == null;

    return ListenableBuilder(
      // Also listen to slider controllers so canSave reacts to min/max/step.
      listenable: Listenable.merge([
        _nameController,
        _sliderMinController,
        _sliderMaxController,
        _sliderStepController,
      ]),
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
                      // Edit mode shows only the chip(s) you can actually
                      // pick: both textual types when the current type is
                      // textual (short ↔ long), or the single locked chip
                      // otherwise.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final def in customFieldTypeRegistry.definitions)
                            if (_isCurrentTypeTextual
                                ? def.allowsTextualSwitch
                                : def.id == _selectedTypeId)
                              PrismChip(
                                label: _labelForDef(context, def),
                                selected: def.id == _selectedTypeId,
                                onTap: _isCurrentTypeTextual
                                    ? () {
                                        setState(
                                          () => _selectedTypeId = def.id,
                                        );
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
                        displayLayout: _scaleDisplayLayout,
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
                        onDisplayLayoutChanged: (v) =>
                            setState(() => _scaleDisplayLayout = v),
                      ),
                    ],

                    // Group config
                    if (_selectedTypeId == 'group') ...[
                      const SizedBox(height: 24),
                      _GroupConfigSection(
                        hideTitleOnProfile: _groupHideTitleOnProfile,
                        onHideTitleChanged: (v) => setState(
                          () => _groupHideTitleOnProfile = v,
                        ),
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
                        minController: _sliderMinController,
                        maxController: _sliderMaxController,
                        stepController: _sliderStepController,
                        unitController: _sliderUnitController,
                        showTicks: _sliderShowTicks,
                        numericError: sliderError,
                        onModeSelected: (m) =>
                            setState(() => _sliderMode = m),
                        onPresetSelected: (id) =>
                            setState(() => _sliderGradientPresetId = id),
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
  /// Delegates to the shared resolver so every surface stays in sync.
  String _labelForDef(BuildContext context, CustomFieldTypeDefinition def) =>
      localizedFieldTypeDefLabel(context.l10n, def);
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
    required this.displayLayout,
    required this.showCustomEmojiInput,
    required this.customEmojiController,
    required this.onEmojiSelected,
    required this.onToggleCustomEmoji,
    required this.onStepsChanged,
    required this.onDisplayLayoutChanged,
  });

  final String selectedEmoji;
  final int steps;
  final DisplayLayout? displayLayout;
  final bool showCustomEmojiInput;
  final TextEditingController customEmojiController;
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onToggleCustomEmoji;
  final ValueChanged<int> onStepsChanged;
  final ValueChanged<DisplayLayout?> onDisplayLayoutChanged;

  static const int _softWarnThreshold = 7;
  // Five 32dp boxes fit a typical phone value column; 6+ start to wrap.
  static const int _layoutSuggestStackedAbove = 5;

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
            _CustomEmojiButton(
              isSelected: showCustomEmojiInput,
              onTap: onToggleCustomEmoji,
              tooltip: l10n.customFieldScaleCustomEmoji,
            ),
          ],
        ),
        if (showCustomEmojiInput) ...[
          const SizedBox(height: 12),
          PrismTextField(
            controller: customEmojiController,
            hintText: l10n.customFieldScaleCustomEmojiHint,
            onChanged: (value) {
              if (value.isNotEmpty) onEmojiSelected(value);
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

        const SizedBox(height: 24),

        // ── Layout chooser ────────────────────────────────────────────
        Text(
          l10n.customFieldScaleLayoutHeading,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DisplayLayout?>(
          segments: [
            ButtonSegment(
              value: null,
              label: Text(l10n.customFieldScaleLayoutAuto),
            ),
            ButtonSegment(
              value: DisplayLayout.compact,
              label: Text(l10n.customFieldScaleLayoutCompact),
            ),
            ButtonSegment(
              value: DisplayLayout.stacked,
              label: Text(l10n.customFieldScaleLayoutStacked),
            ),
          ],
          selected: {displayLayout},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onDisplayLayoutChanged(s.first),
        ),
        if (steps > _layoutSuggestStackedAbove &&
            displayLayout != DisplayLayout.stacked) ...[
          const SizedBox(height: 4),
          Text(
            l10n.customFieldScaleLayoutSuggestStacked,
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

class _CustomEmojiButton extends StatelessWidget {
  const _CustomEmojiButton({
    required this.isSelected,
    required this.onTap,
    required this.tooltip,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
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
            child: Icon(
              AppIcons.editOutlined,
              size: 18,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
    required this.minController,
    required this.maxController,
    required this.stepController,
    required this.unitController,
    required this.showTicks,
    this.numericError,
    required this.onModeSelected,
    required this.onPresetSelected,
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
  final TextEditingController minController;
  final TextEditingController maxController;
  final TextEditingController stepController;
  final TextEditingController unitController;
  final bool showTicks;
  /// Validation error for numeric mode (min >= max or step <= 0). When
  /// non-null, shown inline below the numeric controls and the Save button is
  /// disabled by the parent.
  final String? numericError;
  final ValueChanged<SliderMode> onModeSelected;
  /// Null marks the synthetic "Custom" choice, which reveals the per-anchor
  /// color pickers.
  final ValueChanged<String?> onPresetSelected;
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
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Text(
            l10n.customFieldSliderCustomGradient,
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
              _CustomGradientChip(
                isSelected: selectedPresetId == null,
                onTap: () => onPresetSelected(null),
                leftColorHex: leftColorHex,
                centerColorHex: centerColorHex,
                rightColorHex: rightColorHex,
                labelText: l10n.customFieldSliderCustomGradient,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (selectedPresetId == null) ...[
            _ColorPickerRow(
              labelText: l10n.customFieldSliderLeftLabel,
              colorHex: leftColorHex,
              onColorChanged: onLeftColorChanged,
            ),
            const SizedBox(height: 8),
            _ColorPickerRow(
              labelText: l10n.customFieldSliderCenterLabel,
              colorHex: centerColorHex,
              onColorChanged: onCenterColorChanged,
              placeholderWhenNull: true,
              onClear: centerColorHex == null
                  ? null
                  : () => onCenterColorChanged(null),
            ),
            const SizedBox(height: 8),
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
          // Inline validation error for min >= max or step <= 0.
          if (numericError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    numericError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  String _categoryLabel(AppLocalizations l10n, SliderGradientCategory category) {
    return switch (category) {
      SliderGradientCategory.identity =>
        l10n.customFieldSliderCategoryIdentity,
      SliderGradientCategory.moodIntensity =>
        l10n.customFieldSliderCategoryMoodIntensity,
      SliderGradientCategory.temperature =>
        l10n.customFieldSliderCategoryTemperature,
      SliderGradientCategory.palette =>
        l10n.customFieldSliderCategoryPalette,
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
      'sliderGradientPresetPaletteRoseDusk' =>
        l10n.sliderGradientPresetPaletteRoseDusk,
      'sliderGradientPresetPaletteSageMeadow' =>
        l10n.sliderGradientPresetPaletteSageMeadow,
      'sliderGradientPresetPaletteLastLight' =>
        l10n.sliderGradientPresetPaletteLastLight,
      'sliderGradientPresetPaletteAmberFire' =>
        l10n.sliderGradientPresetPaletteAmberFire,
      'sliderGradientPresetPaletteMauveBloom' =>
        l10n.sliderGradientPresetPaletteMauveBloom,
      'sliderGradientPresetPaletteWarmInk' =>
        l10n.sliderGradientPresetPaletteWarmInk,
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
    final centerColor =
        preset.centerHex == null ? null : AppColors.fromHex(preset.centerHex!);
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
                  gradient:
                      leftColor == rightColor && centerColor == null
                      ? null
                      : () {
                          final stops = sliderGradientStops(
                            leftColor,
                            centerColor,
                            rightColor,
                          );
                          return LinearGradient(
                            colors: stops,
                            stops: sliderGradientStopPositions(stops),
                          );
                        }(),
                  color: leftColor == rightColor && centerColor == null
                      ? leftColor
                      : null,
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
    this.placeholderWhenNull = false,
    this.onClear,
  });

  final String labelText;
  final String? colorHex;
  final ValueChanged<String?> onColorChanged;
  // When true and colorHex is null, render a hollow circle with a + icon
  // instead of a primary-colored fill — reads as "tap to add" for optional
  // anchors like the gradient midpoint.
  final bool placeholderWhenNull;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showPlaceholder = colorHex == null && placeholderWhenNull;

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
          onTap: () => _openColorPicker(context, currentColor),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: showPlaceholder ? Colors.transparent : currentColor,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(
                  alpha: showPlaceholder ? 0.7 : 0.5,
                ),
              ),
            ),
            child: showPlaceholder
                ? Icon(
                    AppIcons.add,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            labelText,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (onClear != null && colorHex != null)
          IconButton(
            icon: Icon(AppIcons.close, size: 18),
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Future<void> _openColorPicker(
    BuildContext context,
    Color initialColor,
  ) async {
    var picked = initialColor;
    final confirmed = await PrismDialog.show<bool>(
      context: context,
      title: context.l10n.customFieldSliderColorAnchorTitle,
      builder: (dialogContext) {
        return ColorPicker(
          pickerColor: initialColor,
          onColorChanged: (color) => picked = color,
          enableAlpha: false,
          hexInputBar: true,
          labelTypes: const [],
          portraitOnly: true,
          pickerAreaHeightPercent: 0.7,
        );
      },
      actions: [
        PrismButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          label: context.l10n.cancel,
        ),
        PrismButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(true),
          label: context.l10n.save,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
    if (confirmed == true) {
      final value = picked.toARGB32();
      final hex =
          '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      onColorChanged(hex);
    }
  }
}

class _CustomGradientChip extends StatelessWidget {
  const _CustomGradientChip({
    required this.isSelected,
    required this.onTap,
    required this.leftColorHex,
    required this.centerColorHex,
    required this.rightColorHex,
    required this.labelText,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final String? leftColorHex;
  final String? centerColorHex;
  final String? rightColorHex;
  final String labelText;

  Color _parse(String? hex, Color fallback) {
    if (hex == null) return fallback;
    try {
      return AppColors.fromHex(hex);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = theme.colorScheme.primary;
    final left = _parse(leftColorHex, fallback);
    final right = _parse(rightColorHex, fallback);
    final center = centerColorHex == null ? null : _parse(centerColorHex, left);
    final stops = sliderGradientStops(left, center, right);
    final gradient = LinearGradient(
      colors: stops,
      stops: sliderGradientStopPositions(stops),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 12,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(labelText, style: theme.textTheme.bodyMedium),
          ],
        ),
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

// ── Group config section ────────────────────────────────────────────────────

class _GroupConfigSection extends StatelessWidget {
  const _GroupConfigSection({
    required this.hideTitleOnProfile,
    required this.onHideTitleChanged,
  });

  final bool hideTitleOnProfile;
  final ValueChanged<bool> onHideTitleChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: !hideTitleOnProfile,
          onChanged: (v) => onHideTitleChanged(!v),
          title: Text(
            l10n.customFieldGroupShowTitleLabel,
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text(
            l10n.customFieldGroupShowTitleSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
