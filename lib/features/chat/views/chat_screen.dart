import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/providers/category_providers.dart';
import 'package:prism_plurality/features/chat/views/create_conversation_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/category_management_sheet.dart';
import 'package:prism_plurality/features/chat/widgets/conversation_tile.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

/// Main conversation list screen.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _seeded = false;

  /// Create a default "All [Members]" conversation if none exist yet.
  void _seedDefaultConversation(List<Conversation> conversations) {
    if (_seeded || conversations.isNotEmpty) return;
    _seeded = true;

    final members = ref.read(activeMembersProvider).value;
    if (members == null || members.isEmpty) return;

    final terms = ref.read(terminologyProvider);

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
  ) {
    return BlurPopupAnchor(
      trigger: BlurPopupTrigger.longPress,
      width: 240,
      maxHeight: 180,
      itemCount: 3,
      itemBuilder: (ctx, index, close) {
        final isMuted = speakingAs != null &&
            conversation.mutedByMemberIds.contains(speakingAs);
        final popupTheme = Theme.of(ctx);
        return switch (index) {
          0 => ListTile(
              dense: true,
              leading: const Icon(
                AppIcons.markEmailReadOutlined,
                size: 20,
              ),
              title: const Text(
                'Mark as Read',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                close();
                if (speakingAs != null) {
                  ref
                      .read(chatNotifierProvider.notifier)
                      .markConversationAsRead(conversation.id, speakingAs);
                }
              },
            ),
          1 => ListTile(
              dense: true,
              leading: Icon(
                isMuted
                    ? AppIcons.notificationsOutlined
                    : AppIcons.notificationsOffOutlined,
                size: 20,
              ),
              title: Text(
                isMuted ? 'Unmute' : 'Mute',
                style: const TextStyle(fontSize: 14),
              ),
              onTap: () {
                close();
                if (speakingAs != null) {
                  ref
                      .read(chatNotifierProvider.notifier)
                      .toggleMute(conversation.id, speakingAs);
                }
              },
            ),
          _ => ListTile(
              dense: true,
              leading: Icon(
                AppIcons.deleteOutline,
                size: 20,
                color: popupTheme.colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(
                  fontSize: 14,
                  color: popupTheme.colorScheme.error,
                ),
              ),
              onTap: () {
                close();
                _confirmDeleteConversation(context, ref, conversation);
              },
            ),
        };
      },
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
  }) {
    final baseColor = theme.colorScheme.onSurface.withValues(alpha: 1);
    final backgroundColor = baseColor.withValues(alpha: 0.08);
    final borderColor = baseColor.withValues(alpha: 0.1);
    final borderRadius = BorderRadius.circular(PrismTokens.radiusMedium);

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
              return Dismissible(
                key: ValueKey(conversations[index].id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: theme.colorScheme.error,
                  child: Icon(
                    AppIcons.delete,
                    color: theme.colorScheme.onError,
                  ),
                ),
                confirmDismiss: (_) => _confirmDeleteConversation(
                  context,
                  ref,
                  conversations[index],
                ),
                child: _buildConversationTile(
                  context,
                  theme,
                  conversations[index],
                  speakingAs,
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
    final categoriesAsync = ref.watch(conversationCategoriesProvider);
    final badgePrefs = ref.watch(chatBadgePreferencesProvider);
    final isMentionsOnly = speakingAs != null &&
        badgePrefs[speakingAs] == 'mentions_only';
    ref.watch(activeMembersProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(conversationsProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverPinnedTopBar(
              child: PrismTopBar(
                title: 'Chat',
                leading: PrismTopBarAction(
                  icon: AppIcons.folderOutlined,
                  tooltip: 'Manage categories',
                  onPressed: () =>
                      CategoryManagementSheet.show(context),
                ),
                actions: [
                  if (speakingAs != null)
                    PrismTopBarAction(
                      icon: isMentionsOnly
                          ? AppIcons.alternateEmail
                          : AppIcons.markChatUnreadOutlined,
                      tooltip: isMentionsOnly
                          ? 'Badge: mentions only'
                          : 'Badge: all messages',
                      onPressed: () {
                        final newPrefs = Map<String, String>.from(badgePrefs);
                        if (isMentionsOnly) {
                          newPrefs.remove(speakingAs);
                        } else {
                          newPrefs[speakingAs] = 'mentions_only';
                        }
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .updateChatBadgePreferences(newPrefs);
                      },
                    ),
                  PrismTopBarAction(
                    icon: AppIcons.search,
                    tooltip: 'Search messages',
                    onPressed: () => context.go('${AppRoutePaths.chat}/search'),
                  ),
                  if (hasArchived || showArchived)
                    PrismTopBarAction(
                      icon: showArchived
                          ? AppIcons.inventoryRounded
                          : AppIcons.inventoryOutlined,
                      tooltip: showArchived ? 'Hide archived' : 'Show archived',
                      onPressed: () =>
                          ref.read(showArchivedProvider.notifier).toggle(),
                    ),
                  PrismTopBarAction(
                    icon: AppIcons.add,
                    tooltip: 'New conversation',
                    onPressed: () => _showCreateSheet(context),
                  ),
                ],
              ),
            ),

            // Conversation list
            ...conversationsAsync.when(
              data: (conversations) {
                _seedDefaultConversation(conversations);

                if (conversations.isEmpty) {
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: AppIcons.chatBubbleOutline,
                        title: 'No conversations',
                        subtitle: 'Start chatting with your system',
                        actionLabel: 'New Conversation',
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
                    conversations: conversations,
                    speakingAs: speakingAs,
                  );
                }

                // Group conversations by category.
                final grouped = <String?, List<Conversation>>{};
                for (final cat in categories) {
                  grouped[cat.id] = [];
                }
                grouped[null] = []; // uncategorized

                for (final conv in conversations) {
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
                    slivers.addAll(_buildCategorySlivers(
                      context: context,
                      theme: theme,
                      label: categoryMap[cat.id],
                      conversations: grouped[cat.id]!,
                      speakingAs: speakingAs,
                    ));
                  }
                }
                // Uncategorized at the bottom
                if (grouped[null]!.isNotEmpty) {
                  slivers.addAll(_buildCategorySlivers(
                    context: context,
                    theme: theme,
                    label: categories.isNotEmpty
                        ? 'Uncategorized'
                        : null,
                    conversations: grouped[null]!,
                    speakingAs: speakingAs,
                  ));
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
                          'Error loading conversations',
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
      title: 'Delete Conversation',
      message: 'Are you sure you want to delete this conversation? All messages will be permanently removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return false;
    Haptics.heavy();
    ref
        .read(chatNotifierProvider.notifier)
        .deleteConversation(conversation.id);
    return true;
  }


  void _showCreateSheet(BuildContext context) async {
    final conversationId = await PrismSheet.showFullScreen<String>(
      context: context,
      builder: (context, scrollController) => CreateConversationSheet(
        scrollController: scrollController,
      ),
    );

    if (conversationId != null && context.mounted) {
      context.go(AppRoutePaths.chatConversation(conversationId));
    }
  }
}
