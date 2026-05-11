import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_live_fronters_notice.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unmapped_fronters_notice_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/utils/pk_link_utils.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

class PluralKitUnmappedFrontersNoticeBanner extends ConsumerWidget {
  const PluralKitUnmappedFrontersNoticeBanner({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref
        .watch(pkUnmappedFrontersNoticeProvider)
        .whenOrNull(data: (state) => state.currentNotice);
    if (notice == null || notice.refs.isEmpty) return const SizedBox.shrink();

    final blocked = ref.watch(frontingMigrationWritesBlockedProvider);
    final theme = Theme.of(context);
    const pkColor = AppColors.info;
    final count = notice.refs.length;
    final message = blocked
        ? 'Resolve the fronting upgrade before reviewing unmapped PluralKit fronters.'
        : count == 1
        ? '1 current PluralKit fronter is not linked to a Prism member.'
        : '$count current PluralKit fronters are not linked to Prism members.';

    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pkColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(12),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.linkOff, size: 20, color: pkColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PluralKit front change needs review',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PrismButton(
              label: 'Review',
              onPressed: () => _showReviewSheet(context),
              tone: PrismButtonTone.subtle,
              density: PrismControlDensity.compact,
              enabled: !blocked,
            ),
          ],
        ),
      ),
    );
  }

  void _showReviewSheet(BuildContext context) {
    PrismSheet.show<void>(
      context: context,
      title: 'Review PluralKit front change',
      maxHeightFactor: 0.85,
      builder: (_) => const _PkUnmappedFrontersReviewSheet(),
    );
  }
}

class _PkUnmappedFrontersReviewSheet extends ConsumerStatefulWidget {
  const _PkUnmappedFrontersReviewSheet();

  @override
  ConsumerState<_PkUnmappedFrontersReviewSheet> createState() =>
      _PkUnmappedFrontersReviewSheetState();
}

