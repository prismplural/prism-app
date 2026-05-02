import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

/// Sheet for composing a new board post or editing an existing one.
///
/// Use [ComposePostSheet.show] to present as a full-screen [PrismSheet].
///
/// Returns the created or updated [MemberBoardPost] on save, or `null` on
/// cancel.
class ComposePostSheet {
  // Utility class — not instantiable.
  ComposePostSheet._();

  /// Present the compose sheet.
  ///
  /// - [defaultTargetMemberId]: pre-selects a recipient headmate.
  /// - [defaultAudience]: initial audience (`'public'` or `'private'`).
  /// - [defaultTitle]: pre-fills the title field.
  /// - [defaultBody]: pre-fills the body field.
  /// - [editingPostId]: when non-null, loads the post for editing.
  ///
  /// Returns the saved [MemberBoardPost] on success, or `null` on cancel.
  static Future<MemberBoardPost?> show(
    BuildContext context, {
    String? defaultTargetMemberId,
    String defaultAudience = 'public',
    String? defaultTitle,
    String? defaultBody,
    String? editingPostId,
  }) {
    return PrismSheet.showFullScreen<MemberBoardPost?>(
      context: context,
      builder: (sheetCtx, scrollController) => _ComposePostSheetBody(
        defaultTargetMemberId: defaultTargetMemberId,
        defaultAudience: defaultAudience,
        defaultTitle: defaultTitle,
        defaultBody: defaultBody,
        editingPostId: editingPostId,
        scrollController: scrollController,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ComposePostSheetBody
// ---------------------------------------------------------------------------

class _ComposePostSheetBody extends ConsumerStatefulWidget {
  const _ComposePostSheetBody({
    required this.defaultTargetMemberId,
    required this.defaultAudience,
    required this.defaultTitle,
    required this.defaultBody,
    required this.editingPostId,
    required this.scrollController,
  });

  final String? defaultTargetMemberId;
  final String defaultAudience;
  final String? defaultTitle;
  final String? defaultBody;
  final String? editingPostId;
  final ScrollController scrollController;

  @override
  ConsumerState<_ComposePostSheetBody> createState() =>
      _ComposePostSheetBodyState();
}

class _ComposePostSheetBodyState
    extends ConsumerState<_ComposePostSheetBody> {
  late final TextEditingController _titleController;
  late final MarkdownEditingController _bodyController;
  late final FocusNode _bodyFocusNode;

  String _audience = 'public';
  String? _targetMemberId;

  bool _isSaving = false;
  bool _loaded = false;

  // Baseline values for dirty detection in edit mode.
  String _initialTitle = '';
  String _initialBody = '';
  String? _initialTargetMemberId;
  String _initialAudience = 'public';

  @override
  void initState() {
    super.initState();
    _audience = widget.defaultAudience;
    _initialAudience = widget.defaultAudience;
    _targetMemberId = widget.defaultTargetMemberId;
    _initialTargetMemberId = widget.defaultTargetMemberId;

    final title = widget.defaultTitle ?? '';
    final body = widget.defaultBody ?? '';
    _titleController = TextEditingController(text: title);
    _bodyController = MarkdownEditingController(text: body);
    _bodyFocusNode = FocusNode();
    _initialTitle = title;
    _initialBody = body;

    if (widget.editingPostId == null) _loaded = true;

    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);

    // For new posts, resolve who is posting before the user starts typing.
    if (widget.editingPostId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _initAuthorSelection();
      });
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTextChanged);
    _bodyController.removeListener(_onTextChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  bool get _isValid => _bodyController.text.trim().isNotEmpty;

  bool get _canSave => !_isSaving && _isValid;

  bool get _isDirty {
    if (widget.editingPostId == null) {
      // New post: dirty as soon as the user has typed anything.
      return _bodyController.text.trim().isNotEmpty ||
          _titleController.text.trim().isNotEmpty;
    }
    return _bodyController.text != _initialBody ||
        _titleController.text != _initialTitle ||
        _targetMemberId != _initialTargetMemberId ||
        _audience != _initialAudience;
  }

  // ---------------------------------------------------------------------------
  // Edit-mode prefill
  // ---------------------------------------------------------------------------

  Future<void> _loadExistingPost() async {
    final postId = widget.editingPostId;
    if (postId == null) return;

    final repo = ref.read(memberBoardPostsRepositoryProvider);
    final post = await repo.getPostById(postId);
    if (!mounted || post == null) return;

    setState(() {
      _audience = post.audience;
      _initialAudience = post.audience;
      _targetMemberId = post.targetMemberId;
      _initialTargetMemberId = post.targetMemberId;
      _bodyController.text = post.body;
      _initialBody = post.body;
      _titleController.text = post.title ?? '';
      _initialTitle = post.title ?? '';
      _loaded = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(memberBoardPostNotifierProvider.notifier);
      final speakingAsId = ref.read(speakingAsProvider);
      MemberBoardPost? result;

      if (widget.editingPostId != null) {
        await notifier.updatePost(
          id: widget.editingPostId!,
          targetMemberId: _targetMemberId,
          audience: _audience,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          body: _bodyController.text.trim(),
        );
        final repo = ref.read(memberBoardPostsRepositoryProvider);
        result = await repo.getPostById(widget.editingPostId!);
      } else {
        result = await notifier.createPost(
          targetMemberId: _targetMemberId,
          authorId: speakingAsId ?? '',
          audience: _audience,
          title: _titleController.text.trim().isEmpty
              ? null
              : _titleController.text.trim(),
          body: _bodyController.text.trim(),
        );
      }

      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Member picker
  // ---------------------------------------------------------------------------

  Future<void> _pickMember() async {
    final terminology = ref.read(terminologySettingProvider);
    final terms = resolveTerminology(
      context.l10n,
      terminology.term,
      customSingular: terminology.customSingular,
      customPlural: terminology.customPlural,
      useEnglish: terminology.useEnglish,
    );
    final members = ref.read(userVisibleMembersProvider).value ?? [];

    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      specialRows: [
        MemberSearchSpecialRow(
          rowKey: 'none',
          title: context.l10n.boardsComposeToNoHeadmate,
          leading: Icon(AppIcons.personOutline),
          result: const MemberSearchResultCleared(),
        ),
      ],
    );

    if (!mounted) return;
    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        setState(() => _targetMemberId = memberId);
      case MemberSearchResultCleared():
        setState(() {
          _targetMemberId = null;
          _audience = 'public';
        });
      case MemberSearchResultDismissed():
      case MemberSearchResultUnknown():
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Author selection
  // ---------------------------------------------------------------------------

  void _initAuthorSelection() {
    final sessions = ref.read(activeSessionsProvider).value ?? [];
    final fronterIds =
        sessions.map((s) => s.memberId).whereType<String>().toList();

    if (fronterIds.length == 1) {
      ref.read(speakingAsProvider.notifier).setMember(fronterIds.first);
      return;
    }

    if (fronterIds.length > 1) {
      final allMembers = ref.read(userVisibleMembersProvider).value ?? [];
      final coFronters =
          allMembers.where((m) => fronterIds.contains(m.id)).toList();
      if (coFronters.isNotEmpty && mounted) _showCoFronterPicker(coFronters);
    }
  }

  Future<void> _showCoFronterPicker(List<Member> coFronters) async {
    final l10n = context.l10n;
    final result = await PrismDialog.show<String?>(
      context: context,
      title: l10n.boardsComposeWhoIsPosting,
      builder: (dialogCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final member in coFronters)
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: MemberAvatar(
                memberName: member.name,
                emoji: member.emoji,
                avatarImageData: member.avatarImageData,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 36,
              ),
              title: Text(member.name),
              onTap: () => Navigator.of(dialogCtx).pop(member.id),
            ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    ref.read(speakingAsProvider.notifier).setMember(result);
  }

  Future<void> _pickAuthor() async {
    final terminology = ref.read(terminologySettingProvider);
    final terms = resolveTerminology(
      context.l10n,
      terminology.term,
      customSingular: terminology.customSingular,
      customPlural: terminology.customPlural,
      useEnglish: terminology.useEnglish,
    );
    final members = ref.read(userVisibleMembersProvider).value ?? [];
    final groups = readMemberSearchGroups(ref, members);
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      groups: groups,
    );
    if (!mounted) return;
    if (result is MemberSearchResultSelected) {
      ref.read(speakingAsProvider.notifier).setMember(result.memberId);
    }
  }

  // ---------------------------------------------------------------------------
  // Discard confirmation
  // ---------------------------------------------------------------------------

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    return PrismDialog.confirm(
      context: context,
      title: context.l10n.memberNoteDiscardTitle,
      message: context.l10n.memberNoteDiscardMessage,
      confirmLabel: context.l10n.memberNoteDiscardConfirm,
      destructive: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.editingPostId != null && !_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadExistingPost();
      });
    }

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isEditing = widget.editingPostId != null;

    _bodyController.updateTheme(context);
    // In edit mode the author is already set; only new posts require a selection.
    final speakingAs = ref.watch(speakingAsProvider);
    final canPost = _canSave && (isEditing || speakingAs != null);

    final targetMember = _targetMemberId != null
        ? ref.watch(memberByIdProvider(_targetMemberId!)).value
        : null;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return ListenableBuilder(
      listenable: Listenable.merge([_titleController, _bodyController]),
      builder: (context, _) => PopScope(
        canPop: !_isDirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldDiscard = await _confirmDiscard();
          if (shouldDiscard && context.mounted) Navigator.of(context).pop();
        },
        child: Column(
          children: [
            PrismSheetTopBar(
              title: isEditing
                  ? l10n.boardsComposeEditing
                  : l10n.boardsComposeNewPost,
              trailing: PrismGlassIconButton(
                icon: AppIcons.check,
                onPressed: canPost ? _save : null,
                enabled: canPost,
                isLoading: _isSaving,
                tooltip: l10n.boardsComposeSave,
                size: PrismTokens.topBarActionSize,
                tint: theme.colorScheme.primary,
                accentIcon: true,
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => _bodyFocusNode.requestFocus(),
                behavior: HitTestBehavior.translucent,
                child: ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    PrismTokens.pageHorizontalPadding + 8,
                    8,
                    PrismTokens.pageHorizontalPadding + 8,
                    16,
                  ),
                  children: [
                    // ── Recipient picker ─────────────────────────────────────
                    Semantics(
                      label: targetMember?.name ??
                          l10n.boardsComposeToNoHeadmate,
                      button: true,
                      child: InkWell(
                        onTap: _pickMember,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              if (targetMember != null)
                                MemberAvatar(
                                  avatarImageData: targetMember.avatarImageData,
                                  memberName: targetMember.name,
                                  emoji: targetMember.emoji,
                                  customColorEnabled:
                                      targetMember.customColorEnabled,
                                  customColorHex: targetMember.customColorHex,
                                  size: 20,
                                )
                              else
                                Icon(
                                  AppIcons.personOutline,
                                  size: 20,
                                  color: mutedColor,
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  targetMember?.name ??
                                      l10n.boardsComposeToNoHeadmate,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: targetMember != null
                                        ? null
                                        : mutedColor,
                                  ),
                                ),
                              ),
                              Icon(
                                AppIcons.expandMore,
                                size: 16,
                                color: mutedColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    PrismTextField(
                      controller: _titleController,
                      hintText: l10n.boardsComposeTitlePlaceholder,
                      fieldStyle: PrismTextFieldStyle.borderless,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      hintStyle: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    PrismTextField(
                      controller: _bodyController,
                      focusNode: _bodyFocusNode,
                      hintText: l10n.boardsComposeBodyPlaceholder,
                      fieldStyle: PrismTextFieldStyle.borderless,
                      style: theme.textTheme.bodyLarge,
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                      ),
                      minLines: 8,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      autofocus: !isEditing,
                    ),
                  ],
                ),
              ),
            ),
            _BottomToolbar(
              memberId: _targetMemberId,
              audience: _audience,
              isEditing: isEditing,
              onPickAuthor: _pickAuthor,
              onAudienceChanged: (v) => setState(() => _audience = v),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BottomToolbar
// ---------------------------------------------------------------------------

class _BottomToolbar extends ConsumerWidget {
  const _BottomToolbar({
    required this.memberId,
    required this.audience,
    required this.isEditing,
    required this.onPickAuthor,
    required this.onAudienceChanged,
  });

  final String? memberId;
  final String audience;
  final bool isEditing;
  final VoidCallback onPickAuthor;
  final ValueChanged<String> onAudienceChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    // Author avatar — only shown for new posts.
    final speakingAsId = isEditing ? null : ref.watch(speakingAsProvider);
    final authorMember = speakingAsId != null
        ? ref.watch(memberByIdProvider(speakingAsId)).value
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
          // Author avatar — tap to change who is posting.
          if (!isEditing) ...[
            Semantics(
              label: authorMember?.name ?? l10n.boardsComposeSelectAuthor,
              button: true,
              child: InkWell(
                onTap: onPickAuthor,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: authorMember != null
                      ? MemberAvatar(
                          avatarImageData: authorMember.avatarImageData,
                          memberName: authorMember.name,
                          emoji: authorMember.emoji,
                          customColorEnabled: authorMember.customColorEnabled,
                          customColorHex: authorMember.customColorHex,
                          size: 24,
                        )
                      : Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(
                            AppIcons.personOutline,
                            size: 14,
                            color: mutedColor,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'public',
                label: Text(l10n.boardsComposeAudienceEveryone),
              ),
              ButtonSegment(
                value: 'private',
                label: Text(l10n.boardsComposeAudiencePrivate),
              ),
            ],
            selected: {audience},
            onSelectionChanged: memberId != null
                ? (v) => onAudienceChanged(v.first)
                : null,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
