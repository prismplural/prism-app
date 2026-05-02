import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Detail screen for a single sharing relationship.
class FriendDetailScreen extends ConsumerWidget {
  const FriendDetailScreen({super.key, required this.friendId});

  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final terms = watchTerminology(context, ref);
    Friend? friend;
    for (final candidate in friends) {
      if (candidate.id == friendId) {
        friend = candidate;
        break;
      }
    }

    if (friend == null) {
      return PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.sharingFriend,
          showBackButton: true,
        ),
        body: Center(child: Text(context.l10n.sharingFriendNotFound)),
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
              context.l10n.sharingGrantedScopes,
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
              termSingular: terms.singular,
              termPlural: terms.plural,
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
              title: Text(context.l10n.sharingSharingId),
              subtitle: Text(
                resolvedFriend.peerSharingId!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              trailing: PrismInlineIconButton(
                icon: AppIcons.copy,
                iconSize: 20,
                tooltip: context.l10n.sharingCopySharingId,
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: resolvedFriend.peerSharingId!),
                  );
                  PrismToast.show(
                    context,
                    message: context.l10n.sharingSharingIdCopied,
                  );
                },
              ),
            ),
          _FingerprintRow(friend: resolvedFriend),
          if (resolvedFriend.lastSyncAt != null)
            PrismListRow(
              leading: Icon(AppIcons.sync),
              title: Text(context.l10n.sharingLastSynced),
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
              label: context.l10n.sharingRevokeAccess,
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
      title: context.l10n.sharingRevokeTitle,
      message: context.l10n.sharingRevokeMessage(friend.displayName),
      confirmLabel: context.l10n.sharingRevoke,
      destructive: true,
    );
    if (confirmed) {
      unawaited(ref.read(friendsProvider.notifier).removeFriend(friend.id));
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
                  friend.isVerified
                      ? context.l10n.sharingVerified
                      : context.l10n.sharingNotVerified,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: friend.isVerified
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
                Text(
                  context.l10n.sharingAddedDate(
                    (friend.establishedAt ?? friend.addedAt)
                        .toLocal()
                        .toString()
                        .split(' ')
                        .first,
                  ),
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

    return PrismSurface(
      fillColor: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.warningAmber, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text(
                context.l10n.sharingVerificationRecommended,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.sharingVerificationDescription(friend.displayName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          PrismButton(
            onPressed: () => _showFingerprintDialog(context, ref),
            label: context.l10n.sharingCompareFingerprint,
            tone: PrismButtonTone.filled,
          ),
        ],
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
      PrismToast.error(
        context,
        message: context.l10n.sharingUnableToComputeFingerprint,
      );
      return;
    }

    if (!context.mounted) return;
    unawaited(
      PrismDialog.show(
        context: context,
        title: context.l10n.sharingSecurityFingerprintTitle,
        builder: (_) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.sharingFingerprintCompareText(friend.displayName),
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
              context.l10n.sharingFingerprintWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        actions: [
          PrismButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            label: context.l10n.cancel,
            tone: PrismButtonTone.subtle,
          ),
          PrismButton(
            onPressed: () {
              onVerified();
              Navigator.of(context, rootNavigator: true).pop();
            },
            label: context.l10n.sharingMarkVerified,
            tone: PrismButtonTone.filled,
          ),
        ],
      ),
    );
  }
}

class _FingerprintRow extends ConsumerStatefulWidget {
  const _FingerprintRow({required this.friend});

  final Friend friend;

  @override
  ConsumerState<_FingerprintRow> createState() => _FingerprintRowState();
}

class _FingerprintRowState extends ConsumerState<_FingerprintRow> {
  Future<String>? _fingerprintFuture;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(covariant _FingerprintRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.friend.publicKeyHex != widget.friend.publicKeyHex) {
      _initFuture();
    }
  }

  void _initFuture() {
    final sharingService = ref.read(sharingServiceProvider);
    _fingerprintFuture = sharingService?.fingerprintForFriend(widget.friend);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = widget.friend.publicKeyHex;

    return FutureBuilder<String>(
      future: _fingerprintFuture,
      builder: (context, snapshot) {
        final label = snapshot.hasData
            ? context.l10n.sharingFingerprint
            : context.l10n.sharingIdentity;
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
            tooltip: context.l10n.sharingCopyLabel(label),
            onPressed: () {
              final text = snapshot.data ?? fallback;
              Clipboard.setData(ClipboardData(text: text));
              PrismToast.show(
                context,
                message: context.l10n.sharingFingerprintCopied(label),
              );
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
    required this.termSingular,
    required this.termPlural,
    required this.isEnabled,
    required this.onChanged,
  });

  final ShareScope scope;
  final String termSingular;
  final String termPlural;
  final bool isEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PrismSwitchRow(
      icon: scope.icon,
      title: scope.displayNameFor(termPlural: termPlural),
      subtitle: scope.descriptionFor(termSingular: termSingular),
      value: isEnabled,
      onChanged: onChanged,
    );
  }
}
