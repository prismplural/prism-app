import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/sharing/views/create_invite_sheet.dart';

/// Main sharing screen showing the friends list and invite controls.
class SharingScreen extends ConsumerWidget {
  const SharingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Sharing',
        showBackButton: true,
        trailing: PrismTopBarAction(
          icon: Icons.person_add,
          tooltip: 'Create invite',
          onPressed: () => _showCreateInvite(context),
        ),
      ),
      bodyPadding: EdgeInsets.zero,
      body: friends.isEmpty
          ? _EmptyState(onCreateInvite: () => _showCreateInvite(context))
          : ListView.builder(
              padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
              itemCount: friends.length,
              itemBuilder: (context, index) => _FriendTile(
                friend: friends[index],
                onTap: () => context.go(
                  '/settings/sharing/${friends[index].id}',
                ),
                onDelete: () => _confirmDelete(context, ref, friends[index]),
              ),
            ),
    );
  }

  void _showCreateInvite(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateInviteSheet(
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Friend friend) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Remove friend',
      message: 'Remove ${friend.displayName} and revoke their access? '
          'This cannot be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) {
      ref.read(friendsProvider.notifier).removeFriend(friend.id);
    }
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({
    required this.friend,
    required this.onTap,
    required this.onDelete,
  });

  final Friend friend;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highestScope = friend.grantedScopes.isNotEmpty
        ? (friend.grantedScopes.toList()
              ..sort((a, b) => b.index.compareTo(a.index)))
            .first
        : null;

    return Dismissible(
      key: ValueKey(friend.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // Dialog handles removal
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.withValues(alpha: 0.2),
        child: Icon(Icons.delete, color: Colors.red.withValues(alpha: 0.8)),
      ),
      child: PrismListRow(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          foregroundColor: theme.colorScheme.onSurface,
          child: Text(
            friend.displayName.isNotEmpty
                ? friend.displayName[0].toUpperCase()
                : '?',
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(friend.displayName)),
            if (friend.isVerified) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.verified,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
        subtitle: Text(
          highestScope?.displayName ?? 'No scopes granted',
          style: theme.textTheme.bodySmall,
        ),
        trailing: friend.lastSyncAt != null
            ? Text(
                _formatRelativeTime(friend.lastSyncAt!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateInvite});

  final VoidCallback onCreateInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.share_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create an invite to share your system info '
              'with trusted friends.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            PrismButton(
              label: 'Create Invite',
              icon: Icons.person_add,
              onPressed: onCreateInvite,
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }
}
