import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_unpushed_members_notice.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_unpushed_members_notice_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Banner shown on the fronting screen when local Prism members exist that
/// have not yet been pushed to PluralKit AND general push sync is disabled
/// (either by direction or by Live Fronts Only mode).
///
/// This widget owns the bootstrap subscription that feeds
/// [PkUnpushedMembersNoticeController.applyMembersSnapshot]. The controller
/// itself is passive — it only updates when the banner widget hands it a
/// fresh snapshot. Mounting the banner is therefore the single, traceable
/// activation point.
///
/// Removing this widget removes the wiring entirely (mirrors the
/// `PluralKitUnmappedFrontersNoticeBanner` pattern but with explicit input
/// listeners instead of relying on a sync-summary observer).
class PluralKitUnpushedMembersNoticeBanner extends ConsumerStatefulWidget {
  const PluralKitUnpushedMembersNoticeBanner({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<PluralKitUnpushedMembersNoticeBanner> createState() =>
      _PluralKitUnpushedMembersNoticeBannerState();
}

class _PluralKitUnpushedMembersNoticeBannerState
    extends ConsumerState<PluralKitUnpushedMembersNoticeBanner> {
  @override
  void initState() {
    super.initState();
    // Listen to each input that participates in the detection logic. Any
    // change recomputes the snapshot and feeds it to the controller. The
    // controller itself does not subscribe — this is the only activation
    // point.
    ref.listenManual<AsyncValue<List<Member>>>(
      pkSyncRelevantMembersProvider,
      (_, _) => _recompute(),
    );
    ref.listenManual<PluralKitSyncState>(
      pluralKitSyncProvider,
      (_, _) => _recompute(),
    );
    ref.listenManual<PkSyncDirection>(
      pkSyncDirectionProvider,
      (_, _) => _recompute(),
    );
    ref.listenManual<PkSyncMode>(pkSyncModeProvider, (_, _) => _recompute());
    // Fire once eagerly so the banner picks up the initial state even if no
    // input changes after mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recompute();
    });
  }

