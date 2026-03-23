import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_editor.dart';
import 'package:uuid/uuid.dart';

/// A modal sheet for creating or editing a system member.
///
/// When [member] is provided the sheet operates in edit mode and pre-populates
/// all fields. Otherwise it starts blank for creation.
///
/// Use via [PrismSheet.showFullScreen] — pass the [scrollController] from the
/// builder callback.
class AddEditMemberSheet extends ConsumerStatefulWidget {
  const AddEditMemberSheet({
    super.key,
    this.member,
    required this.scrollController,
  });

  final Member? member;
  final ScrollController scrollController;

  bool get isEditing => member != null;

  @override
  ConsumerState<AddEditMemberSheet> createState() =>
      _AddEditMemberSheetState();
}

class _AddEditMemberSheetState extends ConsumerState<AddEditMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final String _memberId;

  late final TextEditingController _nameController;
  late final TextEditingController _pronounsController;
  late final TextEditingController _bioController;
  late final TextEditingController _emojiController;
  late final TextEditingController _ageController;
  late final TextEditingController _colorHexController;

  bool _isAdmin = false;
  bool _markdownEnabled = false;
  bool _customColorEnabled = false;
  Uint8List? _avatarImageData;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _memberId = widget.member?.id ?? const Uuid().v4();
    final m = widget.member;
    _nameController = TextEditingController(text: m?.name ?? '');
    _pronounsController = TextEditingController(text: m?.pronouns ?? '');
    _bioController = TextEditingController(text: m?.bio ?? '');
    _emojiController = TextEditingController(text: m?.emoji ?? '❔');
    _ageController =
        TextEditingController(text: m?.age != null ? '${m!.age}' : '');
    _colorHexController =
        TextEditingController(text: m?.customColorHex ?? '');
    _isAdmin = m?.isAdmin ?? false;
    _markdownEnabled = m?.markdownEnabled ?? false;
    _customColorEnabled = m?.customColorEnabled ?? false;
    _avatarImageData = m?.avatarImageData;
  }

  @override
  void dispose() {
    // Clean up orphaned custom field values if member creation was cancelled.
    if (!widget.isEditing && !_saved) {
      ref
          .read(customFieldValueNotifierProvider.notifier)
          .deleteValuesForMember(_memberId);
    }
    _nameController.dispose();
    _pronounsController.dispose();
    _bioController.dispose();
    _emojiController.dispose();
    _ageController.dispose();
    _colorHexController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _avatarImageData = bytes);
    }
  }

  Color? _previewColor() {
    if (!_customColorEnabled) return null;
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
    final pronouns = _pronounsController.text.trim();
    final bio = _bioController.text.trim();
    final emoji = _emojiController.text.trim();
    final ageText = _ageController.text.trim();
    final age = ageText.isNotEmpty ? int.tryParse(ageText) : null;
    final colorHex = _customColorEnabled
        ? _colorHexController.text.trim().isNotEmpty
            ? _colorHexController.text.trim()
            : null
        : null;

    try {
      final notifier = ref.read(membersNotifierProvider.notifier);

      if (widget.isEditing) {
        final updated = widget.member!.copyWith(
          name: name,
          pronouns: pronouns.isNotEmpty ? pronouns : null,
          emoji: emoji.isNotEmpty ? emoji : '❔',
          age: age,
          bio: bio.isNotEmpty ? bio : null,
          avatarImageData: _avatarImageData,
          isAdmin: _isAdmin,
          markdownEnabled: _markdownEnabled,
          customColorEnabled: _customColorEnabled,
          customColorHex: colorHex,
        );
        await notifier.updateMember(updated);
      } else {
        await notifier.createMember(
          id: _memberId,
          name: name,
          pronouns: pronouns.isNotEmpty ? pronouns : null,
          emoji: emoji.isNotEmpty ? emoji : '❔',
          age: age,
          bio: bio.isNotEmpty ? bio : null,
          avatarImageData: _avatarImageData,
          isAdmin: _isAdmin,
          customColorHex: colorHex,
        );
      }

      _saved = true;
      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error saving ${ref.read(terminologyProvider).singularLower}: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = ref.watch(terminologyProvider);

    final canSave = _nameController.text.trim().isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: widget.isEditing ? terms.editText : terms.newText,
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
                        // Avatar
                        Center(
                          child: GestureDetector(
                            onTap: _pickAvatar,
                            child: Stack(
                              children: [
                                MemberAvatar(
                                  avatarImageData: _avatarImageData,
                                  emoji: _emojiController.text.isNotEmpty
                                      ? _emojiController.text
                                      : '❔',
                                  customColorEnabled: _customColorEnabled,
                                  customColorHex:
                                      _colorHexController.text.isNotEmpty
                                          ? _colorHexController.text
                                          : null,
                                  size: 96,
                                  showBorder: true,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 18,
                                      color: theme
                                          .colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Emoji + Name
                        Row(
                          children: [
                            PrismEmojiPicker(
                              emoji: _emojiController.text.isNotEmpty
                                  ? _emojiController.text
                                  : null,
                              onSelected: (emoji) {
                                setState(() {
                                  _emojiController.text = emoji;
                                });
                              },
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PrismTextField(
                                controller: _nameController,
                                labelText: 'Name *',
                                hintText: 'Enter name',
                                textCapitalization: TextCapitalization.words,
                                onChanged: (_) => setState(() {}),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Name is required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Pronouns
                        PrismTextField(
                          controller: _pronounsController,
                          labelText: 'Pronouns',
                          hintText: 'e.g. she/her, they/them',
                        ),
                        const SizedBox(height: 16),

                        // Age
                        PrismTextField(
                          controller: _ageController,
                          labelText: 'Age',
                          hintText: 'Optional',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Bio
                        PrismTextField(
                          controller: _bioController,
                          labelText: 'Bio',
                          hintText: 'A short description...',
                          alignLabelWithHint: true,
                          maxLines: 4,
                          minLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 8),

                        // Markdown toggle
                        PrismSwitchRow(
                          title: 'Format bio as markdown',
                          subtitle: 'Render bio text with markdown formatting',
                          value: _markdownEnabled,
                          onChanged: (v) =>
                              setState(() => _markdownEnabled = v),
                        ),
                        const SizedBox(height: 16),

                        // Admin toggle
                        PrismSwitchRow(
                          title: 'Admin',
                          subtitle: 'Admins can manage system settings',
                          value: _isAdmin,
                          onChanged: (v) => setState(() => _isAdmin = v),
                        ),
                        const SizedBox(height: 8),

                        // Custom color toggle + hex input
                        PrismSwitchRow(
                          title: 'Custom color',
                          subtitle: 'Use a personal color for this member',
                          value: _customColorEnabled,
                          onChanged: (v) =>
                              setState(() => _customColorEnabled = v),
                        ),
                        if (_customColorEnabled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Color preview circle
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _previewColor() ??
                                      theme.colorScheme.surfaceContainerHighest,
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PrismTextField(
                                  controller: _colorHexController,
                                  labelText: 'Color hex',
                                  hintText: '#AF8EE9',
                                  prefixText: '#',
                                  onChanged: (_) => setState(() {}),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9a-fA-F]'),
                                    ),
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Custom fields
                        CustomFieldsEditor(memberId: _memberId),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
  }
}
