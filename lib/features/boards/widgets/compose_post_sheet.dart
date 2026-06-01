import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/bio_image_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/markdown_image_button.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/features/members/widgets/markdown_table_button.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

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

class _ComposePostSheetBodyState extends ConsumerState<_ComposePostSheetBody> {
  late final TextEditingController _titleController;
  late final MarkdownEditingController _bodyController;
  late final FocusNode _bodyFocusNode;
  final String _editSessionId = const Uuid().v4();

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
      var failedTags = const <String>[];
      try {
        failedTags = await ref
            .read(bioImageProcessorProvider(_editSessionId))
            .commitStaged();
      } catch (_) {}
      if (mounted && failedTags.isNotEmpty) {
        PrismToast.error(
          context,
          message: context.l10n.mediaSomeImagesNotSaved,
        );
      }

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

  Future<void> _initAuthorSelection() async {
    // Await the preference so a cold first read never misses "ask each time".
    ComposerDefaultMember mode;
    try {
      mode = await ref.read(composerDefaultMemberProvider.future);
    } catch (_) {
      mode = ComposerDefaultMember.defaultValue;
    }
    if (!mounted) return;
    final sessions = ref.read(activeSessionsProvider).value ?? [];
    final fronterIds = sessions
        .map((s) => s.memberId)
        .whereType<String>()
        .toList();

    // Ask each time: prompt only with multiple co-fronters.
    if (mode == ComposerDefaultMember.askEachTime && fronterIds.length > 1) {
      final allMembers = ref.read(userVisibleMembersProvider).value ?? [];
      final coFronters = allMembers
          .where((m) => fronterIds.contains(m.id))
          .toList();
      if (coFronters.isNotEmpty && mounted) {
        await _showCoFronterPicker(coFronters);
      }
      return;
    }

    // Otherwise pin the author from the resolved default. Seeded, not recorded,
    // so the auto-pick never overwrites the "last used" memory of a manual one.
    final resolved = ref.read(speakingAsProvider);
    if (resolved != null && resolved != unknownSentinelMemberId) {
      ref
          .read(speakingAsProvider.notifier)
          .setMember(resolved, recordLastUsed: false);
    } else if (fronterIds.length == 1) {
      ref
          .read(speakingAsProvider.notifier)
          .setMember(fronterIds.first, recordLastUsed: false);
    }
  }

