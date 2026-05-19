import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/group_display_prefs_provider.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/widgets/group_avatar_picker.dart';
import 'package:prism_plurality/features/members/widgets/group_parent_picker.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

const _uuid = Uuid();

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
    this.initialParentGroupId,
    required this.scrollController,
  });

  final MemberGroup? group;

  /// Pre-select a parent when creating a new group (ignored in edit mode).
  final String? initialParentGroupId;
  final ScrollController scrollController;

  bool get isEditing => group != null;

  @override
  ConsumerState<CreateEditGroupSheet> createState() =>
      _CreateEditGroupSheetState();
}

class _CreateEditGroupSheetState extends ConsumerState<CreateEditGroupSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final MarkdownEditingController _descriptionController;

  String? _emoji;
  Color? _selectedColor;
  String? _parentGroupId;
  bool _saving = false;
  Uint8List? _avatarImageData;
  bool _showEmojiOnAvatar = true;
  late final String _initialName;
  late final String _initialDescription;
  late final String? _initialEmoji;
  late final Color? _initialSelectedColor;
  late final String? _initialParentGroupId;
  late final Uint8List? _initialAvatarImageData;
  // Mutable: a post-frame callback hydrates this from the SharedPreferences-backed provider.
  bool _initialShowEmojiOnAvatar = true;

  bool _bytesEqual(Uint8List? left, Uint8List? right) {
    if (left == null || right == null) return left == right;
    return listEquals(left, right);
  }

  bool get _isDirty =>
      _nameController.text != _initialName ||
      _descriptionController.text != _initialDescription ||
      _emoji != _initialEmoji ||
      _selectedColor != _initialSelectedColor ||
      _parentGroupId != _initialParentGroupId ||
      !_bytesEqual(_avatarImageData, _initialAvatarImageData) ||
      _showEmojiOnAvatar != _initialShowEmojiOnAvatar;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameController = TextEditingController(text: g?.name ?? '');
    _descriptionController = MarkdownEditingController(
      text: g?.description ?? '',
    );
    if (g?.colorHex != null) {
      _selectedColor = AppColors.fromHex(g!.colorHex!);
    }
    _emoji = g?.emoji;
    _parentGroupId = g?.parentGroupId ?? widget.initialParentGroupId;
    _avatarImageData = g?.avatarImageData;
    _initialName = _nameController.text;
    _initialDescription = _descriptionController.text;
    _initialEmoji = _emoji;
    _initialSelectedColor = _selectedColor;
    _initialParentGroupId = _parentGroupId;
    _initialAvatarImageData =
        _avatarImageData == null ? null : Uint8List.fromList(_avatarImageData!);

    if (g != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final asyncVal = ref.read(groupShowEmojiOnAvatarProvider(g.id));
        final persisted = asyncVal.whenOrNull(data: (v) => v) ?? true;
        setState(() {
          _showEmojiOnAvatar = persisted;
          _initialShowEmojiOnAvatar = persisted;
        });
      });
    }
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
    await PrismDialog.show<void>(
      context: context,
      title: l10n.memberGroupColorLabel,
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.54,
            ),
            child: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: _selectedColor ?? const Color(0xFFAF8EE9),
                onColorChanged: (color) =>
                    setState(() => _selectedColor = color),
                enableAlpha: false,
                hexInputBar: true,
                labelTypes: const [],
                portraitOnly: true,
                pickerAreaHeightPercent: 0.65,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_selectedColor != null)
                PrismButton(
                  label: l10n.memberGroupColorClear,
                  tone: PrismButtonTone.subtle,
                  onPressed: () {
                    setState(() => _selectedColor = null);
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                  },
                ),
              PrismButton(
                label: l10n.done,
                tone: PrismButtonTone.filled,
                onPressed: () =>
                    Navigator.of(dialogContext, rootNavigator: true).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openDescriptionEditor() async {
    final l10n = context.l10n;
    final result = await showFullScreenMarkdownEditor(
      context: context,
      title: l10n.memberGroupDescriptionLabel,
      initialText: _descriptionController.text,
      hintText: l10n.memberGroupDescriptionLabel,
    );
    if (result != null && mounted) {
      setState(() => _descriptionController.text = result);
    }
  }

  Future<void> _pickAvatar() async {
    final bytes = await AvatarImagePicker.pickCroppedAvatarBytes(context);
    if (bytes != null && mounted) {
      setState(() => _avatarImageData = bytes);
    }
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
      final allGroupsAsync = ref.read(allGroupsProvider);
      final hierarchyValidationNeeded =
          _parentGroupId != null &&
          _parentGroupId != widget.group?.parentGroupId;
      if (hierarchyValidationNeeded && !allGroupsAsync.hasValue) {
        throw StateError('group hierarchy is still loading');
      }

      final tree = GroupTreeUtils.buildGroupTree(
        GroupTreeUtils.resolveSyncCycles(allGroupsAsync.value ?? const []),
      );
      if (hierarchyValidationNeeded &&
          widget.group != null &&
          _parentGroupId != null &&
          GroupTreeUtils.wouldCreateCycle(
            widget.group!.id,
            _parentGroupId!,
            tree,
          )) {
        throw StateError('selected parent would create a cycle');
      }

      final notifier = ref.read(groupNotifierProvider.notifier);

      String savedId;
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
          avatarImageData: _avatarImageData,
          colorHex: colorHex,
          displayOrder: existing.displayOrder,
          parentGroupId: _parentGroupId,
          groupType: existing.groupType,
          filterRules: existing.filterRules,
          createdAt: existing.createdAt,
        );
        await notifier.updateGroup(updated);
        savedId = existing.id;
      } else {
        savedId = _uuid.v4();
        final group = MemberGroup(
          id: savedId,
          name: name,
          description: description.isNotEmpty ? description : null,
          emoji: _emoji,
          avatarImageData: _avatarImageData,
          colorHex: colorHex,
          parentGroupId: _parentGroupId,
          createdAt: DateTime.now(),
        );
        await notifier.createGroup(group);
      }

      if (_showEmojiOnAvatar != _initialShowEmojiOnAvatar) {
        await ref
            .read(groupShowEmojiOnAvatarProvider(savedId).notifier)
            .set(_showEmojiOnAvatar);
      }

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.memberGroupErrorSaving(e),
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
    final canSave = _nameController.text.trim().isNotEmpty;
    _descriptionController.updateTheme(context);

    // Look up the display name for the currently selected parent group.
    // Use `select` so we only rebuild when the relevant group's name changes,
    // not on every keystroke when other groups in the list change.
    final parentDisplayName = _parentGroupId == null
        ? null
        : ref.watch(
            allGroupsProvider.select(
              (async) => async.value
                  ?.where((g) => g.id == _parentGroupId)
                  .firstOrNull
                  ?.name,
            ),
          );

    return ListenableBuilder(
      listenable: Listenable.merge([_nameController, _descriptionController]),
      builder: (context, _) => UnsavedChangesGuard<bool>(
        hasUnsavedChanges: _isDirty,
        child: SafeArea(
          child: ClipRect(
            child: Column(
              children: [
                PrismSheetTopBar(
                  title: widget.isEditing
                      ? l10n.memberGroupEditTitle
                      : l10n.memberGroupNewTitle,
                  trailing: PrismGlassIconButton(
                    icon: AppIcons.check,
                    tooltip: context.l10n.save,
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
                        Center(
                          child: GroupAvatarPicker(
                            avatarImageData: _avatarImageData,
                            emoji: _emoji,
                            showEmojiOnAvatar: _showEmojiOnAvatar,
                            accentColor: _selectedColor,
                            onPickImage: _pickAvatar,
                            onRemoveImage: () =>
                                setState(() => _avatarImageData = null),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: PrismEmojiPicker(
                            emoji: _emoji,
                            size: 44,
                            onSelected: (emoji) {
                              setState(() => _emoji = emoji);
                            },
                          ),
                        ),
                        if (_avatarImageData != null &&
                            _avatarImageData!.isNotEmpty &&
                            _emoji != null &&
                            _emoji!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          PrismSwitchRow(
                            title: l10n.memberGroupShowEmojiOnAvatar,
                            value: _showEmojiOnAvatar,
                            onChanged: (v) =>
                                setState(() => _showEmojiOnAvatar = v),
                          ),
                        ],
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

                        InkWell(
                          onTap: _openColorPicker,
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        _selectedColor ??
                                        theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.memberGroupColorLabel,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        _selectedColor != null
                                            ? '#${_selectedColor!.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
                                            : l10n.memberGroupColorNone,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  AppIcons.chevronRight,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.memberGroupDescriptionLabel,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            PrismIconButton(
                              icon: AppIcons.edit,
                              tooltip:
                                  l10n.memberGroupDescriptionFullscreenTooltip,
                              onPressed: _openDescriptionEditor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        PrismTextField(
                          controller: _descriptionController,
                          hintText: l10n.memberGroupDescriptionHint,
                          maxLines: 6,
                          minLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 16),

                        InkWell(
                          onTap: _openParentPicker,
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Icon(
                                  AppIcons.folderOutlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.memberGroupParentLabel,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        parentDisplayName ??
                                            l10n.memberGroupParentNone,
                                        style: theme.textTheme.bodyLarge,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  AppIcons.chevronRight,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  size: 18,
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
          ),
        ),
      ),
    );
  }
}
