import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/birthday.dart';
import 'package:prism_plurality/features/members/utils/proxy_tag.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_picker_text_field_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_fields_editor.dart';
import 'package:prism_plurality/features/members/widgets/member_name_style_dialog.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header_editor.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:uuid/uuid.dart';

/// A modal sheet for creating or editing a system member.
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
  ConsumerState<AddEditMemberSheet> createState() => _AddEditMemberSheetState();
}

class _AddEditMemberSheetState extends ConsumerState<AddEditMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  late final String _memberId;

  late final TextEditingController _nameController;
  late final TextEditingController _pronounsController;
  late final TextEditingController _bioController;
  late final TextEditingController _emojiController;
  late final TextEditingController _ageController;
  late final TextEditingController _colorHexController;
  late final TextEditingController _displayNameController;
  final List<_ProxyTagDraft> _proxyTagDrafts = [];

  bool _isAdmin = false;
  bool _markdownEnabled = false;
  bool _customColorEnabled = false;
  Uint8List? _avatarImageData;
  late MemberProfileHeaderSource _profileHeaderSource;
  late MemberProfileHeaderLayout _profileHeaderLayout;
  bool _profileHeaderVisible = true;
  late MemberNameFont _nameStyleFont;
  bool _nameStyleBold = true;
  bool _nameStyleItalic = false;
  late MemberNameColorMode _nameStyleColorMode;
  String? _nameStyleColorHex;
  Uint8List? _profileHeaderImageData;
  bool _saving = false;
  bool _saved = false;

  /// Parsed birthday (null when unset). When [_birthdayHideYear] is true the
  /// year is irrelevant for display; the wire format will substitute the PK
  /// `0004` sentinel on save.
  DateTime? _birthday;
  bool _birthdayHideYear = false;

  @override
  void initState() {
    super.initState();
    _memberId = widget.member?.id ?? const Uuid().v4();
    final m = widget.member;
    _nameController = TextEditingController(text: m?.name ?? '');
    _pronounsController = TextEditingController(text: m?.pronouns ?? '');
    _bioController = TextEditingController(text: m?.bio ?? '');
    _emojiController = TextEditingController(text: m?.emoji ?? '❔');
    _ageController = TextEditingController(
      text: m?.age != null ? '${m!.age}' : '',
    );
    _colorHexController = TextEditingController(
      text: _normalizeColorHexForField(m?.customColorHex),
    );
    _displayNameController = TextEditingController(text: m?.displayName ?? '');
    _proxyTagDrafts
      ..clear()
      ..addAll(parseProxyTags(m?.proxyTagsJson).map(_ProxyTagDraft.fromTag));
    final parsedBirthday = parseBirthday(m?.birthday);
    _birthday = parsedBirthday;
    _birthdayHideYear =
        parsedBirthday != null && isBirthdayYearHidden(parsedBirthday);
    _isAdmin = m?.isAdmin ?? false;
    _markdownEnabled = m?.markdownEnabled ?? false;
    _customColorEnabled = m?.customColorEnabled ?? false;
    _avatarImageData = m?.avatarImageData;
    _profileHeaderSource =
        m?.profileHeaderSource ?? MemberProfileHeaderSource.prism;
    _profileHeaderLayout =
        m?.profileHeaderLayout ?? MemberProfileHeaderLayout.compactBackground;
    _profileHeaderVisible = m?.profileHeaderVisible ?? true;
    _nameStyleFont = m?.nameStyleFont ?? MemberNameFont.standard;
    _nameStyleBold = m?.nameStyleBold ?? true;
    _nameStyleItalic = m?.nameStyleItalic ?? false;
    _nameStyleColorMode = m?.nameStyleColorMode ?? MemberNameColorMode.standard;
    _nameStyleColorHex = m?.nameStyleColorHex;
    _profileHeaderImageData = m?.profileHeaderImageData;
  }

  @override
  void dispose() {
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
    _displayNameController.dispose();
    for (final draft in _proxyTagDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final bytes = await AvatarImagePicker.pickCroppedAvatarBytes(context);
    if (bytes != null && mounted) {
      setState(() => _avatarImageData = bytes);
    }
  }

  String? _proxyTagsJson() => encodeProxyTags(
    _proxyTagDrafts.map(
      (draft) => ProxyTag(
        prefix: draft.prefixController.text,
        suffix: draft.suffixController.text,
      ),
    ),
    emptyAsJsonList: widget.member?.proxyTagsJson != null,
  );

  void _addProxyTag() {
    setState(() => _proxyTagDrafts.add(_ProxyTagDraft()));
  }

  void _removeProxyTag(_ProxyTagDraft draft) {
    setState(() {
      _proxyTagDrafts.remove(draft);
      draft.dispose();
    });
  }

  Member _previewMember() {
    final name = _nameController.text.trim();
    final emoji = _emojiController.text.trim();
    final displayName = _displayNameController.text.trim();
    final pronouns = _pronounsController.text.trim();
    final ageText = _ageController.text.trim();
    final age = ageText.isNotEmpty ? int.tryParse(ageText) : null;
    final colorHex = _colorHexController.text.trim();
    final birthdayWire = _birthday == null
        ? null
        : formatBirthdayWire(_birthday!, hideYear: _birthdayHideYear);

    return (widget.member ??
            Member(
              id: _memberId,
              name: name.isNotEmpty ? name : '',
              emoji: emoji.isNotEmpty ? emoji : '❔',
              createdAt: DateTime.now(),
            ))
        .copyWith(
          name: name.isNotEmpty ? name : (widget.member?.name ?? ''),
          pronouns: pronouns.isNotEmpty ? pronouns : null,
          emoji: emoji.isNotEmpty ? emoji : '❔',
          age: age,
          birthday: birthdayWire,
          proxyTagsJson: _proxyTagsJson(),
          displayName: displayName.isNotEmpty ? displayName : null,
          avatarImageData: _avatarImageData,
          customColorEnabled: _customColorEnabled,
          customColorHex: _customColorEnabled && colorHex.isNotEmpty
              ? colorHex
              : null,
          profileHeaderSource: _profileHeaderSource,
          profileHeaderLayout: _profileHeaderLayout,
          profileHeaderVisible: _profileHeaderVisible,
          nameStyleFont: _nameStyleFont,
          nameStyleBold: _nameStyleBold,
          nameStyleItalic: _nameStyleItalic,
          nameStyleColorMode: _nameStyleColorMode,
          nameStyleColorHex: _nameStyleColorMode == MemberNameColorMode.custom
              ? _nameStyleColorHex
              : null,
          profileHeaderImageData: _profileHeaderImageData,
        );
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

  String _normalizeColorHexForField(String? hex) {
    final cleaned = (hex ?? '').trim().replaceFirst('#', '');
    if (cleaned.length == 8 && cleaned.toUpperCase().startsWith('FF')) {
      return cleaned.substring(2).toUpperCase();
    }
    return cleaned.toUpperCase();
  }

  String _colorToFieldHex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return value.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  Future<void> _openCustomColorPicker() async {
    var pickerColor = _previewColor() ?? const Color(0xFFAF8EE9);

    await PrismDialog.show<void>(
      context: context,
      title: context.l10n.settingsAccentColorPickerTitle,
      builder: (_) {
        return SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        );
      },
      actions: [
        PrismButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          label: context.l10n.cancel,
        ),
        PrismButton(
          onPressed: () {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() {
              _colorHexController.text = _colorToFieldHex(pickerColor);
            });
          },
          label: context.l10n.settingsAccentColorSelect,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  Future<void> _pickBirthday(BuildContext anchorContext) async {
    // When hiding the year we still need an anchor year for the picker; pin
    // to year 2000 so month/day wrap normally. When the user has a real year
    // already, seed from that; otherwise default to 20 years ago as a
    // reasonable scroll starting point.
    final initial = _birthday != null && !isBirthdayYearHidden(_birthday!)
        ? _birthday!
        : _birthday != null
        ? DateTime(2000, _birthday!.month, _birthday!.day)
        : DateTime(DateTime.now().year - 20, 1, 1);
    final picked = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _birthday = picked);
    }
  }

  Future<void> _openNameStyleDialog() {
    return MemberNameStyleDialog.show(
      context: context,
      member: _previewMember(),
      onSaved: (member) => setState(() {
        _nameStyleFont = member.nameStyleFont;
        _nameStyleBold = member.nameStyleBold;
        _nameStyleItalic = member.nameStyleItalic;
        _nameStyleColorMode = member.nameStyleColorMode;
        _nameStyleColorHex =
            member.nameStyleColorMode == MemberNameColorMode.custom
            ? member.nameStyleColorHex
            : null;
      }),
    );
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
    final displayName = _displayNameController.text.trim();
    // Preserve PK's `YYYY-MM-DD` wire format so round-trips stay byte-identical;
    // `0004-MM-DD` is the "no year" sentinel that PK uses when the year is hidden.
    final birthdayWire = _birthday == null
        ? null
        : formatBirthdayWire(_birthday!, hideYear: _birthdayHideYear);
    final proxyTagsJson = _proxyTagsJson();

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
          displayName: displayName.isNotEmpty ? displayName : null,
          birthday: birthdayWire,
          proxyTagsJson: proxyTagsJson,
          profileHeaderSource: _profileHeaderSource,
          profileHeaderLayout: _profileHeaderLayout,
          profileHeaderVisible: _profileHeaderVisible,
          nameStyleFont: _nameStyleFont,
          nameStyleBold: _nameStyleBold,
          nameStyleItalic: _nameStyleItalic,
          nameStyleColorMode: _nameStyleColorMode,
          nameStyleColorHex: _nameStyleColorMode == MemberNameColorMode.custom
              ? _nameStyleColorHex
              : null,
          profileHeaderImageData: _profileHeaderImageData,
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
          displayName: displayName.isNotEmpty ? displayName : null,
          birthday: birthdayWire,
          proxyTagsJson: proxyTagsJson,
          profileHeaderSource: _profileHeaderSource,
          profileHeaderLayout: _profileHeaderLayout,
          profileHeaderVisible: _profileHeaderVisible,
          nameStyleFont: _nameStyleFont,
          nameStyleBold: _nameStyleBold,
          nameStyleItalic: _nameStyleItalic,
          nameStyleColorMode: _nameStyleColorMode,
          nameStyleColorHex: _nameStyleColorMode == MemberNameColorMode.custom
              ? _nameStyleColorHex
              : null,
          profileHeaderImageData: _profileHeaderImageData,
        );
      }

      _saved = true;
      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.memberErrorSaving(
            readTerminology(context, ref).singularLower,
            e,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final l10n = context.l10n;

    final canSave = _nameController.text.trim().isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: widget.isEditing
                ? context.l10n.terminologyEditItem(terms.singular)
                : context.l10n.terminologyNewItem(terms.singular),
            trailing: PrismGlassIconButton(
              icon: AppIcons.check,
              size: PrismTokens.topBarActionSize,
              tooltip: l10n.memberSaveTooltip(terms.singularLower),
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
                  MemberProfileHeaderEditor(
                    member: _previewMember(),
                    source: _profileHeaderSource,
                    layout: _profileHeaderLayout,
                    visible: _profileHeaderVisible,
                    prismHeaderImageData: _profileHeaderImageData,
                    pluralKitHeaderImageData: widget.member?.pkBannerImageData,
                    onSourceChanged: (source) =>
                        setState(() => _profileHeaderSource = source),
                    onLayoutChanged: (layout) =>
                        setState(() => _profileHeaderLayout = layout),
                    onVisibleChanged: (visible) =>
                        setState(() => _profileHeaderVisible = visible),
                    onPrismHeaderImageChanged: (bytes) =>
                        setState(() => _profileHeaderImageData = bytes),
                    onAvatarTap: _pickAvatar,
                    onAvatarRemove: _avatarImageData != null
                        ? () => setState(() => _avatarImageData = null)
                        : null,
                    onNameStyleTap: _openNameStyleDialog,
                  ),
                  const SizedBox(height: 24),

                  PrismPickerTextFieldRow(
                    pickerLabel: context.l10n.onboardingAddMemberFieldEmoji,
                    picker: PrismEmojiPicker(
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
                    field: PrismTextField(
                      controller: _nameController,
                      labelText: l10n.memberNameLabel,
                      hintText: l10n.memberNameHint,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.memberNameRequired;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  PrismTextField(
                    controller: _displayNameController,
                    labelText: l10n.memberDisplayNameLabel,
                    hintText: l10n.memberDisplayNameHint,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  _ProxyTagsEditor(
                    drafts: _proxyTagDrafts,
                    onAdd: _addProxyTag,
                    onRemove: _removeProxyTag,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  PrismTextField(
                    controller: _pronounsController,
                    labelText: l10n.memberPronounsLabel,
                    hintText: l10n.memberPronounsHint,
                  ),
                  const SizedBox(height: 16),

                  PrismTextField(
                    controller: _ageController,
                    labelText: l10n.memberAgeLabel,
                    hintText: l10n.memberAgeHint,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),

                  _BirthdayField(
                    date: _birthday,
                    hideYear: _birthdayHideYear,
                    onPick: _pickBirthday,
                    onClear: () => setState(() => _birthday = null),
                    onToggleHideYear: (v) =>
                        setState(() => _birthdayHideYear = v),
                  ),
                  const SizedBox(height: 16),

                  PrismTextField(
                    controller: _bioController,
                    labelText: l10n.memberBioLabel,
                    hintText: l10n.memberBioHint,
                    maxLines: 4,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 8),

                  PrismSwitchRow(
                    title: l10n.memberMarkdownTitle,
                    subtitle: l10n.memberMarkdownSubtitle,
                    value: _markdownEnabled,
                    onChanged: (v) => setState(() => _markdownEnabled = v),
                  ),
                  const SizedBox(height: 16),

                  PrismSwitchRow(
                    title: l10n.memberAdminTitle,
                    subtitle: l10n.memberAdminSubtitle,
                    value: _isAdmin,
                    onChanged: (v) => setState(() => _isAdmin = v),
                  ),
                  const SizedBox(height: 8),

                  PrismSwitchRow(
                    title: l10n.memberCustomColorTitle,
                    subtitle: l10n.memberCustomColorSubtitle(
                      terms.singularLower,
                    ),
                    value: _customColorEnabled,
                    onChanged: (v) => setState(() => _customColorEnabled = v),
                  ),
                  if (_customColorEnabled) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Tooltip(
                          message: l10n.settingsAccentColorPickerTitle,
                          child: Semantics(
                            button: true,
                            label: l10n.settingsAccentColorPickerTitle,
                            child: GestureDetector(
                              onTap: _openCustomColorPicker,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      _previewColor() ??
                                      theme.colorScheme.surfaceContainerHighest,
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrismTextField(
                            controller: _colorHexController,
                            labelText: l10n.memberColorHexLabel,
                            hintText: '#AF8EE9',
                            prefixText: '#',
                            onChanged: (_) => setState(() {}),
                            suffix: PrismFieldIconButton(
                              icon: AppIcons.colorize,
                              tooltip: l10n.settingsAccentColorPickerTitle,
                              onPressed: _openCustomColorPicker,
                            ),
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

class _ProxyTagDraft {
  _ProxyTagDraft({String? prefix, String? suffix})
    : prefixController = TextEditingController(text: prefix ?? ''),
      suffixController = TextEditingController(text: suffix ?? '');

  factory _ProxyTagDraft.fromTag(ProxyTag tag) =>
      _ProxyTagDraft(prefix: tag.prefix, suffix: tag.suffix);

  final TextEditingController prefixController;
  final TextEditingController suffixController;

  void dispose() {
    prefixController.dispose();
    suffixController.dispose();
  }
}

class _ProxyTagsEditor extends StatelessWidget {
  const _ProxyTagsEditor({
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
  });

  final List<_ProxyTagDraft> drafts;
  final VoidCallback onAdd;
  final ValueChanged<_ProxyTagDraft> onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(AppIcons.tag, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.memberSectionProxyTags,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            PrismButton(
              label: l10n.memberProxyTagsAdd,
              icon: AppIcons.add,
              tone: PrismButtonTone.subtle,
              density: PrismControlDensity.compact,
              onPressed: onAdd,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.memberProxyTagsLocalDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (drafts.isEmpty)
          Text(
            l10n.memberProxyTagsEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final draft in drafts) ...[
            _ProxyTagDraftRow(
              draft: draft,
              onRemove: () => onRemove(draft),
              onChanged: onChanged,
            ),
            if (draft != drafts.last) const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ProxyTagDraftRow extends StatelessWidget {
  const _ProxyTagDraftRow({
    required this.draft,
    required this.onRemove,
    required this.onChanged,
  });

  final _ProxyTagDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final removeButton = PrismFieldIconButton(
      icon: AppIcons.deleteOutline,
      tooltip: l10n.memberProxyTagsRemove,
      semanticLabel: l10n.memberProxyTagsRemove,
      color: theme.colorScheme.error,
      onPressed: onRemove,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final prefixField = PrismTextField(
          controller: draft.prefixController,
          labelText: l10n.memberProxyTagPrefixLabel,
          hintText: l10n.memberProxyTagPrefixHint,
          onChanged: (_) => onChanged(),
          textInputAction: TextInputAction.next,
        );
        final suffixField = PrismTextField(
          controller: draft.suffixController,
          labelText: l10n.memberProxyTagSuffixLabel,
          hintText: l10n.memberProxyTagSuffixHint,
          onChanged: (_) => onChanged(),
        );

        if (compact) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: prefixField),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: removeButton,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              suffixField,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: prefixField),
            const SizedBox(width: 12),
            Expanded(child: suffixField),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: removeButton,
            ),
          ],
        );
      },
    );
  }
}

/// Read-only-looking row that reveals the cupertino date picker when tapped.
/// Shows the formatted birthday or a hint, a "hide year" toggle once a date
/// is set, and a clear button.
class _BirthdayField extends StatelessWidget {
  const _BirthdayField({
    required this.date,
    required this.hideYear,
    required this.onPick,
    required this.onClear,
    required this.onToggleHideYear,
  });

  final DateTime? date;
  final bool hideYear;
  final Future<void> Function(BuildContext anchorContext) onPick;
  final VoidCallback onClear;
  final ValueChanged<bool> onToggleHideYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();

    final effective = date;
    final displayText = effective == null
        ? l10n.memberBirthdayHint
        : (hideYear
              ? formatBirthdayDisplay(
                  DateTime(
                    birthdayNoYearSentinel,
                    effective.month,
                    effective.day,
                  ),
                  locale,
                )
              : formatBirthdayDisplay(effective, locale));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            l10n.memberBirthdayLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Builder(
          builder: (anchorContext) => InkWell(
            onTap: () => onPick(anchorContext),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    AppIcons.calendarTodayOutlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayText,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: effective == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (effective != null)
                    IconButton(
                      tooltip: l10n.memberBirthdayClear,
                      icon: Icon(
                        AppIcons.close,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: onClear,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (effective != null) ...[
          const SizedBox(height: 8),
          PrismSwitchRow(
            title: l10n.memberBirthdayHideYear,
            subtitle: l10n.memberBirthdayHideYearSubtitle,
            value: hideYear,
            onChanged: onToggleHideYear,
          ),
        ],
      ],
    );
  }
}
