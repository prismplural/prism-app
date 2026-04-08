import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Detail screen for a single sharing relationship.
class FriendDetailScreen extends ConsumerWidget {
  const FriendDetailScreen({super.key, required this.friendId});

  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    Friend? friend;
    for (final candidate in friends) {
      if (candidate.id == friendId) {
        friend = candidate;
        break;
      }
    }

    if (friend == null) {
      return const PrismPageScaffold(
        topBar: PrismTopBar(title: 'Friend', showBackButton: true),
        body: Center(child: Text('Friend not found')),
      );
    }
    final resolvedFriend = friend;

    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: resolvedFriend.displayName,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          _FriendHeader(friend: resolvedFriend),
          const Divider(height: 32),
          if (!resolvedFriend.isVerified)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _VerifyCard(
                friend: resolvedFriend,
                onVerified: () {
                  ref
                      .read(friendsProvider.notifier)
                      .updateFriend(resolvedFriend.copyWith(isVerified: true));
                },
              ),
            ),
          if (!resolvedFriend.isVerified) const SizedBox(height: 16),
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
              isEnabled: resolvedFriend.grantedScopes.contains(scope),
              onChanged: (enabled) {
                final scopes = List<ShareScope>.from(
                  resolvedFriend.grantedScopes,
                );
                if (enabled) {
                  scopes.add(scope);
                } else {
                  scopes.remove(scope);
                }
                ref
                    .read(friendsProvider.notifier)
                    .updateFriend(
                      resolvedFriend.copyWith(grantedScopes: scopes),
                    );
              },
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          if ((resolvedFriend.peerSharingId ?? '').isNotEmpty)
            PrismListRow(
              leading: Icon(AppIcons.link),
              title: const Text('Sharing ID'),
              subtitle: Text(
                resolvedFriend.peerSharingId!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              trailing: PrismInlineIconButton(
                icon: AppIcons.copy,
                iconSize: 20,
                tooltip: 'Copy sharing ID',
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: resolvedFriend.peerSharingId!),
                  );
                  PrismToast.show(context, message: 'Sharing ID copied');
                },
              ),
            ),
          _FingerprintRow(friend: resolvedFriend),
          if (resolvedFriend.lastSyncAt != null)
            PrismListRow(
              leading: Icon(AppIcons.sync),
              title: const Text('Last synced'),
              subtitle: Text(
                resolvedFriend.lastSyncAt!
                    .toLocal()
                    .toString()
                    .split('.')
                    .first,
              ),
            ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PrismButton(
              onPressed: () => _confirmRevoke(context, ref, resolvedFriend),
              icon: AppIcons.block,
              label: 'Revoke Access',
              tone: PrismButtonTone.destructive,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    Friend friend,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Revoke access',
      message:
          'Revoke all access for ${friend.displayName}? Resource keys will be rotated.',
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
                  'Added ${(friend.establishedAt ?? friend.addedAt).toLocal().toString().split(' ').first}',
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
                  'Verification Recommended',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Compare fingerprints with ${friend.displayName} out of band before marking this relationship as verified.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            PrismButton(
              onPressed: () => _showFingerprintDialog(context, ref),
              label: 'Compare Fingerprint',
              tone: PrismButtonTone.filled,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFingerprintDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final sharingService = ref.read(sharingServiceProvider);
    if (sharingService == null) {
      PrismToast.error(context, message: 'Sync is not configured');
      return;
    }

    String fingerprint;
    try {
      fingerprint = await sharingService.fingerprintForFriend(friend);
    } catch (_) {
      if (!context.mounted) return;
      PrismToast.error(context, message: 'Unable to compute fingerprint');
      return;
    }

    if (!context.mounted) return;
    PrismDialog.show(
      context: context,
      title: 'Security Fingerprint',
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Compare this fingerprint with ${friend.displayName}. Only mark it verified if they see the same value.',
          ),
          const SizedBox(height: 24),
          SelectableText(
            fingerprint,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Do not verify if the fingerprints differ.',
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
          label: 'Mark Verified',
          tone: PrismButtonTone.filled,
        ),
      ],
    );
  }
}

class _FingerprintRow extends ConsumerWidget {
  const _FingerprintRow({required this.friend});

  final Friend friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharingService = ref.watch(sharingServiceProvider);
    return FutureBuilder<String>(
      future: sharingService?.fingerprintForFriend(friend),
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final fallback = friend.publicKeyHex;
        final label = snapshot.hasData ? 'Fingerprint' : 'Identity';
        final value = snapshot.data ?? _truncate(fallback);
        return PrismListRow(
          leading: Icon(snapshot.hasData ? AppIcons.fingerprint : AppIcons.key),
          title: Text(label),
          subtitle: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          trailing: PrismInlineIconButton(
            icon: AppIcons.copy,
            iconSize: 20,
            tooltip: 'Copy $label',
            onPressed: () {
              final text = snapshot.data ?? fallback;
              Clipboard.setData(ClipboardData(text: text));
              PrismToast.show(context, message: '$label copied');
            },
          ),
        );
      },
    );
  }

  String _truncate(String value) {
    if (value.length <= 20) return value;
    return '${value.substring(0, 10)}...${value.substring(value.length - 10)}';
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
