import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/utils/chat_author_options.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/category_management_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/conversation_tile.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_selector_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

const _kLastChatSubTabKey = 'chat.last_sub_tab';
const _kGroupChatVisibilityNudgeDismissedKey =
    'chat.group_visibility_nudge.dismissed.v1';
const _kDirectMessagesTabPreferenceValue = 0;
const _kGroupChatsTabPreferenceValue = 1;

enum _ChatSubTab { directMessages, groupChats }

/// Main conversation list screen.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _seeded = false;
  bool _seedAttemptInFlight = false;
  bool? _groupChatVisibilityNudgeDismissed;
  _ChatSubTab _activeTab = _ChatSubTab.groupChats;

  @override
  void initState() {
    super.initState();
    _loadSavedTab();
    _loadGroupChatVisibilityNudgeDismissal();
  }

  Future<void> _loadSavedTab() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_kLastChatSubTabKey);
    final tab = savedIndex == _kDirectMessagesTabPreferenceValue
        ? _ChatSubTab.directMessages
        : _ChatSubTab.groupChats;
    if (mounted) {
      setState(() => _activeTab = tab);
    }
  }

  Future<void> _loadGroupChatVisibilityNudgeDismissal() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed =
        prefs.getBool(_kGroupChatVisibilityNudgeDismissedKey) ?? false;
    if (mounted) {
      setState(() => _groupChatVisibilityNudgeDismissed = dismissed);
    }
  }

  Future<void> _dismissGroupChatVisibilityNudge() async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setBool(
      _kGroupChatVisibilityNudgeDismissedKey,
      true,
    );
    if (ok && mounted) {
      setState(() => _groupChatVisibilityNudgeDismissed = true);
    }
  }

  void _selectTab(_ChatSubTab tab) {
    if (_activeTab == tab) return;
    setState(() => _activeTab = tab);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt(
          _kLastChatSubTabKey,
          tab == _ChatSubTab.directMessages
              ? _kDirectMessagesTabPreferenceValue
              : _kGroupChatsTabPreferenceValue,
        ),
      ),
    );
  }

  bool _matchesActiveTab(
    Conversation conversation,
    String? speakingAs,
    Member? speakingAsMember,
  ) {
    final permissions = conversationPermissionsForViewer(
      conversation,
      speakingAsMemberId: speakingAs,
      speakingAsMember: speakingAsMember,
    );
    return _activeTab == _ChatSubTab.directMessages
        ? permissions.isDirectMessage
        : !permissions.isDirectMessage;
  }

  /// Create a default "All [Members]" conversation if none exist yet.
  void _seedDefaultConversation(List<Conversation> conversations) {
    if (_seeded || _seedAttemptInFlight || conversations.isNotEmpty) return;

    // Don't seed the default conversation creator as the Unknown sentinel —
    // pick from real, user-visible members only.
    final members = ref.read(userVisibleMembersProvider).value;
    if (members == null || members.isEmpty) return;

    final terms = readTerminology(context, ref);
    _seedAttemptInFlight = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _seedAttemptInFlight = false;
        return;
      }
      try {
        await ref
            .read(chatNotifierProvider.notifier)
            .seedDefaultConversationIfNeeded(
              title: 'All ${terms.plural}',
              emoji: '💬',
              members: members,
            );
      } catch (error) {
        if (!mounted) return;
        PrismToast.error(
          context,
          message: context.l10n.chatCreateFailed(error),
        );
      } finally {
        _seeded = true;
        _seedAttemptInFlight = false;
      }
    });
  }

  Widget _buildConversationTile(
    BuildContext context,
    ThemeData theme,
    Conversation conversation,
    String? speakingAs,
    Member? speakingAsMember,
  ) {
    final permissions = conversationPermissionsForViewer(
      conversation,
      speakingAsMemberId: speakingAs,
      speakingAsMember: speakingAsMember,
    );
    final actions = <Widget Function(BuildContext, VoidCallback)>[
      (ctx, close) {
        final popupTheme = Theme.of(ctx);
        return PrismListRow(
          dense: true,
          leading: Icon(
            permissions.canMarkRead
                ? AppIcons.markEmailReadOutlined
                : AppIcons.visibilityOutlined,
            size: 20,
          ),
          title: Text(
            permissions.canMarkRead
                ? ctx.l10n.chatMarkAsRead
                : ctx.l10n.chatConversationInfo,
            style: popupTheme.textTheme.bodyMedium,
          ),
          onTap: () {
            close();
            if (permissions.canMarkRead && speakingAs != null) {
              ref
                  .read(chatNotifierProvider.notifier)
                  .markConversationAsRead(conversation.id, speakingAs);
            }
            context.go(AppRoutePaths.chatConversation(conversation.id));
          },
        );
      },
    ];

    if (permissions.canMute) {
      actions.add((ctx, close) {
        final isMuted =
            speakingAs != null &&
            conversation.mutedByMemberIds.contains(speakingAs);
        final popupTheme = Theme.of(ctx);
        return PrismListRow(
          dense: true,
          leading: Icon(
            isMuted
                ? AppIcons.notificationsOutlined
                : AppIcons.notificationsOffOutlined,
            size: 20,
          ),
          title: Text(
            isMuted ? ctx.l10n.chatUnmute : ctx.l10n.chatMute,
            style: popupTheme.textTheme.bodyMedium,
          ),
          onTap: () {
            close();
            if (speakingAs != null) {
              ref
                  .read(chatNotifierProvider.notifier)
                  .toggleMute(conversation.id, speakingAs);
            }
          },
        );
      });
    }

    if (permissions.canDeleteConversation) {
      actions.add((ctx, close) {
        final popupTheme = Theme.of(ctx);
        return PrismListRow(
          dense: true,
          leading: Icon(
            AppIcons.deleteOutline,
            size: 20,
            color: popupTheme.colorScheme.error,
          ),
          title: Text(
            ctx.l10n.delete,
            style: popupTheme.textTheme.bodyMedium?.copyWith(
              color: popupTheme.colorScheme.error,
            ),
          ),
          onTap: () {
            close();
            _confirmDeleteConversation(context, ref, conversation);
          },
        );
      });
    }

    return BlurPopupAnchor(
      trigger: BlurPopupTrigger.longPress,
      width: 240,
      maxHeight: 180,
      itemCount: actions.length,
      itemBuilder: (ctx, index, close) => actions[index](ctx, close),
      child: ConversationTile(
        conversation: conversation,
        onTap: () {
          context.go(AppRoutePaths.chatConversation(conversation.id));
        },
      ),
    );
  }

  /// Build a list of slivers for a category group with lazy rendering.
  List<Widget> _buildCategorySlivers({
    required BuildContext context,
    required ThemeData theme,
    required String? label,
    required List<Conversation> conversations,
    required String? speakingAs,
    required Member? speakingAsMember,
  }) {
    final baseColor = theme.colorScheme.onSurface.withValues(alpha: 1);
    final backgroundColor = baseColor.withValues(alpha: 0.08);
    final borderColor = baseColor.withValues(alpha: 0.1);
    final borderRadius = BorderRadius.circular(
      PrismShapes.of(context).radius(PrismTokens.radiusMedium),
    );

    return [
      if (label != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor),
          ),
          sliver: SliverList.separated(
            itemCount: conversations.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 64,
              endIndent: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final permissions = conversationPermissionsForViewer(
                conversation,
                speakingAsMemberId: speakingAs,
                speakingAsMember: speakingAsMember,
              );
              return Dismissible(
                key: ValueKey(conversation.id),
                direction: permissions.canDeleteConversation
                    ? DismissDirection.endToStart
                    : DismissDirection.none,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: theme.colorScheme.error,
                  child: Icon(
                    AppIcons.delete,
                    color: theme.colorScheme.onError,
                  ),
                ),
                confirmDismiss: (_) =>
                    _confirmDeleteConversation(context, ref, conversation),
                child: _buildConversationTile(
                  context,
                  theme,
                  conversation,
                  speakingAs,
                  speakingAsMember,
                ),
              );
            },
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversationsAsync = ref.watch(filteredConversationsProvider);
    final showArchived = ref.watch(showArchivedProvider);
    final hasArchived = ref.watch(hasArchivedConversationsProvider);
    final speakingAs = ref.watch(speakingAsProvider);
    final speakingAsMember = ref.watch(currentChatViewerProvider);
    final categoriesAsync = ref.watch(conversationCategoriesProvider);
    ref.watch(activeMembersProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(conversationsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverPinnedTopBar(
              child: _ChatTopBar(
                activeTab: _activeTab,
                onTabSelected: _selectTab,
                speakingAs: speakingAs,
                hasArchived: hasArchived,
                showArchived: showArchived,
                onSearchTap: () => context.go('${AppRoutePaths.chat}/search'),
                onArchiveTap: () =>
                    ref.read(showArchivedProvider.notifier).toggle(),
                onCreateTap: () => _showCreateSheet(context),
              ),
            ),

            // Conversation list
            ...conversationsAsync.when(
              skipLoadingOnReload: true,
              data: (conversations) {
                _seedDefaultConversation(conversations);

                final visibleConversations = conversations
                    .where(
                      (conversation) => _matchesActiveTab(
                        conversation,
                        speakingAs,
                        speakingAsMember,
                      ),
                    )
                    .toList();

                // Separate section for admin-only access — keeps "I'm in
                // this chat" distinct from "I see this because I'm admin".
                final participantConversations = <Conversation>[];
                final adminOnlyConversations = <Conversation>[];
                for (final conversation in visibleConversations) {
                  final permissions = conversationPermissionsForViewer(
                    conversation,
                    speakingAsMemberId: speakingAs,
                    speakingAsMember: speakingAsMember,
                  );
                  if (permissions.isAdminNonParticipantGroup &&
                      !permissions.isParticipant) {
                    adminOnlyConversations.add(conversation);
                  } else {
                    participantConversations.add(conversation);
                  }
                }

                if (conversations.isEmpty || visibleConversations.isEmpty) {
                  if (speakingAs == null) {
                    return const [
                      SliverToBoxAdapter(child: _PickSpeakerBanner()),
                    ];
                  }
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icon(AppIcons.chatBubbleOutline),
                        title: _activeTab == _ChatSubTab.directMessages
                            ? context.l10n.chatNoDirectMessages
                            : context.l10n.chatNoGroupChats,
                        subtitle: _activeTab == _ChatSubTab.directMessages
                            ? context.l10n.chatNoDirectMessagesSubtitle
                            : context.l10n.chatNoGroupChatsSubtitle,
                        actionLabel: context.l10n.chatNewConversation,
                        onAction: () => _showCreateSheet(context),
                      ),
                    ),
                  ];
                }

                final categories = categoriesAsync.value ?? [];
                final showVisibilityNudge =
                    _activeTab == _ChatSubTab.groupChats &&
                    _groupChatVisibilityNudgeDismissed == false &&
                    visibleConversations.any(
                      (conversation) => conversation.includesAllMembers,
                    );
                final visibilityNudgeSlivers = showVisibilityNudge
                    ? <Widget>[
                        SliverToBoxAdapter(
                          child: _GroupChatVisibilityNudge(
                            onDismiss: () {
                              unawaited(_dismissGroupChatVisibilityNudge());
                            },
                          ),
                        ),
                      ]
                    : const <Widget>[];

                List<Widget> adminSlivers() {
                  if (adminOnlyConversations.isEmpty) return const [];
                  return _buildCategorySlivers(
                    context: context,
                    theme: theme,
                    label: context.l10n.chatAdminNonParticipantSection,
                    conversations: adminOnlyConversations,
                    speakingAs: speakingAs,
                    speakingAsMember: speakingAsMember,
                  );
                }

                // No categories: flat list, then admin section if any.
                if (categories.isEmpty) {
                  return [
                    ...visibilityNudgeSlivers,
                    ..._buildCategorySlivers(
                      context: context,
                      theme: theme,
                      label: null,
                      conversations: participantConversations,
                      speakingAs: speakingAs,
                      speakingAsMember: speakingAsMember,
                    ),
                    ...adminSlivers(),
                  ];
                }

                // Group conversations by category.
                final grouped = <String?, List<Conversation>>{};
                for (final cat in categories) {
                  grouped[cat.id] = [];
                }
                grouped[null] = []; // uncategorized

                for (final conv in participantConversations) {
                  if (conv.categoryId != null &&
                      grouped.containsKey(conv.categoryId)) {
                    grouped[conv.categoryId]!.add(conv);
                  } else {
                    grouped[null]!.add(conv);
                  }
                }

                final categoryMap = {
                  for (final cat in categories) cat.id: cat.name,
                };

                final slivers = <Widget>[];
                slivers.addAll(visibilityNudgeSlivers);
                // Category groups in display order
                for (final cat in categories) {
                  if (grouped[cat.id]!.isNotEmpty) {
                    slivers.addAll(
                      _buildCategorySlivers(
                        context: context,
                        theme: theme,
                        label: categoryMap[cat.id],
                        conversations: grouped[cat.id]!,
                        speakingAs: speakingAs,
                        speakingAsMember: speakingAsMember,
                      ),
                    );
                  }
                }
                // Uncategorized at the bottom
                if (grouped[null]!.isNotEmpty) {
                  slivers.addAll(
                    _buildCategorySlivers(
                      context: context,
                      theme: theme,
                      label: categories.isNotEmpty
                          ? context.l10n.chatUncategorized
                          : null,
                      conversations: grouped[null]!,
                      speakingAs: speakingAs,
                      speakingAsMember: speakingAsMember,
                    ),
                  );
                }
                slivers.addAll(adminSlivers());
                return slivers;
              },
              loading: () => [const PrismLoadingState.sliver()],
              error: (error, _) => [
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.errorOutline,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.chatErrorLoadingConversations,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('$error', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Bottom padding to clear floating nav bar
            SliverPadding(
              padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteConversation(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.chatDeleteConversationTitle,
      message: context.l10n.chatDeleteConversationMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!confirmed) return false;
    Haptics.heavy();
    unawaited(
      ref
          .read(chatNotifierProvider.notifier)
          .deleteConversation(conversation.id),
    );
    return true;
  }

  void _showCreateSheet(BuildContext context) async {
    final conversationId = await PrismSheet.showFullScreen<String>(
      context: context,
      builder: (context, scrollController) => CreateConversationSheet(
        scrollController: scrollController,
        initialIsGroupChat: _activeTab == _ChatSubTab.groupChats,
      ),
    );

    if (conversationId != null && context.mounted) {
      context.go(AppRoutePaths.chatConversation(conversationId));
    }
  }
}

class _GroupChatVisibilityNudge extends StatelessWidget {
  const _GroupChatVisibilityNudge({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: InfoBanner(
        icon: AppIcons.visibilityOutlined,
        iconColor: iconColor,
        backgroundColor: iconColor.withValues(alpha: 0.1),
        title: context.l10n.chatGroupVisibilityNudgeTitle,
        message: context.l10n.chatGroupVisibilityNudgeMessage,
        dismissTooltip: context.l10n.dismiss,
        onDismiss: onDismiss,
      ),
    );
  }
}

class _PickSpeakerBanner extends StatelessWidget {
  const _PickSpeakerBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.chatPickSpeakerBanner,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _ChatTopBar({
    required this.activeTab,
    required this.onTabSelected,
    required this.speakingAs,
    required this.hasArchived,
    required this.showArchived,
    required this.onSearchTap,
    required this.onArchiveTap,
    required this.onCreateTap,
  });

  final _ChatSubTab activeTab;
  final ValueChanged<_ChatSubTab> onTabSelected;
  final String? speakingAs;
  final bool hasArchived;
  final bool showArchived;
  final VoidCallback onSearchTap;
  final VoidCallback onArchiveTap;
  final VoidCallback onCreateTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmUnread = ref.watch(unreadDmCountProvider);
    final groupUnread = ref.watch(unreadGroupCountProvider);
    return Column(
      children: [
        PrismTopBar(
          title: context.l10n.chatTitle,
          leading: const _ChatMemberSelectorButton(),
          actions: [
            PrismTopBarAction(
              icon: AppIcons.add,
              tooltip: context.l10n.chatNewConversation,
              onPressed: onCreateTap,
            ),
            _OverflowMenuButton(
              speakingAs: speakingAs,
              hasArchived: hasArchived,
              showArchived: showArchived,
              onSearchTap: onSearchTap,
              onArchiveTap: onArchiveTap,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: PrismSegmentedControl<_ChatSubTab>(
            segments: [
              PrismSegment(
                value: _ChatSubTab.groupChats,
                label: context.l10n.chatTabGroupChats,
                badgeCount: groupUnread,
                badgeSemanticLabel: groupUnread > 0
                    ? context.l10n.chatUnreadGroupsBadge(groupUnread)
                    : null,
              ),
              PrismSegment(
                value: _ChatSubTab.directMessages,
                label: context.l10n.chatTabDirectMessages,
                badgeCount: dmUnread,
                badgeSemanticLabel: dmUnread > 0
                    ? context.l10n.chatUnreadDmsBadge(dmUnread)
                    : null,
              ),
            ],
            selected: activeTab,
            onChanged: onTabSelected,
          ),
        ),
      ],
    );
  }
}

class _ChatMemberSelectorButton extends ConsumerWidget {
  const _ChatMemberSelectorButton();

  static const _selectorKey = Key('chatSpeakingAsAppBarSelector');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(userVisibleMembersProvider);
    final speakingAs = ref.watch(speakingAsProvider);
    final terms = watchTerminology(context, ref);

    return membersAsync.when(
      data: (members) {
        final authorOptions = withUnknownChatAuthorOption(context, members);
        final selected = findChatAuthorOption(
          context,
          authorOptions,
          speakingAs,
        );
        final groups = watchMemberSearchGroups(ref, authorOptions);
        final semanticLabel = selected != null
            ? context.l10n.chatSpeakingAs(selected.name)
            : context.l10n.chatChooseSpeakingMember(terms.singularLower);

        return Semantics(
          label: semanticLabel,
          button: true,
          enabled: authorOptions.isNotEmpty,
          child: Tooltip(
            message: semanticLabel,
            child: MemberSelectorPopup(
              key: _selectorKey,
              preferredDirection: BlurPopupDirection.down,
              enabled: authorOptions.isNotEmpty,
              members: authorOptions,
              termPlural: terms.plural,
              searchTitle: context.l10n.selectMember(terms.singular),
              selectedMemberId: speakingAs,
              groups: groups,
              onMemberSelected: (memberId) =>
                  ref.read(speakingAsProvider.notifier).setMember(memberId),
              child: _ChatMemberSelectorTrigger(
                selectedMember: selected,
                enabled: authorOptions.isNotEmpty,
              ),
            ),
          ),
        );
      },
      loading: () => const _ChatMemberSelectorTrigger(enabled: false),
      error: (_, _) => const _ChatMemberSelectorTrigger(enabled: false),
    );
  }
}

class _ChatMemberSelectorTrigger extends StatelessWidget {
  const _ChatMemberSelectorTrigger({
    this.selectedMember,
    required this.enabled,
  });

  final Member? selectedMember;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const hitSize = PrismTokens.topBarActionSize;
    const pipSize = 14.0;
    final member = selectedMember;

    return SizedBox(
      width: hitSize,
      height: hitSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (member != null)
            MemberAvatar(
              avatarImageData: member.avatarImageData,
              memberName: member.name,
              emoji: member.emoji,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: hitSize,
            )
          else
            Container(
              width: hitSize,
              height: hitSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: enabled ? 1 : 0.55,
                ),
              ),
              child: Icon(
                AppIcons.personOutline,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: enabled ? 1 : 0.55,
                ),
              ),
            ),
          if (enabled)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: pipSize,
                height: pipSize,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  AppIcons.expandMore,
                  size: 11,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.85,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ChatMenuAction { search, toggleArchived, markAllRead, manageCategories }