class _PkUnmappedFrontersReviewSheetState
    extends ConsumerState<_PkUnmappedFrontersReviewSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final notice = ref
        .watch(pkUnmappedFrontersNoticeProvider)
        .whenOrNull(data: (state) => state.currentNotice);
    final blocked = ref.watch(frontingMigrationWritesBlockedProvider);
    final membersAsync = ref.watch(userVisibleMembersProvider);
    final theme = Theme.of(context);
    final members =
        membersAsync.whenOrNull(data: (members) => members) ?? const <Member>[];
    final linkableMembers = members
        .where((member) => !member.isDeleted && !hasPluralKitLink(member))
        .toList(growable: false);
    final actionsEnabled = !blocked && !_busy && notice != null;

    if (notice == null || notice.refs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'No current PluralKit fronters need review.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final maxListHeight = MediaQuery.sizeOf(context).height * 0.48;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          blocked
              ? 'Review is paused until the fronting upgrade is resolved.'
              : 'Choose how Prism should handle each unmapped current fronter.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: notice.refs.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            itemBuilder: (context, index) {
              final pkRef = notice.refs[index];
              return _PkUnmappedFronterRow(
                pkRef: pkRef,
                linkableMembers: linkableMembers,
                actionsEnabled: actionsEnabled,
                onImport: () => _importRef(notice, pkRef),
                onLink: (memberId) => _linkRef(notice, pkRef, memberId),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: 'Skip this front change',
          icon: AppIcons.skipNext,
          onPressed: () => _skipNotice(notice),
          tone: PrismButtonTone.subtle,
          expanded: true,
          enabled: actionsEnabled,
          isLoading: _busy,
        ),
      ],
    );
  }

  Future<void> _importRef(
    PkUnmappedFrontersNotice notice,
    PkUnmappedFronterRef pkRef,
  ) {
    return _runBusyAction(() async {
      final current = await _revalidateCurrentRefForWrite(notice, pkRef);
      if (current == null) return;
      await ref
          .read(pluralKitSyncServiceProvider)
          .importCurrentFronter(current.ref);
      await _retryCurrentSwitchPullOnly();
      await _removeRefFromCurrentNotice(current.notice, current.ref);
    });
  }

  Future<void> _linkRef(
    PkUnmappedFrontersNotice notice,
    PkUnmappedFronterRef pkRef,
    String memberId,
  ) {
    return _runBusyAction(() async {
      final current = await _revalidateCurrentRefForWrite(notice, pkRef);
      if (current == null) return;
      await ref
          .read(pluralKitSyncServiceProvider)
          .linkCurrentFronterToLocal(current.ref, memberId);
      await _retryCurrentSwitchPullOnly();
      await _removeRefFromCurrentNotice(current.notice, current.ref);
    });
  }

  Future<void> _skipNotice(PkUnmappedFrontersNotice notice) {
    return _runBusyAction(() async {
      await ref.read(pkUnmappedFrontersNoticeProvider.notifier).dismiss(notice);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<({PkUnmappedFrontersNotice notice, PkUnmappedFronterRef ref})?>
  _revalidateCurrentRefForWrite(
    PkUnmappedFrontersNotice notice,
    PkUnmappedFronterRef pkRef,
  ) async {
    if (ref.read(frontingMigrationWritesBlockedProvider)) return null;

    final summary = await ref
        .read(pluralKitSyncProvider.notifier)
        .syncLiveFrontersOnly(direction: PkSyncDirection.pullOnly);
    if (!mounted ||
        ref.read(frontingMigrationWritesBlockedProvider) ||
        summary?.observedLiveFronters != true) {
      return null;
    }

    final currentNotice = _currentNotice();
    if (currentNotice == null ||
        currentNotice.dismissalKey != notice.dismissalKey) {
      return null;
    }

    final currentRef = _findMatchingPkRef(currentNotice, pkRef);
    if (currentRef == null) return null;
    return (notice: currentNotice, ref: currentRef);
  }

  Future<void> _retryCurrentSwitchPullOnly() {
    return ref
        .read(pluralKitSyncProvider.notifier)
        .syncLiveFrontersOnly(direction: PkSyncDirection.pullOnly);
  }

  Future<void> _removeRefFromCurrentNotice(
    PkUnmappedFrontersNotice revalidatedNotice,
    PkUnmappedFronterRef resolved,
  ) async {
    if (!mounted) return;
    final currentNotice = _currentNotice();
    if (currentNotice == null ||
        currentNotice.dismissalKey != revalidatedNotice.dismissalKey ||
        _findMatchingPkRef(currentNotice, resolved) == null) {
      return;
    }
    await _removeRefFromNotice(currentNotice, resolved);
  }

  PkUnmappedFrontersNotice? _currentNotice() {
    return ref
        .read(pkUnmappedFrontersNoticeProvider)
        .whenOrNull(data: (state) => state.currentNotice);
  }

  Future<void> _removeRefFromNotice(
    PkUnmappedFrontersNotice notice,
    PkUnmappedFronterRef resolved,
  ) async {
    final remaining = notice.refs
        .where((candidate) => !_samePkRef(candidate, resolved))
        .toList(growable: false);
    final controller = ref.read(pkUnmappedFrontersNoticeProvider.notifier);
    if (remaining.isEmpty) {
      await controller.clear();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    await controller.publish(
      PkUnmappedFrontersNotice(
        systemId: notice.systemId,
        switchId: notice.switchId,
        switchTimestamp: notice.switchTimestamp,
        sortedPkIds: notice.sortedPkIds,
        refs: remaining,
      ),
    );
  }

  Future<void> _runBusyAction(FutureOr<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PkUnmappedFronterRow extends StatelessWidget {
  const _PkUnmappedFronterRow({
    required this.pkRef,
    required this.linkableMembers,
    required this.actionsEnabled,
    required this.onImport,
    required this.onLink,
  });

  final PkUnmappedFronterRef pkRef;
  final List<Member> linkableMembers;
  final bool actionsEnabled;
  final VoidCallback onImport;
  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PkRefAvatar(pkRef: pkRef),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pkRef.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      pkRef.pkId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrismButton(
                label: 'Import to Prism',
                icon: AppIcons.cloudDownload,
                onPressed: onImport,
                tone: PrismButtonTone.filled,
                density: PrismControlDensity.compact,
                enabled: actionsEnabled,
              ),
              PrismButton(
                label: 'Link existing member',
                icon: AppIcons.link,
                onPressed: () => _showLinkSearch(context),
                tone: PrismButtonTone.subtle,
                density: PrismControlDensity.compact,
                enabled: actionsEnabled && linkableMembers.isNotEmpty,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLinkSearch(BuildContext context) async {
    final result = await MemberSearchSheet.showSingle(
      context,
      members: linkableMembers,
      termPlural: context.l10n.settingsTerminologyOptionMembers,
      title: 'Link ${pkRef.label}',
    );

    if (!context.mounted) return;
    if (result case MemberSearchResultSelected(:final memberId)) {
      onLink(memberId);
    }
  }
}

class _PkRefAvatar extends StatelessWidget {
  const _PkRefAvatar({required this.pkRef});

  final PkUnmappedFronterRef pkRef;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final initial = pkRef.label.trim();

    return CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Text(
        initial.isEmpty ? '?' : initial.characters.first.toUpperCase(),
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

bool _samePkRef(PkUnmappedFronterRef a, PkUnmappedFronterRef b) {
  final aUuid = a.pkUuid?.trim();
  final bUuid = b.pkUuid?.trim();
  if (aUuid != null && aUuid.isNotEmpty && bUuid != null && bUuid.isNotEmpty) {
    return aUuid == bUuid;
  }
  return a.pkId.trim() == b.pkId.trim();
}

PkUnmappedFronterRef? _findMatchingPkRef(
  PkUnmappedFrontersNotice notice,
  PkUnmappedFronterRef ref,
) {
  for (final candidate in notice.refs) {
    if (_samePkRef(candidate, ref)) return candidate;
  }
  return null;
}
