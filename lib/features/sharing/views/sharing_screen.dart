import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/sharing/friend.dart';
import 'package:prism_plurality/core/sharing/pending_sharing_request.dart';
import 'package:prism_plurality/core/sharing/share_scope.dart';
import 'package:prism_plurality/core/sharing/sharing_providers.dart';
import 'package:prism_plurality/core/sharing/sharing_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/features/sharing/views/accept_invite_sheet.dart';
import 'package:prism_plurality/features/sharing/views/create_invite_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';

/// Main sharing screen showing pending requests and established relationships.
class SharingScreen extends ConsumerStatefulWidget {
  const SharingScreen({super.key});

  @override
  ConsumerState<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends ConsumerState<SharingScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshInbox(showNoopToast: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final pendingAsync = ref.watch(pendingSharingRequestsProvider);
    final pending = pendingAsync.value ?? const <PendingSharingRequest>[];
    final terms = watchTerminology(context, ref);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.sharingTitle,
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.refresh,
            tooltip: context.l10n.sharingRefreshInbox,
            onPressed: _refreshing
                ? null
                : () => _refreshInbox(showNoopToast: true),
          ),
          PrismTopBarAction(
            icon: AppIcons.paste,
            tooltip: context.l10n.sharingUseSharingCodeTooltip,
            onPressed: () => _showUseInvite(context),
          ),
          PrismTopBarAction(
            icon: AppIcons.personAdd,
            tooltip: context.l10n.sharingShareYourCodeTooltip,
            onPressed: () => _showCreateInvite(context),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: pendingAsync.isLoading && friends.isEmpty
          ? const PrismLoadingState()
          : friends.isEmpty && pending.isEmpty
          ? RefreshIndicator(
              onRefresh: () => _refreshInbox(showNoopToast: false),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      onCreateInvite: () => _showCreateInvite(context),
                      onUseInvite: () => _showUseInvite(context),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _refreshInbox(showNoopToast: false),
              child: ListView(
                padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
                children: [
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        context.l10n.sharingPendingRequests,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...pending.map(
                      (request) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: _PendingRequestCard(
                          request: request,
                          termPlural: terms.plural,
                          onAccept: request.canAccept
                              ? () => _acceptRequest(request)
                              : null,
                          onDismiss: () => _dismissRequest(request),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (friends.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        context.l10n.sharingTrustedPeople,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...friends.map(
                      (friend) => _FriendTile(
                        friend: friend,
                        termPlural: terms.plural,
                        onTap: () =>
                            context.go('/settings/sharing/${friend.id}'),
                        onDelete: () => _confirmDelete(context, friend),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Future<void> _showCreateInvite(BuildContext context) async {
    await PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          CreateInviteSheet(scrollController: scrollController),
    );
  }

  Future<void> _showUseInvite(BuildContext context) async {
    final result = await PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (context, _) => const AcceptInviteSheet(),
    );
    if (result == true && context.mounted) {
      PrismToast.show(context, message: context.l10n.sharingRequestSent);
    }
  }

  Future<void> _refreshInbox({required bool showNoopToast}) async {
    if (_refreshing) return;
    final sharingService = ref.read(sharingServiceProvider);
    if (sharingService == null) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.sharingSyncNotConfigured,
        );
      }
      return;
    }

    setState(() {
      _refreshing = true;
    });
    try {
      final result = await sharingService.refreshPendingRequests();
      if (!mounted) return;
      if (result.hasUpdates) {
        PrismToast.show(context, message: _refreshSummary(result));
      } else if (showNoopToast) {
        PrismToast.show(context, message: context.l10n.sharingNoNewRequests);
      }
    } catch (e) {
      if (!mounted) return;
      PrismToast.error(context, message: context.l10n.sharingUnableToRefresh);
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _acceptRequest(PendingSharingRequest request) async {
    final sharingService = ref.read(sharingServiceProvider);
    if (sharingService == null) return;

    try {
      await sharingService.acceptPendingRequest(request.initId);
      if (!mounted) return;
      PrismToast.show(context, message: context.l10n.sharingRequestAccepted);
    } catch (e) {
      if (!mounted) return;
      PrismToast.error(context, message: context.l10n.sharingUnableToAccept);
    }
  }

  Future<void> _dismissRequest(PendingSharingRequest request) async {
    final sharingService = ref.read(sharingServiceProvider);
    if (sharingService == null) return;

    await sharingService.rejectPendingRequest(request.initId);
    if (!mounted) return;
    PrismToast.show(context, message: context.l10n.sharingRequestDismissed);
  }

  Future<void> _confirmDelete(BuildContext context, Friend friend) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.sharingRemoveTitle,
      message: context.l10n.sharingRemoveMessage(friend.displayName),
      confirmLabel: context.l10n.sharingRemove,
      destructive: true,
    );
    if (confirmed) {
      unawaited(ref.read(friendsProvider.notifier).removeFriend(friend.id));
    }
  }

  String _refreshSummary(SharingInboxRefreshResult result) {
    final parts = <String>[];
    if (result.accepted > 0) {
      parts.add('${result.accepted} accepted');
    }
    if (result.warned > 0) {
      parts.add('${result.warned} need review');
    }
    if (result.blocked > 0) {
      parts.add('${result.blocked} blocked');
    }
    if (result.errored > 0) {
      parts.add('${result.errored} failed');
    }
    return parts.join(', ');
  }
}

class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({
    required this.request,
    required this.termPlural,
    required this.onDismiss,
    this.onAccept,
  });

  final PendingSharingRequest request;
  final String termPlural;
  final VoidCallback onDismiss;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warningTone =
        request.trustDecision == PendingSharingTrustDecision.blockKeyChange;

    return PrismSurface(
      padding: const EdgeInsets.all(16),
      fillColor: warningTone
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surface,
      borderColor: warningTone
          ? theme.colorScheme.error.withValues(alpha: 0.2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                warningTone ? AppIcons.warningAmber : AppIcons.personAdd,
                color: warningTone ? theme.colorScheme.error : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.displayName,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            request.trustDecision.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: warningTone ? theme.colorScheme.error : null,
            ),
          ),
          if (request.fingerprint != null) ...[
            const SizedBox(height: 8),
            Text(
              'Fingerprint: ${request.fingerprint}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (request.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              request.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (request.offeredScopes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.offeredScopes
                  .map((scope) => scope.displayNameFor(termPlural: termPlural))
                  .join(', '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrismButton(
                  label: request.canAccept
                      ? context.l10n.sharingIgnore
                      : context.l10n.sharingDismiss,
                  onPressed: onDismiss,
                  tone: PrismButtonTone.subtle,
                ),
              ),
              if (request.canAccept) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: PrismButton(
                    label: context.l10n.sharingAccept,
                    onPressed: onAccept ?? () {},
                    enabled: onAccept != null,
                    tone: PrismButtonTone.filled,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({
    required this.friend,
    required this.termPlural,
    required this.onTap,
    required this.onDelete,
  });

  final Friend friend;
  final String termPlural;
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
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.withValues(alpha: 0.2),
        child: Icon(AppIcons.delete, color: Colors.red.withValues(alpha: 0.8)),
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
                AppIcons.verified,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
        subtitle: Text(
          highestScope?.displayNameFor(termPlural: termPlural) ??
              context.l10n.sharingNoScopesGranted,
          style: theme.textTheme.bodySmall,
        ),
        trailing: friend.lastSyncAt != null
            ? Text(
                _formatRelativeTime(friend.lastSyncAt!, context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  String _formatRelativeTime(DateTime dt, BuildContext context) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return context.l10n.sharingJustNow;
    if (diff.inMinutes < 60) {
      return context.l10n.sharingMinutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) return context.l10n.sharingHoursAgo(diff.inHours);
    return context.l10n.sharingDaysAgo(diff.inDays);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateInvite, required this.onUseInvite});

  final VoidCallback onCreateInvite;
  final VoidCallback onUseInvite;

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
              AppIcons.shareOutlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.sharingEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.sharingEmptySubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            PrismButton(
              label: context.l10n.sharingShareMyCode,
              icon: AppIcons.personAdd,
              onPressed: onCreateInvite,
              tone: PrismButtonTone.filled,
            ),
            const SizedBox(height: 12),
            PrismButton(
              label: context.l10n.sharingUseACode,
              icon: AppIcons.paste,
              onPressed: onUseInvite,
              tone: PrismButtonTone.subtle,
            ),
          ],
        ),
      ),
    );
  }
}