class _OverflowMenuButton extends ConsumerWidget {
  const _OverflowMenuButton({
    required this.speakingAs,
    required this.hasArchived,
    required this.showArchived,
    required this.onSearchTap,
    required this.onArchiveTap,
  });

  final String? speakingAs;
  final bool hasArchived;
  final bool showArchived;
  final VoidCallback onSearchTap;
  final VoidCallback onArchiveTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PrismPopupMenu<_ChatMenuAction>(
      width: 240,
      maxHeight: 224,
      items: [
        PrismMenuItem(
          value: _ChatMenuAction.search,
          label: l10n.chatSearchMessages,
          icon: AppIcons.search,
        ),
        if (hasArchived || showArchived)
          PrismMenuItem(
            value: _ChatMenuAction.toggleArchived,
            label: showArchived ? l10n.chatHideArchived : l10n.chatShowArchived,
            icon: showArchived
                ? AppIcons.inventoryRounded
                : AppIcons.inventoryOutlined,
          ),
        PrismMenuItem(
          value: _ChatMenuAction.markAllRead,
          label: l10n.chatMarkAllAsRead,
          icon: AppIcons.markEmailReadOutlined,
        ),
        PrismMenuItem(
          value: _ChatMenuAction.manageCategories,
          label: l10n.chatManageCategories,
          icon: AppIcons.folderOutlined,
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _ChatMenuAction.search:
            onSearchTap();
          case _ChatMenuAction.toggleArchived:
            onArchiveTap();
          case _ChatMenuAction.markAllRead:
            final id = speakingAs;
            if (id != null) {
              ref
                  .read(chatNotifierProvider.notifier)
                  .markAllConversationsAsRead(id);
            }
          case _ChatMenuAction.manageCategories:
            CategoryManagementSheet.show(context);
        }
      },
    );
  }
}