  Future<void> _showCoFronterPicker(List<Member> coFronters) async {
    final l10n = context.l10n;
    final terminology = ref.read(terminologySettingProvider);
    final terms = resolveTerminology(
      l10n,
      terminology.term,
      customSingular: terminology.customSingular,
      customPlural: terminology.customPlural,
      useEnglish: terminology.useEnglish,
    );
    final result = await MemberSearchSheet.showSingle(
      context,
      members: coFronters,
      termPlural: terms.plural,
      title: l10n.boardsComposeWhoIsPosting,
      groups: readMemberSearchGroups(ref, coFronters),
    );
    if (!mounted) return;
    if (result is MemberSearchResultSelected) {
      ref.read(speakingAsProvider.notifier).setMember(result.memberId);
    }
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
    final fronterIds =
        ref
            .read(activeSessionsProvider)
            .value
            ?.map((s) => s.memberId)
            .whereType<String>()
            .toSet() ??
        const <String>{};
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: terms.plural,
      groups: groups,
      fronterIds: fronterIds,
      fronterSectionLabel: context.l10n.memberPickerFrontingSectionLabel,
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
    final isImageProcessing =
        ref.watch(bioImageProcessingStateProvider).status ==
        BioImageProcessingStatus.processing;
    final canPost =
        _canSave && !isImageProcessing && (isEditing || speakingAs != null);

    final targetMember = _targetMemberId != null
        ? ref.watch(activeMemberByIdProvider(_targetMemberId!)).value
        : null;
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    try {
      ref.watch(bioImageProcessorProvider(_editSessionId));
    } catch (_) {}

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
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => _bodyFocusNode.requestFocus(),
                    behavior: HitTestBehavior.translucent,
                    child: ListView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        PrismTokens.pageHorizontalPadding + 8,
                        8,
                        PrismTokens.pageHorizontalPadding + 8,
                        72,
                      ),
                      children: [
                        Semantics(
                          label:
                              targetMember?.name ??
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
                                      avatarImageData:
                                          targetMember.avatarImageData,
                                      memberName: targetMember.name,
                                      emoji: targetMember.emoji,
                                      customColorEnabled:
                                          targetMember.customColorEnabled,
                                      customColorHex:
                                          targetMember.customColorHex,
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
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
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
                  Positioned(
                    right: PrismTokens.pageHorizontalPadding + 8,
                    bottom: 12,
                    child: _EditorMarkdownActions(
                      bodyController: _bodyController,
                      editSessionId: _editSessionId,
                    ),
                  ),
                ],
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

  static const double _audienceSelectorWidth = 210;
  static const double _toolbarActionSize = PrismTokens.topBarActionSize;
  static const double _toolbarGap = 8;
  static const double _groupGap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final bottomInset = modalBottomInsetOf(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    final speakingAsId = isEditing ? null : ref.watch(speakingAsProvider);
    final authorMember = speakingAsId != null
        ? ref.watch(activeMemberByIdProvider(speakingAsId)).value
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final authorSelector = !isEditing
              ? _AuthorSelectorButton(
                  label: authorMember?.name ?? l10n.boardsComposeSelectAuthor,
                  authorMember: authorMember,
                  mutedColor: mutedColor,
                  onTap: onPickAuthor,
                )
              : null;

          final toolbarActions = <Widget>[?authorSelector];

          final actionGroupWidth = authorSelector == null
              ? 0
              : _toolbarActionSize;
          final singleRowFits =
              constraints.maxWidth >=
              actionGroupWidth + _groupGap + _audienceSelectorWidth;

          final audienceSelector = _AudienceSelector(
            width: constraints.maxWidth < _audienceSelectorWidth
                ? constraints.maxWidth
                : _audienceSelectorWidth,
            enabled: memberId != null,
            audience: audience,
            onAudienceChanged: onAudienceChanged,
          );

          if (singleRowFits) {
            return Row(
              children: [
                ...toolbarActions,
                if (toolbarActions.isNotEmpty)
                  const SizedBox(width: _toolbarGap),
                const Spacer(),
                audienceSelector,
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (toolbarActions.isNotEmpty)
                Row(children: [...toolbarActions, const Spacer()]),
              if (toolbarActions.isNotEmpty) const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: audienceSelector),
            ],
          );
        },
      ),
    );
  }
}

class _EditorMarkdownActions extends StatelessWidget {
  const _EditorMarkdownActions({
    required this.bodyController,
    required this.editSessionId,
  });

  final TextEditingController bodyController;
  final String editSessionId;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownTableButton(controller: bodyController),
        const SizedBox(width: 4),
        MarkdownImageButton(
          controller: bodyController,
          sessionId: editSessionId,
        ),
      ],
    );
  }
}

class _AuthorSelectorButton extends StatelessWidget {
  const _AuthorSelectorButton({
    required this.label,
    required this.authorMember,
    required this.mutedColor,
    required this.onTap,
  });

  final String label;
  final Member? authorMember;
  final Color mutedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: label,
      button: true,
      child: SizedBox.square(
        key: const ValueKey('boards.compose.authorSelector'),
        dimension: PrismTokens.topBarActionSize,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: authorMember != null
                  ? MemberAvatar(
                      avatarImageData: authorMember!.avatarImageData,
                      memberName: authorMember!.name,
                      emoji: authorMember!.emoji,
                      customColorEnabled: authorMember!.customColorEnabled,
                      customColorHex: authorMember!.customColorHex,
                      size: 32,
                    )
                  : Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Icon(
                        AppIcons.personOutline,
                        size: 18,
                        color: mutedColor,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudienceSelector extends StatelessWidget {
  const _AudienceSelector({
    required this.width,
    required this.enabled,
    required this.audience,
    required this.onAudienceChanged,
  });

  final double width;
  final bool enabled;
  final String audience;
  final ValueChanged<String> onAudienceChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SizedBox(
      key: const ValueKey('boards.compose.audienceSelector'),
      width: width,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: PrismSegmentedControl<String>(
            segments: [
              PrismSegment(
                value: 'public',
                label: l10n.boardsComposeAudienceEveryone,
              ),
              PrismSegment(
                value: 'private',
                label: l10n.boardsComposeAudiencePrivate,
              ),
            ],
            selected: audience,
            onChanged: enabled ? onAudienceChanged : (_) {},
          ),
        ),
      ),
    );
  }
}
