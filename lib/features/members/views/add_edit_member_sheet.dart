import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/birthday.dart';
import 'package:prism_plurality/features/members/utils/proxy_tag.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_push_new_member_dialog.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/avatar_image_picker.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
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
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/features/members/widgets/member_profile_header_editor.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';
import 'package:uuid/uuid.dart';

enum _MemberEditTab { edit, style }

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
  late final TextEditingController _nameStyleColorHexController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _pluralkitDisplayNameController;
  late final CustomFieldsEditorController _customFieldsEditorController;
  final List<_ProxyTagDraft> _proxyTagDrafts = [];

  bool _isAdmin = false;
  bool _markdownEnabled = true;
  bool _customColorEnabled = false;
  bool _isAlwaysFronting = false;
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
  _MemberEditTab _tab = _MemberEditTab.edit;
  late final String _initialName;
  late final String _initialPronouns;
  late final String _initialBio;
  late final String _initialEmoji;
  late final String _initialAge;
  late final String _initialColorHex;
  late final String _initialNameStyleColorHex;
  late final String _initialDisplayName;
  late final String _initialPluralKitDisplayName;
  late final String? _initialProxyTagsJson;
  late final bool _initialIsAdmin;
  late final bool _initialMarkdownEnabled;
  late final bool _initialCustomColorEnabled;
  late final bool _initialIsAlwaysFronting;
  late final Uint8List? _initialAvatarImageData;
  late final MemberProfileHeaderSource _initialProfileHeaderSource;
  late final MemberProfileHeaderLayout _initialProfileHeaderLayout;
  late final bool _initialProfileHeaderVisible;
  late final MemberNameFont _initialNameStyleFont;
  late final bool _initialNameStyleBold;
  late final bool _initialNameStyleItalic;
  late final MemberNameColorMode _initialNameStyleColorMode;
  late final String? _initialNameStyleColorHexValue;
  late final Uint8List? _initialProfileHeaderImageData;
  late final DateTime? _initialBirthday;
  late final bool _initialBirthdayHideYear;

  /// Parsed birthday (null when unset). When [_birthdayHideYear] is true the
  /// year is irrelevant for display; the wire format will substitute the PK
  /// `0004` sentinel on save.
  DateTime? _birthday;
  bool _birthdayHideYear = false;

  bool get _isDirty =>
      _nameController.text != _initialName ||
      _pronounsController.text != _initialPronouns ||
      _bioController.text != _initialBio ||
      _emojiController.text != _initialEmoji ||
      _ageController.text != _initialAge ||
      _colorHexController.text != _initialColorHex ||
      _nameStyleColorHexController.text != _initialNameStyleColorHex ||
      _displayNameController.text != _initialDisplayName ||
      _pluralkitDisplayNameController.text != _initialPluralKitDisplayName ||
      _proxyTagsJson() != _initialProxyTagsJson ||
      _isAdmin != _initialIsAdmin ||
      _markdownEnabled != _initialMarkdownEnabled ||
      _customColorEnabled != _initialCustomColorEnabled ||
      _isAlwaysFronting != _initialIsAlwaysFronting ||
      !_bytesEqual(_avatarImageData, _initialAvatarImageData) ||
      _profileHeaderSource != _initialProfileHeaderSource ||
      _profileHeaderLayout != _initialProfileHeaderLayout ||
      _profileHeaderVisible != _initialProfileHeaderVisible ||
      _nameStyleFont != _initialNameStyleFont ||
      _nameStyleBold != _initialNameStyleBold ||
      _nameStyleItalic != _initialNameStyleItalic ||
      _nameStyleColorMode != _initialNameStyleColorMode ||
      _nameStyleColorHex != _initialNameStyleColorHexValue ||
      !_bytesEqual(_profileHeaderImageData, _initialProfileHeaderImageData) ||
      _birthday != _initialBirthday ||
      _birthdayHideYear != _initialBirthdayHideYear;

  bool get _showPluralKitDisplayNameField {
    final member = widget.member;
    if (member != null) {
      if (_hasText(member.pluralkitUuid) ||
          _hasText(member.pluralkitId) ||
          _hasText(member.pluralkitDisplayName)) {
        return true;
      }
    }
    // For new or unlinked members: show the field when PK push is on, so the
    // value can ride along with the auto-push that creates the PK member.
    // Pull-only is excluded — a local value would just be clobbered on first
    // pull, which would surprise the user.
    final pkState = ref.watch(pluralKitSyncProvider);
    if (!pkState.isConnected) return false;
    return ref.watch(pkSyncDirectionProvider).pushEnabled;
  }

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
    _nameStyleColorHexController = TextEditingController(
      text: _normalizeColorHexForField(m?.nameStyleColorHex),
    );
    _displayNameController = TextEditingController(text: m?.displayName ?? '');
    _pluralkitDisplayNameController = TextEditingController(
      text: m?.pluralkitDisplayName ?? '',
    );
    _customFieldsEditorController = CustomFieldsEditorController();
    _proxyTagDrafts
      ..clear()
      ..addAll(parseProxyTags(m?.proxyTagsJson).map(_ProxyTagDraft.fromTag));
    final parsedBirthday = parseBirthday(m?.birthday);
    _birthday = parsedBirthday;
    _birthdayHideYear =
        parsedBirthday != null && isBirthdayYearHidden(parsedBirthday);
    _isAdmin = m?.isAdmin ?? false;
    // Match the drift column default — new members get markdown on; existing
    // members reflect whatever they have on disk.
    _markdownEnabled = m?.markdownEnabled ?? true;
    _customColorEnabled = m?.customColorEnabled ?? false;
    _isAlwaysFronting = m?.isAlwaysFronting ?? false;
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
    _initialName = _nameController.text;
    _initialPronouns = _pronounsController.text;
    _initialBio = _bioController.text;
    _initialEmoji = _emojiController.text;
    _initialAge = _ageController.text;
    _initialColorHex = _colorHexController.text;
    _initialNameStyleColorHex = _nameStyleColorHexController.text;
    _initialDisplayName = _displayNameController.text;
    _initialPluralKitDisplayName = _pluralkitDisplayNameController.text;
    _initialProxyTagsJson = _proxyTagsJson();
    _initialIsAdmin = _isAdmin;
    _initialMarkdownEnabled = _markdownEnabled;
    _initialCustomColorEnabled = _customColorEnabled;
    _initialIsAlwaysFronting = _isAlwaysFronting;
    _initialAvatarImageData = _copyBytes(_avatarImageData);
    _initialProfileHeaderSource = _profileHeaderSource;
    _initialProfileHeaderLayout = _profileHeaderLayout;
    _initialProfileHeaderVisible = _profileHeaderVisible;
    _initialNameStyleFont = _nameStyleFont;
    _initialNameStyleBold = _nameStyleBold;
    _initialNameStyleItalic = _nameStyleItalic;
    _initialNameStyleColorMode = _nameStyleColorMode;
    _initialNameStyleColorHexValue = _nameStyleColorHex;
    _initialProfileHeaderImageData = _copyBytes(_profileHeaderImageData);
    _initialBirthday = _birthday;
    _initialBirthdayHideYear = _birthdayHideYear;
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
    _nameStyleColorHexController.dispose();
    _displayNameController.dispose();
    _pluralkitDisplayNameController.dispose();
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
    final pluralkitDisplayName = _pluralkitDisplayNameController.text.trim();
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
          pluralkitDisplayName: pluralkitDisplayName.isNotEmpty
              ? pluralkitDisplayName
              : null,
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

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  String _colorToFieldHex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return value.toRadixString(16).padLeft(6, '0').toUpperCase();
  }

  Uint8List? _copyBytes(Uint8List? bytes) =>
      bytes == null ? null : Uint8List.fromList(bytes);

  bool _bytesEqual(Uint8List? left, Uint8List? right) {
    if (left == null || right == null) return left == right;
    return listEquals(left, right);
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
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _birthday = picked);
    }
  }

  Color? _previewNameStyleColor() {
    if (_nameStyleColorMode != MemberNameColorMode.custom) return null;
    final hex = _nameStyleColorHexController.text.trim();
    if (hex.isEmpty) return null;
    try {
      return AppColors.fromHex(hex);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openNameStyleColorPicker() async {
    var pickerColor = _previewNameStyleColor() ?? const Color(0xFFB498C2);

    await PrismDialog.show<void>(
      context: context,
      title: context.l10n.memberNameStyleColorLabel,
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
            final hex = _colorToFieldHex(pickerColor);
            setState(() {
              _nameStyleColorHexController.text = hex;
              _nameStyleColorHex = hex;
            });
          },
          label: context.l10n.settingsAccentColorSelect,
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }

  Future<void> _openBioEditor() async {
    final result = await showFullScreenMarkdownEditor(
      context: context,
      title: context.l10n.memberBioLabel,
      initialText: _bioController.text,
      hintText: context.l10n.memberBioHint,
    );
    if (result != null && mounted) {
      setState(() => _bioController.text = result);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    await _customFieldsEditorController.savePendingValues();

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
    final nameStyleColorHex = _nameStyleColorMode == MemberNameColorMode.custom
        ? _nameStyleColorHexController.text.trim().isNotEmpty
              ? _nameStyleColorHexController.text.trim()
              : null
        : null;
    final displayName = _displayNameController.text.trim();
    final pluralkitDisplayName = _pluralkitDisplayNameController.text.trim();
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
          pluralkitDisplayName: pluralkitDisplayName.isNotEmpty
              ? pluralkitDisplayName
              : null,
          birthday: birthdayWire,
          proxyTagsJson: proxyTagsJson,
          isAlwaysFronting: _isAlwaysFronting,
          profileHeaderSource: _profileHeaderSource,
          profileHeaderLayout: _profileHeaderLayout,
          profileHeaderVisible: _profileHeaderVisible,
          nameStyleFont: _nameStyleFont,
          nameStyleBold: _nameStyleBold,
          nameStyleItalic: _nameStyleItalic,
          nameStyleColorMode: _nameStyleColorMode,
          nameStyleColorHex: nameStyleColorHex,
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
          isAlwaysFronting: _isAlwaysFronting,
          displayName: displayName.isNotEmpty ? displayName : null,
          pluralkitDisplayName: pluralkitDisplayName.isNotEmpty
              ? pluralkitDisplayName
              : null,
          birthday: birthdayWire,
          proxyTagsJson: proxyTagsJson,
          profileHeaderSource: _profileHeaderSource,
          profileHeaderLayout: _profileHeaderLayout,
          profileHeaderVisible: _profileHeaderVisible,
          nameStyleFont: _nameStyleFont,
          nameStyleBold: _nameStyleBold,
          nameStyleItalic: _nameStyleItalic,
          nameStyleColorMode: _nameStyleColorMode,
          nameStyleColorHex: nameStyleColorHex,
          profileHeaderImageData: _profileHeaderImageData,
        );
      }

      _saved = true;

      // On member creation (NOT edit), if PluralKit is paired-and-ready but
      // general push sync is disabled, prompt the user to one-shot push this
      // new member without changing their global sync settings. The dialog
      // handles its own success/error feedback; we always close the sheet
      // afterwards regardless of dialog outcome (push / keep-local / dismiss).
      if (!widget.isEditing && mounted) {
        // Await the persisted PK settings before reading the gate. Each of
        // these notifiers loads from the DAO asynchronously on first read
        // (fire-and-forget in build()), so a synchronous read on the first
        // member creation after launch could see defaults and either prompt
        // when it shouldn't or skip when it should.
        await Future.wait<void>([
          ref.read(pluralKitSyncServiceProvider).loadState(),
          ref.read(pkSyncDirectionProvider.notifier).load(),
          ref.read(pkSyncModeProvider.notifier).load(),
        ]);
        if (!mounted) return;
        final pkSyncState = ref.read(pluralKitSyncProvider);
        final pushEnabled = ref.read(pkSyncDirectionProvider).pushEnabled;
        final mode = ref.read(pkSyncModeProvider);
        final pushDisabled =
            !pushEnabled || mode == PkSyncMode.liveFrontsOnly;
        if (pkSyncState.canAutoSync && pushDisabled) {
          await showPkPushNewMemberDialog(
            context,
            memberId: _memberId,
            memberName: name,
          );
        }
      }

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

    return ListenableBuilder(
      listenable: Listenable.merge([
        _nameController,
        _pronounsController,
        _bioController,
        _emojiController,
        _ageController,
        _colorHexController,
        _nameStyleColorHexController,
        _displayNameController,
        for (final draft in _proxyTagDrafts) ...[
          draft.prefixController,
          draft.suffixController,
        ],
      ]),
      builder: (context, _) => UnsavedChangesGuard<bool>(
        hasUnsavedChanges: _isDirty,
        child: SafeArea(
          child: Column(
            children: [
              PrismSheetTopBar(
                title: widget.isEditing
                    ? context.l10n.terminologyEditItem(terms.singular)
                    : context.l10n.terminologyNewItem(terms.singular),
                titleWidget: PrismSegmentedControl<_MemberEditTab>(
                  selected: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                  segments: [
                    PrismSegment(
                      value: _MemberEditTab.edit,
                      label: l10n.memberEditTabEdit,
                    ),
                    PrismSegment(
                      value: _MemberEditTab.style,
                      label: l10n.memberEditTabStyle,
                    ),
                  ],
                ),
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
                      if (_tab == _MemberEditTab.style) ...[
                        const SizedBox(height: 16),
                        MemberProfileHeaderEditor(
                          member: _previewMember(),
                          source: _profileHeaderSource,
                          layout: _profileHeaderLayout,
                          visible: _profileHeaderVisible,
                          prismHeaderImageData: _profileHeaderImageData,
                          pluralKitHeaderImageData:
                              widget.member?.pkBannerImageData,
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
                          showSectionWrapper: false,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          l10n.memberNameStyleDialogTitle,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontFamily:
                                theme.textTheme.headlineLarge?.fontFamily,
                            fontWeight: FontWeight.w700,
                            letterSpacing:
                                theme.textTheme.headlineLarge?.letterSpacing ??
                                0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.memberNameStyleFontLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        PrismSegmentedControl<MemberNameFont>(
                          selected: _nameStyleFont,
                          onChanged: (font) =>
                              setState(() => _nameStyleFont = font),
                          segments: [
                            PrismSegment(
                              value: MemberNameFont.standard,
                              label: l10n.memberNameStyleFontDefault,
                            ),
                            PrismSegment(
                              value: MemberNameFont.display,
                              label: l10n.memberNameStyleFontDisplay,
                            ),
                            PrismSegment(
                              value: MemberNameFont.serif,
                              label: l10n.memberNameStyleFontSerif,
                            ),
                            PrismSegment(
                              value: MemberNameFont.mono,
                              label: l10n.memberNameStyleFontMono,
                            ),
                            PrismSegment(
                              value: MemberNameFont.rounded,
                              label: l10n.memberNameStyleFontRounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.memberNameStyleStyleLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            PrismButton(
                              label: l10n.memberNameStyleBold,
                              icon: AppIcons.textBold,
                              tone: _nameStyleBold
                                  ? PrismButtonTone.filled
                                  : PrismButtonTone.subtle,
                              density: PrismControlDensity.compact,
                              onPressed: () => setState(
                                () => _nameStyleBold = !_nameStyleBold,
                              ),
                            ),
                            PrismButton(
                              label: l10n.memberNameStyleItalic,
                              icon: AppIcons.textItalic,
                              tone: _nameStyleItalic
                                  ? PrismButtonTone.filled
                                  : PrismButtonTone.subtle,
                              density: PrismControlDensity.compact,
                              onPressed: () => setState(
                                () => _nameStyleItalic = !_nameStyleItalic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.memberNameStyleColorLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        PrismSegmentedControl<MemberNameColorMode>(
                          selected: _nameStyleColorMode,
                          onChanged: (mode) => setState(() {
                            _nameStyleColorMode = mode;
                            if (mode == MemberNameColorMode.custom &&
                                _nameStyleColorHex == null) {
                              final seeded = _colorToFieldHex(
                                Theme.of(context).colorScheme.primary,
                              );
                              _nameStyleColorHex = seeded;
                              _nameStyleColorHexController.text = seeded;
                            }
                          }),
                          segments: [
                            PrismSegment(
                              value: MemberNameColorMode.standard,
                              label: l10n.memberNameStyleColorDefault,
                            ),
                            PrismSegment(
                              value: MemberNameColorMode.accent,
                              label: l10n.memberNameStyleColorAccent,
                            ),
                            PrismSegment(
                              value: MemberNameColorMode.custom,
                              label: l10n.memberNameStyleColorCustom,
                            ),
                          ],
                        ),
                        if (_nameStyleColorMode ==
                            MemberNameColorMode.custom) ...[
                          const SizedBox(height: 12),
                          Text(
                            l10n.memberColorHexLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: PrismTextField(
                                    controller: _nameStyleColorHexController,
                                    hintText: '#B498C2',
                                    prefixText: '#',
                                    onChanged: (v) => setState(
                                      () => _nameStyleColorHex =
                                          v.trim().isNotEmpty ? v.trim() : null,
                                    ),
                                    suffix: PrismFieldIconButton(
                                      icon: AppIcons.colorize,
                                      tooltip: l10n.memberNameStyleColorLabel,
                                      onPressed: _openNameStyleColorPicker,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9a-fA-F]'),
                                      ),
                                      LengthLimitingTextInputFormatter(6),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                AspectRatio(
                                  aspectRatio: 1,
                                  child: Tooltip(
                                    message: l10n.memberNameStyleColorLabel,
                                    child: Semantics(
                                      button: true,
                                      label: l10n.memberNameStyleColorLabel,
                                      child: GestureDetector(
                                        onTap: _openNameStyleColorPicker,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                _previewNameStyleColor() ??
                                                theme
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            border: Border.all(
                                              color: theme.colorScheme.outline,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        Text(
                          l10n.memberAccentColorSectionTitle,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontFamily:
                                theme.textTheme.headlineLarge?.fontFamily,
                            fontWeight: FontWeight.w700,
                            letterSpacing:
                                theme.textTheme.headlineLarge?.letterSpacing ??
                                0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        PrismSwitchRow(
                          title: l10n.memberCustomColorTitle,
                          subtitle: l10n.memberCustomColorSubtitle(
                            terms.singularLower,
                          ),
                          value: _customColorEnabled,
                          onChanged: (v) =>
                              setState(() => _customColorEnabled = v),
                        ),
                        if (_customColorEnabled) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.memberColorHexLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: PrismTextField(
                                    controller: _colorHexController,
                                    hintText: '#AF8EE9',
                                    prefixText: '#',
                                    onChanged: (_) => setState(() {}),
                                    suffix: PrismFieldIconButton(
                                      icon: AppIcons.colorize,
                                      tooltip:
                                          l10n.settingsAccentColorPickerTitle,
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
                                const SizedBox(width: 12),
                                AspectRatio(
                                  aspectRatio: 1,
                                  child: Tooltip(
                                    message:
                                        l10n.settingsAccentColorPickerTitle,
                                    child: Semantics(
                                      button: true,
                                      label:
                                          l10n.settingsAccentColorPickerTitle,
                                      child: GestureDetector(
                                        onTap: _openCustomColorPicker,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                _previewColor() ??
                                                theme
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                            border: Border.all(
                                              color: theme.colorScheme.outline,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
                      if (_tab == _MemberEditTab.edit) ...[
                        PrismPickerTextFieldRow(
                          pickerLabel:
                              context.l10n.onboardingAddMemberFieldEmoji,
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
                        if (_showPluralKitDisplayNameField) ...[
                          const SizedBox(height: 16),
                          PrismTextField(
                            controller: _pluralkitDisplayNameController,
                            labelText: l10n.memberPluralKitDisplayNameLabel,
                            hintText: l10n.memberPluralKitDisplayNameHint,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          l10n.memberEditSectionAbout,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontFamily:
                                theme.textTheme.headlineLarge?.fontFamily,
                            fontWeight: FontWeight.w700,
                            letterSpacing:
                                theme.textTheme.headlineLarge?.letterSpacing ??
                                0,
                          ),
                        ),
                        const SizedBox(height: 12),

                        PrismTextField(
                          controller: _pronounsController,
                          labelText: l10n.memberPronounsLabel,
                          hintText: l10n.memberPronounsHint,
                        ),
                        const SizedBox(height: 16),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: PrismTextField(
                                controller: _ageController,
                                labelText: l10n.memberAgeLabel,
                                hintText: l10n.memberAgeHint,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _BirthdayField(
                                date: _birthday,
                                hideYear: _birthdayHideYear,
                                onPick: _pickBirthday,
                                onClear: () => setState(() => _birthday = null),
                                onToggleHideYear: (v) =>
                                    setState(() => _birthdayHideYear = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.memberBioLabel,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            PrismIconButton(
                              icon: AppIcons.edit,
                              tooltip: l10n.memberBioEditorTooltip,
                              onPressed: _openBioEditor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        PrismTextField(
                          controller: _bioController,
                          hintText: l10n.memberBioHint,
                          maxLines: 6,
                          minLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),

                        const SizedBox(height: 24),
                        _ProxyTagsEditor(
                          drafts: _proxyTagDrafts,
                          onAdd: _addProxyTag,
                          onRemove: _removeProxyTag,
                          onChanged: () => setState(() {}),
                        ),

                        const SizedBox(height: 24),
                        Text(
                          l10n.memberEditSectionSettings,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontFamily:
                                theme.textTheme.headlineLarge?.fontFamily,
                            fontWeight: FontWeight.w700,
                            letterSpacing:
                                theme.textTheme.headlineLarge?.letterSpacing ??
                                0,
                          ),
                        ),
                        const SizedBox(height: 12),

                        PrismSwitchRow(
                          title: l10n.memberMarkdownTitle,
                          subtitle: l10n.memberMarkdownSubtitle,
                          value: _markdownEnabled,
                          onChanged: (v) =>
                              setState(() => _markdownEnabled = v),
                        ),
                        const SizedBox(height: 8),

                        PrismSwitchRow(
                          title: l10n.memberAdminTitle,
                          subtitle: l10n.memberAdminSubtitle,
                          value: _isAdmin,
                          onChanged: (v) => setState(() => _isAdmin = v),
                        ),
                        const SizedBox(height: 8),

                        PrismSwitchRow(
                          title: l10n.memberAlwaysFrontingTitle,
                          subtitle: l10n.memberAlwaysFrontingSubtitle(
                            terms.singularLower,
                          ),
                          value: _isAlwaysFronting,
                          onChanged: (v) =>
                              setState(() => _isAlwaysFronting = v),
                        ),

                        CustomFieldsEditor(
                          memberId: _memberId,
                          controller: _customFieldsEditorController,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
