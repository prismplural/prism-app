import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/clipboard/app_clipboard.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/members/widgets/markdown_table_button.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/image_first_paste.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_mention_text_field.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_markdown_text.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

/// Create or edit a note without assuming the surrounding presentation.
///
/// The same editor can live inside a full-screen sheet, an inline desktop
/// detail pane, or eventually another host such as a separate desktop window.
class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({
    super.key,
    this.note,
    this.memberId,
    this.scrollController,
    this.controller,
    this.onSaved,
    this.onCancel,
  });

  final Note? note;
  final String? memberId;
  final ScrollController? scrollController;
  final NoteEditorController? controller;
  final ValueChanged<Note>? onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class NoteEditorController {
  _NoteEditorState? _state;

  bool get hasUnsavedChanges => _state?._hasUnsavedChanges ?? false;

  Future<bool> confirmDiscardIfNeeded() async {
    final state = _state;
    if (state == null || !state.mounted) return true;
    return state._confirmDiscard();
  }

  void _attach(_NoteEditorState state) {
    _state = state;
  }

  void _detach(_NoteEditorState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  late final TextEditingController _titleController;
  late final MarkdownEditingController _bodyController;
  late final FocusNode _bodyFocusNode;
  late DateTime _date;
  late String? _selectedMemberId;
  String? _colorHex;

  late final String _initialTitle;
  late final String _initialBody;
  late final DateTime _initialDate;
  late String? _initialMemberId;
  bool _memberWasEdited = false;
  bool _showPreview = false;
  // Isolates staged images to this editor instance.
  final String _editSessionId = const Uuid().v4();
  // Drives the add-image dialog when an image is pasted into the body, reusing
  // the floating image button's staging flow.
  final GlobalKey<MarkdownImageButtonState> _imageButtonKey = GlobalKey();

  bool get _isEditing => widget.note != null;

  /// Routes a pasted clipboard image into the add-image dialog; false lets the
  /// default text paste run.
  Future<bool> _handlePasteImage() async {
    final image = await ref.read(appClipboardReaderProvider).readImage();
    if (image == null || !mounted) return false;
    final button = _imageButtonKey.currentState;
    if (button == null) return false;
    await button.insertImageFromBytes(image.bytes);
    return true;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _initialTitle = widget.note?.title ?? '';
    _initialBody = widget.note?.body ?? '';
    _initialDate = widget.note?.date ?? DateTime.now();
    _initialMemberId = widget.note != null
        ? widget.note!.memberId
        : widget.memberId ?? ref.read(currentFronterProvider).value?.id;

    _titleController = TextEditingController(text: _initialTitle);
    _bodyController = MarkdownEditingController(text: _initialBody);
    _bodyFocusNode = FocusNode();
    _date = _initialDate;
    _selectedMemberId = _initialMemberId;
    _colorHex = widget.note?.colorHex;
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?._detach(this);
    widget.controller?._attach(this);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  bool get _isDirty =>
      _titleController.text != _initialTitle ||
      _bodyController.text != _initialBody ||
      _date != _initialDate ||
      _selectedMemberId != _initialMemberId;

  bool get _hasStagedImages {
    try {
      return ref
          .read(bioImageProcessorProvider(_editSessionId))
          .staged
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get _hasUnsavedChanges => _isDirty || _hasStagedImages;

  void _discardStagedImages() {
    try {
      ref.read(bioImageProcessorProvider(_editSessionId)).discardStaged();
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_isValid) return;
    // Commit any images staged via the image button before persisting.
    var failedTags = const <String>[];
    try {
      failedTags = await ref
          .read(bioImageProcessorProvider(_editSessionId))
          .commitStaged();
    } catch (_) {}
    if (mounted && failedTags.isNotEmpty) {
      PrismToast.error(context, message: context.l10n.mediaSomeImagesNotSaved);
    }

    final notifier = ref.read(noteNotifierProvider.notifier);
    final savedNote = _isEditing
        ? await notifier.updateNote(
            widget.note!.copyWith(
              title: _titleController.text.trim(),
              body: _bodyController.text.trim(),
              colorHex: _colorHex,
              memberId: _selectedMemberId,
              date: _date,
            ),
          )
        : await notifier.createNote(
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            colorHex: _colorHex,
            memberId: _selectedMemberId,
            date: _date,
          );

    if (!mounted || savedNote == null) return;
    final onSaved = widget.onSaved;
    if (onSaved != null) {
      onSaved(savedNote);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate(BuildContext anchorContext) async {
    final picked = await showPrismDatePicker(
      context: context,
      anchorContext: anchorContext,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickMember(List<Member> members) async {
    final terminology = readTerminology(context, ref);
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terminology.plural,
      title: context.l10n.memberNoteChooseHeadmate(terminology.singular),
      groups: readMemberSearchGroups(ref, members),
      specialRows: [
        MemberSearchSpecialRow(
          rowKey: 'none',
          title: context.l10n.memberSelectNone,
          leading: Icon(AppIcons.removeCircleOutline),
          result: const MemberSearchResultCleared(),
        ),
      ],
    );
    if (!mounted) return;

    setState(() {
      switch (result) {
        case MemberSearchResultSelected(:final memberId):
          _memberWasEdited = true;
          _selectedMemberId = memberId;
        case MemberSearchResultCleared():
          _memberWasEdited = true;
          _selectedMemberId = null;
        case MemberSearchResultDismissed():
        case MemberSearchResultUnknown():
          break;
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final shouldDiscard = await PrismDialog.confirm(
      context: context,
      title: context.l10n.memberNoteDiscardTitle,
      message: context.l10n.memberNoteDiscardMessage,
      confirmLabel: context.l10n.memberNoteDiscardConfirm,
      destructive: true,
    );
    if (shouldDiscard) _discardStagedImages();
    return shouldDiscard;
  }

  Future<void> _requestClose() async {
    final onCancel = widget.onCancel;
    if (onCancel != null) {
      final shouldDiscard = await _confirmDiscard();
      if (!shouldDiscard || !mounted) return;
      onCancel();
    } else {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final memberCandidates =
        ref.watch(userVisibleMemberListProvider).value ?? const <Member>[];
    _bodyController.updateTheme(context);
    watchMemberSearchGroupSources(ref);

    // Keep staged images alive across preview toggles.
    try {
      ref.watch(bioImageProcessorProvider(_editSessionId));
    } catch (_) {}

    if (!_isEditing && widget.memberId == null) {
      ref.listen(currentFronterProvider, (_, next) {
        final currentFronter = next.value;
        if (_memberWasEdited ||
            _selectedMemberId != null ||
            currentFronter == null) {
          return;
        }
        setState(() {
          _selectedMemberId = currentFronter.id;
          _initialMemberId = currentFronter.id;
        });
      });
    }

    return Material(
      color: Colors.transparent,
      child: ListenableBuilder(
        listenable: Listenable.merge([_titleController, _bodyController]),
        builder: (context, _) => CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(_requestClose()),
          },
          child: UnsavedChangesGuard<void>(
            hasUnsavedChanges: _hasUnsavedChanges,
            onDiscard: _discardStagedImages,
            discardResult: null,
            // Inline panes are closed by their parent controller.
            isActive: widget.onCancel == null,
            child: Column(
              children: [
                PrismSheetTopBar(
                  title: l10n.memberNoteTitle,
                  leading: PrismGlassIconButton(
                    icon: AppIcons.close,
                    size: PrismTokens.topBarActionSize,
                    onPressed: _requestClose,
                    tooltip: l10n.close,
                    semanticLabel: l10n.close,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PrismGlassIconButton(
                        icon: _showPreview ? AppIcons.edit : AppIcons.preview,
                        onPressed: () =>
                            setState(() => _showPreview = !_showPreview),
                        tooltip: _showPreview
                            ? l10n.edit
                            : l10n.memberNotePreviewTooltip,
                        size: PrismTokens.topBarActionSize,
                      ),
                      const SizedBox(width: 4),
                      PrismGlassIconButton(
                        icon: AppIcons.check,
                        onPressed: _isValid ? _save : null,
                        enabled: _isValid,
                        tooltip: l10n.memberSaveNoteTooltip,
                        size: PrismTokens.topBarActionSize,
                        tint: theme.colorScheme.primary,
                        accentIcon: true,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _bodyFocusNode.requestFocus(),
                        behavior: HitTestBehavior.translucent,
                        child: ListView(
                          controller: widget.scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: PrismTokens.pageHorizontalPadding + 8,
                            vertical: 16,
                          ),
                          children: _showPreview
                              ? _buildPreviewContent(theme, l10n)
                              : _buildEditorContent(theme, l10n),
                        ),
                      ),
                      if (!_showPreview)
                        Positioned(
                          right: 16,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MarkdownTableButton(controller: _bodyController),
                              const SizedBox(width: 4),
                              MarkdownImageButton(
                                key: _imageButtonKey,
                                controller: _bodyController,
                                sessionId: _editSessionId,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                _BottomToolbar(
                  date: _date,
                  memberId: _selectedMemberId,
                  onPickDate: _pickDate,
                  onPickMember: () => unawaited(_pickMember(memberCandidates)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPreviewContent(ThemeData theme, AppLocalizations l10n) {
    return [
      if (_titleController.text.trim().isNotEmpty) ...[
        Text(
          _titleController.text.trim(),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_bodyController.text.trim().isEmpty)
        Text(
          l10n.memberNoteBodyHint,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        )
      else
        PrismMarkdownText(
          data: _bodyController.text,
          enabled: true,
          baseStyle: theme.textTheme.bodyLarge,
          editSessionId: _editSessionId,
          mentionsInteractive: false,
        ),
    ];
  }

  List<Widget> _buildEditorContent(ThemeData theme, AppLocalizations l10n) {
    return [
      PrismTextField(
        controller: _titleController,
        hintText: l10n.memberNoteTitleHint,
        fieldStyle: PrismTextFieldStyle.borderless,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        hintStyle: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        autofocus: !_isEditing,
      ),
      const SizedBox(height: 8),
      ImagePasteRegion(
        onPasteImage: _handlePasteImage,
        builder: (context, contextMenuBuilder) => MemberMentionTextField(
          controller: _bodyController,
          focusNode: _bodyFocusNode,
          hintText: l10n.memberNoteBodyHint,
          fieldStyle: PrismTextFieldStyle.borderless,
          style: theme.textTheme.bodyLarge,
          hintStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          minLines: 12,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          contextMenuBuilder: contextMenuBuilder,
        ),
      ),
    ];
  }
}

/// Bottom toolbar with date and member chips, pinned above keyboard.
class _BottomToolbar extends ConsumerWidget {
  const _BottomToolbar({
    required this.date,
    required this.memberId,
    required this.onPickDate,
    required this.onPickMember,
  });

  final DateTime date;
  final String? memberId;
  final void Function(BuildContext anchorContext) onPickDate;
  final VoidCallback onPickMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final dateFormat = DateFormat.MMMd(context.dateLocale);
    final settingsAsync = ref.watch(systemSettingsProvider);
    final bottomInset = modalBottomInsetOf(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    // Resolve member if set.
    final member = memberId != null
        ? ref.watch(activeMemberByIdProvider(memberId!)).value
        : null;

    return Container(
      padding: EdgeInsets.only(
        left: PrismTokens.pageHorizontalPadding + 8,
        right: PrismTokens.pageHorizontalPadding + 8,
        top: 8,
        bottom: 8 + bottomInset,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Builder(
            builder: (anchorContext) => _ToolbarChip(
              icon: AppIcons.calendarTodayOutlined,
              label: dateFormat.format(date),
              color: mutedColor,
              onTap: () => onPickDate(anchorContext),
              semanticLabel: l10n.memberNoteDateSemantics(
                DateFormat.yMMMd(context.dateLocale).format(date),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (settingsAsync.hasValue)
            _MemberToolbarChip(
              member: member,
              settings: settingsAsync.requireValue,
              mutedColor: mutedColor,
              onPickMember: onPickMember,
            ),
        ],
      ),
    );
  }
}

class _MemberToolbarChip extends StatelessWidget {
  const _MemberToolbarChip({
    required this.member,
    required this.settings,
    required this.mutedColor,
    required this.onPickMember,
  });

  final Member? member;
  final SystemSettings settings;
  final Color mutedColor;
  final VoidCallback onPickMember;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final terminology = resolveTerminology(
      l10n,
      settings.terminology,
      customSingular: settings.customTerminology,
      customPlural: settings.customPluralTerminology,
      useEnglish: settings.terminologyUseEnglish,
    );

    final selectedMember = member;
    if (selectedMember != null) {
      return _ToolbarChip(
        icon: null,
        label: selectedMember.name,
        color: mutedColor,
        onTap: onPickMember,
        leading: MemberAvatar(
          avatarImageData: selectedMember.avatarImageData,
          memberId: selectedMember.id,
          deferAvatarLookup: true,
          memberName: selectedMember.name,
          emoji: selectedMember.emoji,
          customColorEnabled: selectedMember.customColorEnabled,
          customColorHex: selectedMember.customColorHex,
          size: 20,
        ),
        semanticLabel: l10n.memberNoteMemberSemantics(
          terminology.singular,
          selectedMember.name,
        ),
      );
    }

    return _ToolbarChip(
      icon: AppIcons.personOutline,
      label: l10n.memberNoteAddHeadmate(terminology.singularLower),
      color: mutedColor.withValues(alpha: 0.6),
      onTap: onPickMember,
      semanticLabel: l10n.memberNoteNoHeadmateSemantics(
        terminology.singularLower,
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.leading,
    this.semanticLabel,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? leading;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
