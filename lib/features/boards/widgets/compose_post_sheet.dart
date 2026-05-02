import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/chat/widgets/speaking_as_picker.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
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

// ---------------------------------------------------------------------------
// ComposePostSheet
//
// LOCKED API:
//   static Future<MemberBoardPost?> show(
//     BuildContext context, {
//     String? defaultTargetMemberId,
//     String defaultAudience = 'public',
//     String? defaultTitle,
//     String? defaultBody,
//     String? editingPostId,
//   })
// ---------------------------------------------------------------------------

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
    // Watch so the save button reacts when the user picks a "from" member.
    final speakingAs = ref.watch(speakingAsProvider);
    final canPost = _canSave && speakingAs != null;

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: PrismTokens.pageHorizontalPadding + 8,
                    vertical: 16,
                  ),
                  children: [
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
              onPickMember: _pickMember,
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
    required this.onPickMember,
    required this.onAudienceChanged,
  });

  final String? memberId;
  final String audience;
  final VoidCallback onPickMember;
  final ValueChanged<String> onAudienceChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    final member = memberId != null
        ? ref.watch(memberByIdProvider(memberId!)).value
        : null;

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: mutedColor.withValues(alpha: 0.6),
    );
    // Fixed width keeps "From" and "To" labels visually aligned.
    const double kLabelWidth = 36;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── From row ───────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: kLabelWidth,
                child: Text(
                  l10n.boardsComposeFromLabel,
                  style: labelStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: SpeakingAsPicker(autoSelectFirst: false),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ── To row ─────────────────────────────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: kLabelWidth,
                child: Text(
                  l10n.boardsComposeToLabel,
                  style: labelStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              _ToolbarChip(
                icon: AppIcons.personOutline,
                label: member?.name ?? l10n.boardsComposeToNoHeadmate,
                color: mutedColor,
                onTap: onPickMember,
                leading: member != null
                    ? MemberAvatar(
                        avatarImageData: member.avatarImageData,
                        memberName: member.name,
                        emoji: member.emoji,
                        customColorEnabled: member.customColorEnabled,
                        customColorHex: member.customColorHex,
                        size: 20,
                      )
                    : null,
                semanticLabel: member?.name ?? l10n.boardsComposeToNoHeadmate,
              ),
              const SizedBox(width: 8),
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ToolbarChip
// ---------------------------------------------------------------------------

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
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
