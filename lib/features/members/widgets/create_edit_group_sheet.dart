import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/group_parent_picker.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

const _uuid = Uuid();

const _kGroupColors = [
  Color(0xFFAF8EE9), // prism purple
  Color(0xFFE88EA0), // rose
  Color(0xFF8EA8E8), // blue
  Color(0xFF8EE8A0), // sage green
  Color(0xFFE8D08E), // amber
  Color(0xFFB88EE8), // lavender
  Color(0xFFE88E8E), // red
  Color(0xFF8EE8D0), // teal
  Color(0xFFE8B88E), // orange
  Color(0xFF8EB8E8), // light blue
  Color(0xFFD08EE8), // violet
  Color(0xFF8EE8B8), // mint
  Color(0xFF607D8B), // blue grey
  Color(0xFF795548), // brown
  Color(0xFF9E9E9E), // grey
  Color(0xFF424242), // dark grey
];

/// Modal sheet for creating or editing a member group.
///
/// When [group] is provided the sheet operates in edit mode and pre-populates
/// all fields. Otherwise it starts blank for creation.
///
/// Use via [PrismSheet.showFullScreen] — pass the [scrollController] from the
/// builder callback.
class CreateEditGroupSheet extends ConsumerStatefulWidget {
  const CreateEditGroupSheet({
    super.key,
    this.group,
    required this.scrollController,
  });

  final MemberGroup? group;
  final ScrollController scrollController;

  bool get isEditing => group != null;

  @override
  ConsumerState<CreateEditGroupSheet> createState() =>
      _CreateEditGroupSheetState();
}

class _CreateEditGroupSheetState extends ConsumerState<CreateEditGroupSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  String? _emoji;
  Color? _selectedColor;
  String? _parentGroupId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameController = TextEditingController(text: g?.name ?? '');
    _descriptionController =
        TextEditingController(text: g?.description ?? '');
    if (g?.colorHex != null) {
      _selectedColor = AppColors.fromHex(g!.colorHex!);
    }
    _emoji = g?.emoji;
    _parentGroupId = g?.parentGroupId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _openParentPicker() {
    PrismSheet.show<void>(
      context: context,
      builder: (sheetContext) => GroupParentPicker(
        excludeGroupId: widget.group?.id,
        currentParentId: _parentGroupId,
        onSelected: (id) => setState(() => _parentGroupId = id),
      ),
    );
  }

  Future<void> _openColorPicker() async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    await PrismSheet.show<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.memberGroupColorLabel,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            BlockPicker(
              pickerColor: _selectedColor ?? const Color(0xFFAF8EE9),
              onColorChanged: (color) {
                setState(() => _selectedColor = color);
                Navigator.of(sheetContext).pop();
              },
              availableColors: _kGroupColors,
              layoutBuilder: (context, colors, child) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final color in colors) child(color)],
              ),
              itemBuilder: (color, isCurrentColor, changeColor) =>
                  GestureDetector(
                onTap: changeColor,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isCurrentColor
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3)
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final colorHex = _selectedColor != null
        ? '#${_selectedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
        : null;

    try {
      final notifier = ref.read(groupNotifierProvider.notifier);

      if (widget.isEditing) {
        // Use a rebuild via constructor to properly clear parentGroupId to null
        // when the user has removed the parent (copyWith cannot unset nullable
        // fields to null with freezed without a Value wrapper approach, so we
        // explicitly reconstruct instead).
        final existing = widget.group!;
        final updated = MemberGroup(
          id: existing.id,
          name: name,
          description: description.isNotEmpty ? description : null,
          emoji: _emoji,
          colorHex: colorHex,
          displayOrder: existing.displayOrder,
          parentGroupId: _parentGroupId,
          groupType: existing.groupType,
          filterRules: existing.filterRules,
          createdAt: existing.createdAt,
        );
        await notifier.updateGroup(updated);
      } else {
        final group = MemberGroup(
          id: _uuid.v4(),
          name: name,
          description: description.isNotEmpty ? description : null,
          emoji: _emoji,
          colorHex: colorHex,
          parentGroupId: _parentGroupId,
          createdAt: DateTime.now(),
        );
        await notifier.createGroup(group);
      }

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.memberGroupErrorSaving(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final canSave = _nameController.text.trim().isNotEmpty;

    // Look up the display name for the currently selected parent group.
    // Use `select` so we only rebuild when the relevant group's name changes,
    // not on every keystroke when other groups in the list change.
    final parentDisplayName = _parentGroupId == null
        ? null
        : ref.watch(allGroupsProvider.select((async) =>
            async.value?.where((g) => g.id == _parentGroupId).firstOrNull?.name));

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: widget.isEditing ? l10n.memberGroupEditTitle : l10n.memberGroupNewTitle,
            trailing: PrismGlassIconButton(
                    icon: AppIcons.check,
                    size: PrismTokens.topBarActionSize,
                    isLoading: _saving,
                    tint: canSave ? theme.colorScheme.primary : null,
                    accentIcon: canSave,
                    onPressed: canSave ? _save : null,
                  ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                controller: widget.scrollController,
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                children: [
                  // Emoji picker
                  Center(
                    child: PrismEmojiPicker(
                      emoji: _emoji,
                      size: 64,
                      onSelected: (emoji) {
                        setState(() => _emoji = emoji);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Name
                  PrismTextField(
                    controller: _nameController,
                    labelText: l10n.memberGroupNameLabel,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.memberGroupNameRequired;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  PrismTextField(
                    controller: _descriptionController,
                    labelText: l10n.memberGroupDescriptionLabel,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),

                  // Parent group selector
                  InkWell(
                    onTap: _openParentPicker,
                    borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Icon(AppIcons.folderOutlined, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.memberGroupParentLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  parentDisplayName ?? l10n.memberGroupParentNone,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                          Icon(AppIcons.chevronRight, color: theme.colorScheme.onSurfaceVariant, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Color picker row
                  InkWell(
                    onTap: _openColorPicker,
                    borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _selectedColor ??
                                  theme.colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: theme.colorScheme.outlineVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedColor != null
                                  ? l10n.memberGroupColorLabel
                                  : l10n.memberGroupColorNone,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          if (_selectedColor != null)
                            PrismButton(
                              label: l10n.cancel,
                              tone: PrismButtonTone.subtle,
                              density: PrismControlDensity.compact,
                              onPressed: () =>
                                  setState(() => _selectedColor = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
