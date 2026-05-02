import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart'
    show speakingAsProvider;
import 'package:prism_plurality/features/chat/widgets/speaking_as_picker.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
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
/// Use [ComposePostSheet.show] to present this as a [PrismSheet] bottom sheet.
///
/// On save, returns the created or updated [MemberBoardPost]. Returns `null`
/// when the user cancels.
class ComposePostSheet {
  // Utility class — not instantiable.
  ComposePostSheet._();

  /// Present the compose sheet.
  ///
  /// - [defaultTargetMemberId]: pre-selects a recipient member.
  /// - [defaultAudience]: initial audience value; must be `'public'` or
  ///   `'private'`.
  /// - [defaultTitle]: pre-fills the title field (also auto-shows the title
  ///   input).
  /// - [defaultBody]: pre-fills the body field.
  /// - [editingPostId]: when non-null, loads the post for editing; audience
  ///   and recipient remain editable per spec (codex P1 #6).
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
    return PrismSheet.show<MemberBoardPost?>(
      context: context,
      maxHeightFactor: 0.95,
      builder: (sheetCtx) => _ComposePostSheetBody(
        defaultTargetMemberId: defaultTargetMemberId,
        defaultAudience: defaultAudience,
        defaultTitle: defaultTitle,
        defaultBody: defaultBody,
        editingPostId: editingPostId,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RecipientOption — describes one choice in the recipient picker
// ---------------------------------------------------------------------------

/// A single option in the recipient picker.
///
/// [targetMemberId] is null for the "Everyone (public)" option.
/// [audience] is `'public'` or `'private'`.
class _RecipientOption {
  const _RecipientOption({
    required this.label,
    required this.audience,
    this.targetMemberId,
    this.member,
  });

  final String label;
  final String audience;
  final String? targetMemberId;
  final Member? member;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _RecipientOption &&
          targetMemberId == other.targetMemberId &&
          audience == other.audience;

  @override
  int get hashCode => Object.hash(targetMemberId, audience);
}

// ---------------------------------------------------------------------------
// Internal body widget
// ---------------------------------------------------------------------------

class _ComposePostSheetBody extends ConsumerStatefulWidget {
  const _ComposePostSheetBody({
    required this.defaultTargetMemberId,
    required this.defaultAudience,
    required this.defaultTitle,
    required this.defaultBody,
    required this.editingPostId,
  });

  final String? defaultTargetMemberId;
  final String defaultAudience;
  final String? defaultTitle;
  final String? defaultBody;
  final String? editingPostId;

  @override
  ConsumerState<_ComposePostSheetBody> createState() =>
      _ComposePostSheetBodyState();
}

class _ComposePostSheetBodyState
    extends ConsumerState<_ComposePostSheetBody> {
  final _bodyController = TextEditingController();
  final _titleController = TextEditingController();
  final _bodyFocusNode = FocusNode();

  // Recipient selection
  String _audience = 'public';
  String? _targetMemberId; // null = "Everyone (public)"

  // UI state
  bool _showTitle = false;
  bool _isSaving = false;
  bool _loaded = false; // true once edit-mode fetch completes

  @override
  void initState() {
    super.initState();
    _audience = widget.defaultAudience;
    _targetMemberId = widget.defaultTargetMemberId;

    if (widget.defaultTitle != null) {
      _titleController.text = widget.defaultTitle!;
      _showTitle = true;
    }
    if (widget.defaultBody != null) {
      _bodyController.text = widget.defaultBody!;
    }

    // For new posts (no editingPostId), mark as loaded immediately.
    if (widget.editingPostId == null) {
      _loaded = true;
    }

    _bodyController.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onBodyChanged);
    _bodyController.dispose();
    _titleController.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _onBodyChanged() => setState(() {});

  bool get _canSave =>
      !_isSaving && _bodyController.text.trim().isNotEmpty;

  // ---------------------------------------------------------------------------
  // Edit-mode prefill
  // ---------------------------------------------------------------------------

  Future<void> _loadExistingPost() async {
    final postId = widget.editingPostId;
    if (postId == null) return;

    final repo = ref.read(memberBoardPostsRepositoryProvider);
    final post = await repo.getPostById(postId);
    if (!mounted) return;
    if (post == null) return;

    setState(() {
      _audience = post.audience;
      _targetMemberId = post.targetMemberId;
      _bodyController.text = post.body;
      if (post.title != null && post.title!.isNotEmpty) {
        _titleController.text = post.title!;
        _showTitle = true;
      }
      _loaded = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save(BuildContext context) async {
    if (!_canSave) return;

    setState(() => _isSaving = true);

    try {
      final notifier =
          ref.read(memberBoardPostNotifierProvider.notifier);
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
        // Re-fetch so we can return the updated post to the caller.
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

      if (context.mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

  List<_RecipientOption> _buildOptions(
    List<Member> members,
    AppLocalizations l10n,
  ) {
    final options = <_RecipientOption>[
      _RecipientOption(
        label: l10n.boardsComposeRecipientPublicEveryone,
        audience: 'public',
        targetMemberId: null,
      ),
    ];

    for (final m in members) {
      options.add(
        _RecipientOption(
          label: l10n.boardsComposeRecipientPublicMember(m.name),
          audience: 'public',
          targetMemberId: m.id,
          member: m,
        ),
      );
      options.add(
        _RecipientOption(
          label: l10n.boardsComposeRecipientPrivateMember(m.name),
          audience: 'private',
          targetMemberId: m.id,
          member: m,
        ),
      );
    }

    return options;
  }

  _RecipientOption _selectedOption(List<_RecipientOption> options) {
    for (final opt in options) {
      if (opt.targetMemberId == _targetMemberId &&
          opt.audience == _audience) {
        return opt;
      }
    }
    // Fallback: "Everyone (public)".
    return options.first;
  }

  String _consequenceText(
    _RecipientOption selected,
    AppLocalizations l10n,
  ) {
    if (selected.targetMemberId == null) {
      return l10n.boardsComposeConsequencePublicEveryone;
    }
    final name =
        selected.member?.name ?? selected.targetMemberId ?? '';
    if (selected.audience == 'private') {
      return l10n.boardsComposeConsequencePrivate(name);
    }
    return l10n.boardsComposeConsequencePublicMember(name);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Kick off the edit-mode fetch on first build.
    if (widget.editingPostId != null && !_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadExistingPost();
      });
    }

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isEditing = widget.editingPostId != null;

    // Filter out the sentinel (unknown) member — same as SpeakingAsPicker does
    // with userVisibleMembersProvider.
    final visibleMembers =
        ref.watch(userVisibleMembersProvider).value ?? const [];

    final options = _buildOptions(visibleMembers, l10n);
    final selected = _selectedOption(options);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sheet title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              isEditing ? l10n.boardsComposeEditing : '',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Speaking-as header ──────────────────────────────────────────
          const SpeakingAsPicker(),

          const SizedBox(height: 12),

          // ── Recipient picker ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _RecipientPickerRow(
              options: options,
              selected: selected,
              onSelected: (opt) {
                setState(() {
                  _audience = opt.audience;
                  _targetMemberId = opt.targetMemberId;
                });
              },
            ),
          ),

          const SizedBox(height: 6),

          // ── Consequence text ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _consequenceText(selected, l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Optional title ──────────────────────────────────────────────
          if (_showTitle)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: PrismTextField(
                controller: _titleController,
                hintText: l10n.boardsComposeTitlePlaceholder,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLines: 1,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: GestureDetector(
                onTap: () {
                  setState(() => _showTitle = true);
                },
                child: Text(
                  l10n.boardsComposeAddTitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // ── Body ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: PrismTextField(
              controller: _bodyController,
              focusNode: _bodyFocusNode,
              autofocus: true,
              hintText: l10n.boardsComposeBodyPlaceholder,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: null,
            ),
          ),

          const SizedBox(height: 20),

          // ── Action row ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PrismButton(
                  label: l10n.boardsComposeCancel,
                  tone: PrismButtonTone.subtle,
                  onPressed: () => Navigator.of(context).pop(null),
                ),
                const SizedBox(width: 8),
                PrismButton(
                  label: l10n.boardsComposeSave,
                  tone: PrismButtonTone.filled,
                  enabled: _canSave,
                  isLoading: _isSaving,
                  onPressed: () => _save(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RecipientPickerRow — chip-trigger that opens a popup picker
// ---------------------------------------------------------------------------

class _RecipientPickerRow extends StatelessWidget {
  const _RecipientPickerRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_RecipientOption> options;
  final _RecipientOption selected;
  final ValueChanged<_RecipientOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrivate = selected.audience == 'private';
    final accentColor = isPrivate
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(
        PrismShapes.of(context).radius(999),
      ),
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(999),
          ),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.35),
          ),
        ),
        child: Semantics(
          button: true,
          label: selected.label,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.member != null) ...[
                MemberAvatar(
                  avatarImageData: selected.member!.avatarImageData,
                  memberName: selected.member!.name,
                  emoji: selected.member!.emoji,
                  customColorEnabled: selected.member!.customColorEnabled,
                  customColorHex: selected.member!.customColorHex,
                  size: 20,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  selected.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: accentColor),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    await PrismSheet.show(
      context: context,
      builder: (sheetCtx) => _RecipientPickerSheet(
        options: options,
        selected: selected,
        onSelected: (opt) {
          Navigator.of(sheetCtx).pop();
          onSelected(opt);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RecipientPickerSheet — modal bottom sheet with the full option list
// ---------------------------------------------------------------------------

class _RecipientPickerSheet extends StatelessWidget {
  const _RecipientPickerSheet({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_RecipientOption> options;
  final _RecipientOption selected;
  final ValueChanged<_RecipientOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      shrinkWrap: true,
      itemCount: options.length,
      itemBuilder: (ctx, index) {
        final opt = options[index];
        final isSelected = opt == selected;
        final isPrivate = opt.audience == 'private';
        final accentColor = isPrivate
            ? theme.colorScheme.secondary
            : theme.colorScheme.primary;

        return PrismListRow(
          leading: opt.member != null
              ? MemberAvatar(
                  avatarImageData: opt.member!.avatarImageData,
                  memberName: opt.member!.name,
                  emoji: opt.member!.emoji,
                  customColorEnabled: opt.member!.customColorEnabled,
                  customColorHex: opt.member!.customColorHex,
                  size: 32,
                )
              : Icon(
                  Icons.public,
                  color: theme.colorScheme.primary,
                ),
          title: Text(
            opt.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isSelected ? accentColor : null,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check, color: accentColor, size: 18)
              : null,
          onTap: () => onSelected(opt),
        );
      },
    );
  }
}
