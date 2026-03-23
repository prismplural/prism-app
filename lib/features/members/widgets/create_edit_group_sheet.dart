import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';

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
  late final TextEditingController _colorHexController;

  String? _emoji;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _nameController = TextEditingController(text: g?.name ?? '');
    _descriptionController =
        TextEditingController(text: g?.description ?? '');
    _colorHexController = TextEditingController(text: g?.colorHex ?? '');
    _emoji = g?.emoji;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _colorHexController.dispose();
    super.dispose();
  }

  Color? _previewColor() {
    final hex = _colorHexController.text.trim();
    if (hex.isEmpty) return null;
    try {
      return AppColors.fromHex(hex);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final colorHex = _colorHexController.text.trim();

    try {
      final notifier = ref.read(groupNotifierProvider.notifier);

      if (widget.isEditing) {
        final updated = widget.group!.copyWith(
          name: name,
          description: description.isNotEmpty ? description : null,
          emoji: _emoji,
          colorHex: colorHex.isNotEmpty ? colorHex : null,
        );
        await notifier.updateGroup(updated);
      } else {
        final group = MemberGroup(
          id: _uuid.v4(),
          name: name,
          description: description.isNotEmpty ? description : null,
          emoji: _emoji,
          colorHex: colorHex.isNotEmpty ? colorHex : null,
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
        PrismToast.error(context, message: 'Error saving group: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _nameController.text.trim().isNotEmpty;
    final previewColor = _previewColor();

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: widget.isEditing ? 'Edit Group' : 'New Group',
            trailing: _saving
                ? SizedBox(
                    width: PrismTokens.topBarActionSize,
                    height: PrismTokens.topBarActionSize,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                : PrismGlassIconButton(
                    icon: Icons.check,
                    size: PrismTokens.topBarActionSize,
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
                    labelText: 'Name',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  PrismTextField(
                    controller: _descriptionController,
                    labelText: 'Description',
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),

                  // Color hex
                  Row(
                    children: [
                      Expanded(
                        child: PrismTextField(
                          controller: _colorHexController,
                          labelText: 'Color (hex)',
                          hintText: '#AF8EE9',
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: previewColor ??
                              theme.colorScheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ],
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
