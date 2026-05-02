import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/ui/delete_strategy_dialog.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Detail screen for a multi-contributor fronting period.
///
/// Single-contributor periods are routed directly to [SessionDetailScreen]
/// (see `_PeriodTile.onTap`); this screen only renders for 2+ contributors.
///
/// Header renders immediately from a [PeriodDetailArgs] hint passed via
/// `state.extra` so navigation feels instant. Reactive period data comes
/// from `derivedPeriodsProvider` once it resolves — when an open-ended
/// session closes mid-mount, the live timer disappears via the provider
/// subscription (no cached `isLive`).
class PeriodDetailScreen extends ConsumerWidget {
  const PeriodDetailScreen({
    super.key,
    required this.sessionIds,
    this.hint,
  });

  final List<String> sessionIds;
  final PeriodDetailArgs? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: context.l10n.frontingSessionDetailDeleteTooltip,
            // Wired in Task 11.
            onPressed: () {},
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        children: [
          _Header(sessionIds: sessionIds, hint: hint),
          _CoFrontersSection(sessionIds: sessionIds),
          // Future tasks fill in: brief/always-present (T8),
          // comments (T9), stale handling (T13).
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.sessionIds, required this.hint});

  final List<String> sessionIds;
  final PeriodDetailArgs? hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reactive isOpenEnded: prefer the matched FrontingPeriod from
    // derivedPeriodsProvider; fall back to hint for first paint. Task 7
    // will replace the inline set-equality lookup below with the shared
    // findPeriodBySessionIds helper.
    final periodsAsync = ref.watch(derivedPeriodsProvider);
    final matchedPeriod = periodsAsync.whenOrNull(
      data: (periods) => _findPeriodBySessionIds(periods, sessionIds),
    );
    final isOpenEnded =
        matchedPeriod?.isOpenEnded ?? hint?.isOpenEnded ?? false;

    if (hint == null) {
      // Deep-link / no-hint case: small loading shimmer in the section card.
      return const PrismSectionCard(
        margin: EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: 80,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final h = hint!;
    final names = _namesString(h.activeMembers);

    final locale = context.dateLocale;
    final startStr = h.start.toTimeString(locale);
    final endStr = isOpenEnded ? 'ongoing' : h.end.toTimeString(locale);
    final timeRange = '$startStr – $endStr';

    final duration = h.end.difference(h.start);

    return PrismSectionCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        label:
            'Period: $names, fronting from $startStr to $endStr, duration ${duration.toRoundedString()}',
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GroupMemberAvatar(
              size: 56,
              members: [
                for (final m in h.activeMembers)
                  GroupAvatarMember(
                    avatarImageData: m.avatarImageData,
                    emoji: m.emoji,
                    customColorEnabled: m.customColorEnabled,
                    customColorHex: m.customColorHex,
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    names,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: 6),
                  if (isOpenEnded)
                    Row(
                      children: [
                        FrontingDurationText(
                          startTime: h.start,
                          rounded: true,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          '  ·  $timeRange',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    )
                  else
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: duration.toRoundedString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  $timeRange',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Finds the period whose sessionIds set matches [ids] by set equality.
  /// Task 7 will extract this into lib/features/fronting/services/period_lookup.dart.
  FrontingPeriod? _findPeriodBySessionIds(
    List<FrontingPeriod> periods,
    List<String> ids,
  ) {
    if (ids.isEmpty) return null;
    final target = ids.toSet();
    for (final p in periods) {
      final candidate = p.sessionIds.toSet();
      if (candidate.length == target.length && candidate.containsAll(target)) {
        return p;
      }
    }
    return null;
  }

  // Same logic as _PeriodTile._namesString, but UNTRUNCATED — show every name.
  String _namesString(List<Member> members) {
    final names = members.map((m) => m.name).toList();
    if (names.isEmpty) return 'Unknown';
    if (names.length == 1) return names[0];
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    final allButLast = names.sublist(0, names.length - 1).join(', ');
    return '$allButLast & ${names.last}';
  }
}

/// Co-fronters section: one row per contributing session in [sessionIds].
///
/// Resolves each session via [sessionByIdProvider], filters out nulls
/// (graceful degrade for tombstoned data), then resolves member metadata
/// via [membersByIdsProvider]. Each row taps to its individual session
/// detail and long-presses to the edit/delete context menu.
class _CoFrontersSection extends ConsumerWidget {
  const _CoFrontersSection({required this.sessionIds});

  final List<String> sessionIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve all sessions; skip loading/error — render nothing until data
    // arrives (the header provides instant content from hint, so there's no
    // blank screen).
    final resolvedSessions = <FrontingSession>[];
    for (final id in sessionIds) {
      final session =
          ref.watch(sessionByIdProvider(id)).whenOrNull(data: (d) => d);
      if (session != null) {
        resolvedSessions.add(session);
      }
    }

    if (resolvedSessions.isEmpty) return const SizedBox.shrink();

    // Sort by startTime ascending so the section order is chronological.
    final sorted = [...resolvedSessions]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Collect member IDs for batch lookup.
    final memberIds =
        sorted.map((s) => s.memberId).whereType<String>().toList();
    final membersKey = memberIdsKey(memberIds);
    final membersMap =
        ref.watch(membersByIdsProvider(membersKey)).whenOrNull(data: (d) => d) ??
        const <String, Member>{};

    return PrismSectionCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Co-fronters',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 64,
                endIndent: 12,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.08),
              ),
            _CoFronterRow(
              session: sorted[i],
              membersMap: membersMap,
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// One row in [_CoFrontersSection].
///
/// Visual treatment mirrors [_PerMemberSessionTile] from session_history_list.dart:
/// avatar + name + duration · time range + chevron.  Long-press opens the
/// edit/delete context menu (same actions as the list-row pattern).
class _CoFronterRow extends ConsumerWidget {
  const _CoFronterRow({
    required this.session,
    required this.membersMap,
  });

  final FrontingSession session;
  final Map<String, Member> membersMap;

  // ── Context actions ──────────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(frontingSessionRepositoryProvider);
    final current = await repo.getSessionById(session.id);
    if (current == null || !context.mounted) return;
    final allSessions = await repo.getAllSessions();

    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);

    final sessionSnapshot = current.toSnapshot();
    final allSnapshots = allSessions.map((s) => s.toSnapshot()).toList();
    final deleteCtx =
        editGuard.getDeleteContext(sessionSnapshot, allSnapshots);

    if (!context.mounted) return;
    final strategy = await showDeleteStrategyDialog(
      context,
      deleteContext: deleteCtx,
    );
    if (strategy == null || !context.mounted) return;

    Haptics.heavy();
    final changes = resolutionService.computeDeleteChanges(deleteCtx, strategy);
    final result = await changeExecutor.execute(changes);
    if (!context.mounted) return;
    result.when(
      success: (_) {},
      failure: (error) {
        if (context.mounted) {
          PrismToast.error(
            context,
            message: context.l10n.frontingErrorSavingSession(error),
          );
        }
      },
    );
  }

  Future<void> _endFronting(BuildContext context, WidgetRef ref) async {
    if (session.memberId == null) return;
    try {
      await ref
          .read(frontingNotifierProvider.notifier)
          .endFronting([session.memberId!]);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSavingSession(e.toString()),
        );
      }
    }
  }

  List<_ContextAction> _buildContextActions(
    BuildContext context,
    WidgetRef ref,
  ) {
    return [
      if (session.isActive)
        _ContextAction(
          label: context.l10n.frontingEndSessionButton,
          icon: AppIcons.stopRounded,
          onSelected: () => _endFronting(context, ref),
        ),
      _ContextAction(
        label: context.l10n.edit,
        icon: AppIcons.editOutlined,
        onSelected: () => context.go(AppRoutePaths.sessionEdit(session.id)),
      ),
      _ContextAction(
        label: context.l10n.delete,
        icon: AppIcons.deleteOutline,
        destructive: true,
        onSelected: () => _confirmDelete(context, ref),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final memberId = session.memberId;
    final member = memberId == null ? null : membersMap[memberId];
    final isUnknown = member == null;

    final accentColor =
        member != null && member.customColorEnabled && member.customColorHex != null
            ? AppColors.fromHex(member.customColorHex!)
            : theme.colorScheme.primary;

    final locale = context.dateLocale;
    final startStr = session.startTime.toTimeString(locale);
    final endStr =
        session.endTime == null ? 'ongoing' : session.endTime!.toTimeString(locale);
    final timeRange = '$startStr – $endStr';
    final duration = session.endTime == null
        ? DateTime.now().difference(session.startTime)
        : session.endTime!.difference(session.startTime);
    final name = member?.name ?? 'Unknown';

    const dimAlpha = 0.6;

    // Leading: avatar or Unknown circle.
    final leadingWidget = isUnknown
        ? Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              AppIcons.helpOutline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : MemberAvatar(
            avatarImageData: member.avatarImageData,
            memberName: member.name,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            size: 40,
          );

    // Subtitle: live timer for active sessions, static for closed.
    final subtitleWidget = session.isActive
        ? Row(
            children: [
              FrontingDurationText(
                startTime: session.startTime,
                rounded: true,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '  ·  $timeRange',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: duration.toRoundedString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: '  ·  $timeRange',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );

    final tileContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(AppRoutePaths.session(session.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              leadingWidget,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: isUnknown
                          ? theme.textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w300,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: dimAlpha),
                            )
                          : theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style:
                          (theme.textTheme.bodySmall ?? const TextStyle())
                              .copyWith(
                        color: isUnknown
                            ? theme.colorScheme.onSurface
                                .withValues(alpha: dimAlpha)
                            : null,
                      ),
                      child: subtitleWidget,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                AppIcons.chevronRightRounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: isUnknown ? 0.4 * dimAlpha : 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final actions = _buildContextActions(context, ref);

    return BlurPopupAnchor(
      key: ValueKey('co-fronter-${session.id}'),
      trigger: BlurPopupTrigger.longPress,
      width: 220,
      maxHeight: 320,
      semanticLabel: context.l10n.moreOptions,
      itemCount: actions.length,
      itemBuilder: (context, index, close) {
        final action = actions[index];
        return PrismListRow(
          dense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: Icon(action.icon, size: 20),
          title: Text(action.label),
          destructive: action.destructive,
          onTap: () {
            close();
            unawaited(Future<void>.sync(action.onSelected));
          },
        );
      },
      child: tileContent,
    );
  }
}

/// Lightweight context-action descriptor for [_CoFronterRow].
///
/// Intentionally local — deduplication with session_history_list.dart's
/// [_TileContextAction] is deferred until there's a clear shared home.
class _ContextAction {
  const _ContextAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final FutureOr<void> Function() onSelected;
  final bool destructive;
}
