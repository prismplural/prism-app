import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/category_management_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/conversation_tile.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

const _kLastChatSubTabKey = 'chat.last_sub_tab';
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
  _ChatSubTab _activeTab = _ChatSubTab.groupChats;

  @override
  void initState() {
    super.initState();
    _loadSavedTab();
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
    if (_seeded || conversations.isNotEmpty) return;
    _seeded = true;

    // Don't seed the default conversation creator as the Unknown sentinel —
    // pick from real, user-visible members only.
    final members = ref.read(userVisibleMembersProvider).value;
    if (members == null || members.isEmpty) return;

    final terms = readTerminology(context, ref);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(chatNotifierProvider.notifier)
          .createGroupConversation(
            title: 'All ${terms.plural}',
            emoji: '💬',
            creatorId: members.first.id,
            participantIds: members.map((m) => m.id).toList(),
          );
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

                if (conversations.isEmpty || visibleConversations.isEmpty) {
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

                // If no categories exist, show flat list.
                if (categories.isEmpty) {
                  return _buildCategorySlivers(
                    context: context,
                    theme: theme,
                    label: null,
                    conversations: visibleConversations,
                    speakingAs: speakingAs,
                    speakingAsMember: speakingAsMember,
                  );
                }

                // Group conversations by category.
                final grouped = <String?, List<Conversation>>{};
                for (final cat in categories) {
                  grouped[cat.id] = [];
                }
                grouped[null] = []; // uncategorized

                for (final conv in visibleConversations) {
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

class _ChatTopBar extends StatelessWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        PrismTopBar(
          title: context.l10n.chatTitle,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OverflowMenuButton(speakingAs: speakingAs),
              const SizedBox(width: 8),
              PrismTopBarAction(
                icon: AppIcons.search,
                tooltip: context.l10n.chatSearchMessages,
                onPressed: onSearchTap,
              ),
            ],
          ),
          actions: [
            if (hasArchived || showArchived)
              PrismTopBarAction(
                icon: showArchived
                    ? AppIcons.inventoryRounded
                    : AppIcons.inventoryOutlined,
                tooltip: showArchived
                    ? context.l10n.chatHideArchived
                    : context.l10n.chatShowArchived,
                onPressed: onArchiveTap,
              ),
            PrismTopBarAction(
              icon: AppIcons.add,
              tooltip: context.l10n.chatNewConversation,
              onPressed: onCreateTap,
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
              ),
              PrismSegment(
                value: _ChatSubTab.directMessages,
                label: context.l10n.chatTabDirectMessages,
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

class _OverflowMenuButton extends ConsumerStatefulWidget {
  const _OverflowMenuButton({required this.speakingAs});

  final String? speakingAs;

  @override
  ConsumerState<_OverflowMenuButton> createState() =>
      _OverflowMenuButtonState();
}

class _OverflowMenuButtonState extends ConsumerState<_OverflowMenuButton> {
  final _popupKey = GlobalKey<BlurPopupAnchorState>();

  @override
  Widget build(BuildContext context) {
    final speakingAs = widget.speakingAs;
    return BlurPopupAnchor(
      key: _popupKey,
      trigger: BlurPopupTrigger.manual,
      width: 220,
      maxHeight: 112,
      itemCount: 2,
      semanticLabel: context.l10n.moreOptions,
      itemBuilder: (ctx, index, close) {
        final popupTheme = Theme.of(ctx);
        return switch (index) {
          0 => PrismListRow(
            dense: true,
            leading: Icon(AppIcons.markEmailReadOutlined, size: 20),
            title: Text(
              ctx.l10n.chatMarkAllAsRead,
              style: popupTheme.textTheme.bodyMedium,
            ),
            onTap: () {
              close();
              if (speakingAs != null) {
                ref
                    .read(chatNotifierProvider.notifier)
                    .markAllConversationsAsRead(speakingAs);
              }
            },
          ),
          _ => PrismListRow(
            dense: true,
            leading: Icon(AppIcons.folderOutlined, size: 20),
            title: Text(
              ctx.l10n.chatManageCategories,
              style: popupTheme.textTheme.bodyMedium,
            ),
            onTap: () {
              close();
              CategoryManagementSheet.show(context);
            },
          ),
        };
      },
      child: PrismTopBarAction(
        icon: AppIcons.moreVert,
        tooltip: context.l10n.moreOptions,
        onPressed: () => _popupKey.currentState?.show(),
      ),
    );
  }
}
