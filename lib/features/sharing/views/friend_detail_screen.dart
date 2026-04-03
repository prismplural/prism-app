import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Detail screen for a single friend — scope management, verification,
/// and revocation.
class FriendDetailScreen extends ConsumerWidget {
  const FriendDetailScreen({super.key, required this.friendId});

  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final friend = friends.where((f) => f.id == friendId).firstOrNull;

    if (friend == null) {
      return const PrismPageScaffold(
        topBar: PrismTopBar(title: 'Friend', showBackButton: true),
        body: Center(child: Text('Friend not found')),
      );
    }

    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: friend.displayName, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          // ── Header ──────────────────────────────────────
          _FriendHeader(friend: friend),

          const Divider(height: 32),

          // ── Verification ────────────────────────────────
          if (!friend.isVerified)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _VerifyCard(
                friend: friend,
                onVerified: () {
                  ref.read(friendsProvider.notifier).updateFriend(
                        friend.copyWith(isVerified: true),
                      );
                },
              ),
            ),

          if (!friend.isVerified) const SizedBox(height: 16),

          // ── Scope toggles ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Granted Scopes',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...ShareScope.values.map(
            (scope) => _ScopeToggle(
              scope: scope,
              isEnabled: friend.grantedScopes.contains(scope),
              onChanged: (enabled) {
                final scopes = List<ShareScope>.from(friend.grantedScopes);
                if (enabled) {
                  scopes.add(scope);
                } else {
                  scopes.remove(scope);
                }
                ref.read(friendsProvider.notifier).updateFriend(
                      friend.copyWith(grantedScopes: scopes),
                    );
              },
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),

          // ── Public key ─────────────────────────────────
          ListTile(
            leading: Icon(AppIcons.key),
            title: const Text('Public Key'),
            subtitle: Text(
              _truncateKey(friend.publicKeyHex),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            trailing: IconButton(
              icon: Icon(AppIcons.copy, size: 20),
              tooltip: 'Copy public key',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: friend.publicKeyHex));
                PrismToast.show(context, message: 'Public key copied');
              },
            ),
          ),

          // ── Last sync ──────────────────────────────────
          if (friend.lastSyncAt != null)
            ListTile(
              leading: Icon(AppIcons.sync),
              title: const Text('Last synced'),
              subtitle: Text(
                friend.lastSyncAt!.toLocal().toString().split('.').first,
              ),
            ),

          const SizedBox(height: 24),

          // ── Revoke ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PrismButton(
              onPressed: () => _confirmRevoke(context, ref, friend),
              icon: AppIcons.block,
              label: 'Revoke Access',
              tone: PrismButtonTone.destructive,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateKey(String hex) {
    if (hex.length <= 16) return hex;
    return '${hex.substring(0, 8)}...${hex.substring(hex.length - 8)}';
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref, Friend friend) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Revoke access',
      message: 'Revoke all access for ${friend.displayName}? '
          'Resource keys will be rotated.',
      confirmLabel: 'Revoke',
      destructive: true,
    );
    if (confirmed) {
      ref.read(friendsProvider.notifier).removeFriend(friend.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _FriendHeader extends StatelessWidget {
  const _FriendHeader({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            child: Text(
              friend.displayName.isNotEmpty
                  ? friend.displayName[0].toUpperCase()
                  : '?',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        friend.displayName,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (friend.isVerified) ...[
                      const SizedBox(width: 8),
                      Icon(
                        AppIcons.verified,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  friend.isVerified ? 'Verified' : 'Not verified',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: friend.isVerified
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
                Text(
                  'Added ${friend.addedAt.toLocal().toString().split(' ').first}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyCard extends ConsumerWidget {
  const _VerifyCard({required this.friend, required this.onVerified});

  final Friend friend;
  final VoidCallback onVerified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.warningAmber, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'Verification Required',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Compare the verification code with your friend '
              'to confirm a secure connection.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            PrismButton(
              onPressed: () => _showSasDialog(context, ref),
              label: 'Verify Now',
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSasDialog(BuildContext context, WidgetRef ref) async {
    final sharingService = ref.read(sharingServiceProvider);
    if (sharingService == null) {
      PrismToast.error(context, message: 'Sync is not configured');
      return;
    }
    String? sasCode;
    try {
      sasCode = await sharingService.getSasCodeForFriend(friend);
    } catch (_) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Unable to generate verification code');
      return;
    }

    if (!context.mounted) return;
    PrismDialog.show(
      context: context,
      title: 'Verification Code',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Share this code with ${friend.displayName} and confirm '
            'they see the same number.',
          ),
          const SizedBox(height: 24),
          Text(
            sasCode!,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Do NOT confirm if the codes don\'t match.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
      ),
      actions: [
        PrismButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Cancel',
          tone: PrismButtonTone.subtle,
        ),
        PrismButton(
          onPressed: () {
            onVerified();
            Navigator.of(context).pop();
          },
          label: 'Codes Match',
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }
}

class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({
    required this.scope,
    required this.isEnabled,
    required this.onChanged,
  });

  final ShareScope scope;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PrismSwitchRow(
      icon: scope.icon,
      title: scope.displayName,
      subtitle: scope.description,
      value: isEnabled,
      onChanged: onChanged,
    );
  }
}
