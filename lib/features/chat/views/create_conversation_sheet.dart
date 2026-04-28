import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_picker_text_field_row.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/selected_member_picker.dart';
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
  /// When omitted, the picker starts empty.
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
    List<MemberSearchGroup> groups,
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

    if (_isGroupChat) {
      final result = await MemberSearchSheet.showMulti(
        context,
        members: members,
        termPlural: termPlural,
        groups: groups,
        initialSelected: Set<String>.from(_selectedMemberIds),
        trailingBuilder: (member) {
          if (member.id != speakingAs) return null;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(frontingLabel, style: labelStyle),
          );
        },
      );

      if (result == null || !mounted) return;
      setState(() {
        _selectedMemberIds
          ..clear()
          ..addAll(result);
      });
      return;
    }

    final eligibleMembers = members
        .where((member) => member.id != speakingAs)
        .toList();
    final result = await MemberSearchSheet.showSingle(
      context,
      members: eligibleMembers,
      termPlural: termPlural,
      groups: groups,
    );

    if (!mounted) return;
    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        setState(() {
          _selectedMemberIds
            ..clear()
            ..add(memberId);
        });
      case MemberSearchResultDismissed():
      case MemberSearchResultCleared():
      case MemberSearchResultUnknown():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Non-fronting picker: hide the Unknown sentinel — chats with the
    // placeholder member aren't a real flow.
    final membersAsync = ref.watch(userVisibleMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);

    // Pre-select members once loaded only when the caller explicitly provided
    // initial IDs.
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
      }
    }

    // Show warning only after the user has started choosing participants.
    final fronterDeselected =
        _isGroupChat &&
        _selectedMemberIds.isNotEmpty &&
        speakingAs != null &&
        !_selectedMemberIds.contains(speakingAs);

    // Member rows for the inline lazy sliver list.
    final members = membersAsync.value ?? [];
    final displayMembers = _isGroupChat
        ? members
        : members.where((m) => m.id != speakingAs).toList();
    final searchGroups = watchMemberSearchGroups(ref, displayMembers);

    final topBar = PrismSheetTopBar(
      title: context.l10n.chatCreateTitle,
      trailing: _isCreating
          ? SizedBox(
              width: PrismTokens.topBarActionSize,
              height: PrismTokens.topBarActionSize,
              child: Center(
                child: PrismSpinner(color: theme.colorScheme.primary, size: 20),
              ),
            )
          : PrismGlassIconButton(
              icon: AppIcons.check,
              size: PrismTokens.topBarActionSize,
              tooltip: context.l10n.chatCreateConversationTooltip,
              tint: _canCreate ? theme.colorScheme.primary : null,
              accentIcon: _canCreate,
              onPressed: _canCreate ? _createConversation : null,
            ),
    );

    List<Widget> buildBodySlivers({bool includeTopBar = false}) => [
      if (includeTopBar) SliverToBoxAdapter(child: topBar),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
      // ── DM / Group toggle ────────────────────────────────────
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PrismSegmentedControl<bool>(
            segments: [
              PrismSegment(value: true, label: context.l10n.chatCreateGroupTab),
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
            child: PrismPickerTextFieldRow(
              pickerLabel: context.l10n.onboardingAddMemberFieldEmoji,
              picker: PrismEmojiPicker(
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
              field: PrismTextField(
                controller: _titleController,
                labelText: context.l10n.chatCreateGroupName,
                hintText: context.l10n.chatCreateGroupNameHint,
                onChanged: (_) => setState(() {}),
              ),
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
                              .where((c) => c.id == _selectedCategoryId)
                              .map((c) => c.name)
                              .firstOrNull ??
                          noneLabel
                    : noneLabel;
                return Semantics(
                  button: true,
                  label: context.l10n.chatInfoCategorySemantics(currentName),
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
                              title: Text(ctx.l10n.chatInfoCategoryNone),
                              trailing: _selectedCategoryId == null
                                  ? Icon(AppIcons.checkRounded)
                                  : null,
                              onTap: () {
                                setState(() => _selectedCategoryId = null);
                                Navigator.of(ctx).pop();
                              },
                            ),
                            for (final cat in categories)
                              PrismListRow(
                                title: Text(cat.name),
                                trailing: cat.id == _selectedCategoryId
                                    ? Icon(AppIcons.checkRounded)
                                    : null,
                                onTap: () {
                                  setState(() => _selectedCategoryId = cat.id);
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

      // ── Member picker ────────────────────────────────────────
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildMemberPicker(
            context,
            membersAsync,
            displayMembers,
            searchGroups,
          ),
        ),
      ),

      // ── Spacer below member picker ───────────────────────────
      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      // ── Fronter-deselected warning ───────────────────────────
      if (fronterDeselected)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
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
        child: SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
      ),
    ];

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < PrismTokens.topBarHeight) {
            return CustomScrollView(
              controller: widget.scrollController,
              slivers: buildBodySlivers(includeTopBar: true),
            );
          }

          return Column(
            children: [
              topBar,
              Expanded(
                child: CustomScrollView(
                  controller: widget.scrollController,
                  slivers: buildBodySlivers(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMemberPicker(
    BuildContext context,
    AsyncValue<dynamic> membersAsync,
    List<Member> displayMembers,
    List<MemberSearchGroup> searchGroups,
  ) {
    return membersAsync.when(
      data: (_) {
        if (displayMembers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.l10n.chatCreateNoMembers,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        if (_isGroupChat) {
          return SelectedMultiMemberPicker(
            key: const Key('createConversationSelectedMemberPicker'),
            members: displayMembers,
            selectedMemberIds: _selectedMemberIds,
            onPressed: () => _openSearchSheet(
              context,
              Theme.of(context),
              displayMembers,
              searchGroups,
            ),
          );
        }

        return SelectedMemberPicker(
          key: const Key('createConversationSelectedMemberPicker'),
          members: displayMembers,
          selectedMemberId: _selectedMemberIds.isEmpty
              ? null
              : _selectedMemberIds.first,
          includeUnknown: false,
          onPressed: () => _openSearchSheet(
            context,
            Theme.of(context),
            displayMembers,
            searchGroups,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.chatAddMembersFailed(error),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
