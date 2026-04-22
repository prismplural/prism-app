import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Bottom sheet for creating a new conversation (DM or group).
///
/// Use via [PrismSheet.showFullScreen] — pass the [scrollController] from the
/// builder callback.
class CreateConversationSheet extends ConsumerStatefulWidget {
  const CreateConversationSheet({
    super.key,
    required this.scrollController,
    this.initialMemberIds,
  });

  final ScrollController scrollController;

  /// Optional list of member IDs to pre-select when the sheet opens.
  /// Takes precedence over the speaking-as auto-selection when provided.
  final List<String>? initialMemberIds;

  @override
  ConsumerState<CreateConversationSheet> createState() =>
      _CreateConversationSheetState();
}

class _CreateConversationSheetState
    extends ConsumerState<CreateConversationSheet> {
  bool _isGroupChat = true;
  final _titleController = TextEditingController();
  final _emojiController = TextEditingController();
  final Set<String> _selectedMemberIds = {};
  String? _selectedCategoryId;
  bool _isCreating = false;
  bool _didPreselect = false;

  @override
  void dispose() {
    _titleController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  bool get _canCreate {
    if (_isGroupChat) {
      return _titleController.text.trim().isNotEmpty &&
          _selectedMemberIds.length >= 2;
    } else {
      // DM: current fronter + one selected other member
      final speakingAs = ref.read(speakingAsProvider);
      return speakingAs != null && _selectedMemberIds.length == 1;
    }
  }

  List<String> get _dmParticipants {
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return _selectedMemberIds.toList();
    return {speakingAs, ..._selectedMemberIds}.toList();
  }

  String _currentFronterName(AsyncValue<dynamic> membersAsync) {
    final speakingAs = ref.read(speakingAsProvider);
    if (speakingAs == null) return '...';
    final members = membersAsync.value;
    if (members == null) return '...';
    for (final m in members) {
      if (m.id == speakingAs) return m.name;
    }
    return '...';
  }

  Future<void> _createConversation() async {
    if (!_canCreate || _isCreating) return;

    setState(() => _isCreating = true);

    final speakingAs = ref.read(speakingAsProvider);

    try {
      final conversation = await ref
          .read(chatNotifierProvider.notifier)
          .createGroupConversation(
            title: _isGroupChat ? _titleController.text.trim() : '',
            emoji: _emojiController.text.trim().isNotEmpty
                ? _emojiController.text.trim()
                : null,
            creatorId: speakingAs ?? _selectedMemberIds.first,
            participantIds: _isGroupChat
                ? _selectedMemberIds.toList()
                : _dmParticipants,
            categoryId: _isGroupChat ? _selectedCategoryId : null,
            isDirectMessage: !_isGroupChat,
          );

      if (mounted) {
        Haptics.success();
        Navigator.of(context).pop(conversation.id);
      }
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: context.l10n.chatCreateFailed(e));
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _openSearchSheet(
    BuildContext context,
    ThemeData theme,
    List<Member> members,
  ) async {
    final speakingAs = ref.read(speakingAsProvider);
    final s = ref.read(terminologySettingProvider);
    final termPlural = resolveTerminology(
      context.l10n,
      s.term,
      customSingular: s.customSingular,
      customPlural: s.customPlural,
      useEnglish: s.useEnglish,
    ).plural;

    final frontingLabel = context.l10n.chatCreateFronting;
    final primaryColor = theme.colorScheme.primary;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: primaryColor,
      fontWeight: FontWeight.w600,
    );

    // DM mode: exclude the speaking-as member (they are the sender).
    final searchMembers = _isGroupChat
        ? members
        : members.where((m) => m.id != speakingAs).toList();
    final initialSelected =
        _isGroupChat
              ? Set<String>.from(_selectedMemberIds)
              : Set<String>.from(_selectedMemberIds)
          ..remove(speakingAs);

    final result = await MemberSearchSheet.showMulti(
      context,
      members: searchMembers,
      termPlural: termPlural,
      initialSelected: initialSelected,
      trailingBuilder: _isGroupChat
          ? (member) {
              if (member.id != speakingAs) return null;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(frontingLabel, style: labelStyle),
              );
            }
          : null,
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedMemberIds.clear();
      if (_isGroupChat) {
        _selectedMemberIds.addAll(result);
      } else {
        _selectedMemberIds.addAll(result.where((id) => id != speakingAs));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(activeMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);

    // Pre-select members once loaded: initialMemberIds takes precedence,
    // otherwise fall back to the current speaking-as fronter.
    if (!_didPreselect && membersAsync.hasValue) {
      _didPreselect = true;
      if (widget.initialMemberIds != null &&
          widget.initialMemberIds!.isNotEmpty) {
        // Filter to active members only — inactive members aren't visible
        // in the sheet and can't be unchecked by the user.
        final activeIds = membersAsync.value!.map((m) => m.id).toSet();
        _selectedMemberIds.addAll(
          widget.initialMemberIds!.where(activeIds.contains),
        );
      } else if (speakingAs != null) {
        _selectedMemberIds.add(speakingAs);
      }
    }

    // Show warning if fronter was deselected in group mode
    final fronterDeselected =
        _isGroupChat &&
        speakingAs != null &&
        !_selectedMemberIds.contains(speakingAs);

    // Member rows for the inline lazy sliver list.
    final members = membersAsync.value ?? [];
    final displayMembers = _isGroupChat
        ? members
        : members.where((m) => m.id != speakingAs).toList();

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: context.l10n.chatCreateTitle,
            trailing: _isCreating
                ? SizedBox(
                    width: PrismTokens.topBarActionSize,
                    height: PrismTokens.topBarActionSize,
                    child: Center(
                      child: PrismSpinner(
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  )
                : PrismGlassIconButton(
                    icon: AppIcons.check,
                    size: PrismTokens.topBarActionSize,
                    tint: _canCreate ? theme.colorScheme.primary : null,
                    accentIcon: _canCreate,
                    onPressed: _canCreate ? _createConversation : null,
                  ),
          ),
          const SizedBox(height: 8),

          // Scrollable body using CustomScrollView so the member list is a
          // truly lazy SliverList.builder (no eager Column).
          Expanded(
            child: CustomScrollView(
              controller: widget.scrollController,
              slivers: [
                // ── DM / Group toggle ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PrismSegmentedControl<bool>(
                      segments: [
                        PrismSegment(
                          value: true,
                          label: context.l10n.chatCreateGroupTab,
                        ),
                        PrismSegment(
                          value: false,
                          label: context.l10n.chatCreateDirectMessageTab,
                        ),
                      ],
                      selected: _isGroupChat,
                      onChanged: (value) {
                        setState(() {
                          _isGroupChat = value;
                        });
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // ── Group-specific fields ────────────────────────────────
                if (_isGroupChat) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          PrismEmojiPicker(
                            emoji: _emojiController.text.trim().isNotEmpty
                                ? _emojiController.text.trim()
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
                              controller: _titleController,
                              labelText: context.l10n.chatCreateGroupName,
                              hintText: context.l10n.chatCreateGroupNameHint,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // Category picker
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Builder(
                        builder: (context) {
                          final categoriesAsync = ref.watch(
                            conversationCategoriesProvider,
                          );
                          final categories = categoriesAsync.value ?? [];
                          if (categories.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final noneLabel = context.l10n.chatInfoCategoryNone;
                          final currentName = _selectedCategoryId != null
                              ? categories
                                        .where(
                                          (c) => c.id == _selectedCategoryId,
                                        )
                                        .map((c) => c.name)
                                        .firstOrNull ??
                                    noneLabel
                              : noneLabel;
                          return Semantics(
                            button: true,
                            label: context.l10n.chatInfoCategorySemantics(
                              currentName,
                            ),
                            child: PrismListRow(
                              title: Text(context.l10n.chatInfoCategory),
                              subtitle: Text(currentName),
                              trailing: Icon(AppIcons.chevronRightRounded),
                              onTap: () {
                                PrismSheet.show(
                                  context: context,
                                  builder: (ctx) => Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PrismListRow(
                                        title: Text(
                                          ctx.l10n.chatInfoCategoryNone,
                                        ),
                                        trailing: _selectedCategoryId == null
                                            ? Icon(AppIcons.checkRounded)
                                            : null,
                                        onTap: () {
                                          setState(
                                            () => _selectedCategoryId = null,
                                          );
                                          Navigator.of(ctx).pop();
                                        },
                                      ),
                                      for (final cat in categories)
                                        PrismListRow(
                                          title: Text(cat.name),
                                          trailing:
                                              cat.id == _selectedCategoryId
                                              ? Icon(AppIcons.checkRounded)
                                              : null,
                                          onTap: () {
                                            setState(
                                              () =>
                                                  _selectedCategoryId = cat.id,
                                            );
                                            Navigator.of(ctx).pop();
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],

                // ── Member selection header ──────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          _isGroupChat
                              ? context.l10n.chatCreateSelectParticipants
                              : context.l10n.chatCreateMessageAs(
                                  _currentFronterName(membersAsync),
                                ),
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        // Search button — opens shared multi-select sheet.
                        IconButton(
                          icon: Icon(AppIcons.search),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: context.l10n.search,
                          onPressed: members.isEmpty
                              ? null
                              : () => _openSearchSheet(context, theme, members),
                        ),
                        if (_isGroupChat)
                          membersAsync.whenOrNull(
                                data: (members) {
                                  if (members.isEmpty) return null;
                                  final allSelected = members.every(
                                    (m) => _selectedMemberIds.contains(m.id),
                                  );
                                  return PrismButton(
                                    label: allSelected
                                        ? context.l10n.chatCreateDeselectAll
                                        : context.l10n.chatCreateSelectAll,
                                    tone: PrismButtonTone.subtle,
                                    onPressed: () {
                                      setState(() {
                                        if (allSelected) {
                                          _selectedMemberIds.clear();
                                        } else {
                                          _selectedMemberIds.addAll(
                                            members.map((m) => m.id),
                                          );
                                        }
                                      });
                                    },
                                  );
                                },
                              ) ??
                              const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // ── Member rows (lazy) ───────────────────────────────────
                ..._buildMemberSliver(
                  context,
                  theme,
                  membersAsync,
                  speakingAs,
                  displayMembers,
                ),

                // ── Fronter-deselected warning ───────────────────────────
                if (fronterDeselected)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.infoOutline,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.l10n.chatCreateFronterDeselectedWarning(
                                  _currentFronterName(membersAsync),
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Bottom padding ───────────────────────────────────────
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMemberSliver(
    BuildContext context,
    ThemeData theme,
    AsyncValue<dynamic> membersAsync,
    String? speakingAs,
    List<dynamic> displayMembers,
  ) {
    return membersAsync.when(
      data: (_) {
        if (displayMembers.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l10n.chatCreateNoMembers,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ];
        }
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: displayMembers.length,
              itemBuilder: (context, index) {
                final member = displayMembers[index];
                return PrismCheckboxRow(
                  padding: EdgeInsets.zero,
                  leading: MemberAvatar(
                    avatarImageData: member.avatarImageData,
                    memberName: member.name,
                    emoji: member.emoji,
                    customColorEnabled: member.customColorEnabled,
                    customColorHex: member.customColorHex,
                    size: 36,
                  ),
                  title: Row(
                    children: [
                      Text(member.name),
                      if (member.id == speakingAs) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(
                              PrismShapes.of(context).pill(22),
                            ),
                          ),
                          child: Text(
                            context.l10n.chatCreateFronting,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  value: _selectedMemberIds.contains(member.id),
                  onChanged: (selected) {
                    setState(() {
                      if (selected) {
                        if (!_isGroupChat) _selectedMemberIds.clear();
                        _selectedMemberIds.add(member.id);
                      } else {
                        _selectedMemberIds.remove(member.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ];
      },
      loading: () => [const SliverToBoxAdapter(child: PrismLoadingState())],
      error: (error, _) => [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.l10n.chatAddMembersFailed(error),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