  void _recompute() {
    if (!mounted) return;
    final membersAsync = ref.read(pkSyncRelevantMembersProvider);
    final members = membersAsync.value;
    if (members == null) return; // wait for first emission

    final syncState = ref.read(pluralKitSyncProvider);
    final direction = ref.read(pkSyncDirectionProvider);
    final mode = ref.read(pkSyncModeProvider);

    final pkReady = syncState.canAutoSync;
    final pushDisabled =
        !direction.pushEnabled || mode == PkSyncMode.liveFrontsOnly;

    // Fire-and-forget; controller methods are idempotent and the only state
    // that matters lands on the provider.
    unawaited(
      ref
          .read(pkUnpushedMembersNoticeProvider.notifier)
          .applyMembersSnapshot(
            members,
            pkReady: pkReady,
            pushDisabled: pushDisabled,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref
        .watch(pkUnpushedMembersNoticeProvider)
        .whenOrNull(data: (state) => state.currentNotice);
    if (notice == null || notice.refs.isEmpty) return const SizedBox.shrink();

    final blocked = ref.watch(frontingMigrationWritesBlockedProvider);
    final theme = Theme.of(context);
    const pkColor = AppColors.info;
    final count = notice.refs.length;
    final l10n = context.l10n;
    final message = blocked
        ? 'Resolve the fronting upgrade before reviewing local-only members.'
        : count == 1
        ? l10n.pkUnpushedMembersBannerMessageOne
        : l10n.pkUnpushedMembersBannerMessageMany(count);

    return Padding(
      padding: widget.padding,
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
            Icon(AppIcons.cloudOff, size: 20, color: pkColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.pkUnpushedMembersBannerTitle,
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
      title: context.l10n.pkUnpushedMembersReviewSheetTitle,
      maxHeightFactor: 0.85,
      builder: (_) => const _PkUnpushedMembersReviewSheet(),
    );
  }
}

class _PkUnpushedMembersReviewSheet extends ConsumerStatefulWidget {
  const _PkUnpushedMembersReviewSheet();

  @override
  ConsumerState<_PkUnpushedMembersReviewSheet> createState() =>
      _PkUnpushedMembersReviewSheetState();
}

class _PkUnpushedMembersReviewSheetState
    extends ConsumerState<_PkUnpushedMembersReviewSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final notice = ref
        .watch(pkUnpushedMembersNoticeProvider)
        .whenOrNull(data: (state) => state.currentNotice);
    final blocked = ref.watch(frontingMigrationWritesBlockedProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final actionsEnabled = !blocked && !_busy && notice != null;

    if (notice == null || notice.refs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'No local-only members need review.',
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
              : l10n.pkUnpushedMembersReviewIntro,
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
              final memberRef = notice.refs[index];
              return _PkUnpushedMemberRow(
                memberRef: memberRef,
                actionsEnabled: actionsEnabled,
                onPushOnce: () => _pushOnce(memberRef),
                onKeepLocal: () => _keepLocal(memberRef),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        PrismButton(
          label: l10n.pkUnpushedMembersDismissForNow,
          icon: AppIcons.skipNext,
          onPressed: () => _dismissNotice(notice),
          tone: PrismButtonTone.subtle,
          expanded: true,
          enabled: actionsEnabled,
          isLoading: _busy,
        ),
      ],
    );
  }

  Future<void> _pushOnce(PkUnpushedMemberRef memberRef) {
    return _runBusyAction(() async {
      if (ref.read(frontingMigrationWritesBlockedProvider)) return;
      final service = ref.read(pkOneShotPushServiceProvider);
      try {
        await service.pushSingleMember(memberRef.memberId);
        if (!mounted) return;
        PrismToast.success(
          context,
          message: '${memberRef.label} pushed to PluralKit.',
        );
      } catch (e) {
        if (!mounted) return;
        PrismToast.error(
          context,
          message: "Couldn't push ${memberRef.label} to PluralKit: $e",
        );
      }
    });
  }

  Future<void> _keepLocal(PkUnpushedMemberRef memberRef) {
    return _runBusyAction(() async {
      if (ref.read(frontingMigrationWritesBlockedProvider)) return;
      final repo = ref.read(memberRepositoryProvider);
      final member = await repo.getMemberById(memberRef.memberId);
      if (member == null || member.isDeleted) return;
      await repo.excludePluralKitSync(member.id);
      if (!mounted) return;
      PrismToast.success(
        context,
        message: '${memberRef.label} will stay Prism-only.',
      );
    });
  }

  Future<void> _dismissNotice(PkUnpushedMembersNotice notice) {
    return _runBusyAction(() async {
      await ref.read(pkUnpushedMembersNoticeProvider.notifier).dismiss(notice);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _runBusyAction(FutureOr<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _PkUnpushedMemberRow extends ConsumerWidget {
  const _PkUnpushedMemberRow({
    required this.memberRef,
    required this.actionsEnabled,
    required this.onPushOnce,
    required this.onKeepLocal,
  });

  final PkUnpushedMemberRef memberRef;
  final bool actionsEnabled;
  final VoidCallback onPushOnce;
  final VoidCallback onKeepLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MemberAvatar(
                memberId: memberRef.memberId,
                avatarImageData: memberRef.avatarImageData,
                memberName: memberRef.label,
                size: 40,
                deferAvatarLookup: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memberRef.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (memberRef.displayName != null &&
                        memberRef.displayName!.trim().isNotEmpty &&
                        memberRef.displayName!.trim() !=
                            memberRef.memberName.trim())
                      Text(
                        memberRef.memberName,
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
                label: l10n.pkUnpushedMembersRowPushOnce,
                icon: AppIcons.upload,
                onPressed: onPushOnce,
                tone: PrismButtonTone.filled,
                density: PrismControlDensity.compact,
                enabled: actionsEnabled,
              ),
              PrismButton(
                label: l10n.pkUnpushedMembersRowKeepLocal,
                icon: AppIcons.cloudOff,
                onPressed: onKeepLocal,
                tone: PrismButtonTone.subtle,
                density: PrismControlDensity.compact,
                enabled: actionsEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
