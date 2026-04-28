import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/ui/delete_strategy_dialog.dart';
import 'package:prism_plurality/features/fronting/utils/period_day_grouping.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// A day-grouped list of fronting **periods** (derived from per-member
/// sessions) plus inline sleep tiles.
///
/// Each row is one period — a maximal time span during which the active
/// fronter set didn't change (§2.3, §4.6). Co-fronts render as a single
/// row with an avatar stack, not N rows; brief visitors fold in as
/// trailing chips.
class SessionHistoryList extends ConsumerWidget {
  const SessionHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(derivedPeriodsProvider);
    final sessionsAsync = ref.watch(unifiedHistoryProvider);

    return periodsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: PrismLoadingState(),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.frontingErrorLoadingHistory(e)),
        ),
      ),
      data: (periods) {
        // Sleep tiles still come from the raw session stream — derived
        // periods only cover fronting (sleep is rendered as its own kind
        // of row). We pull sleep sessions out of the same upstream list
        // that fed the derivation.
        final sleepSessions = sessionsAsync
                .whenOrNull(data: (list) => list.where((s) => s.isSleep).toList()) ??
            const <FrontingSession>[];

        if (periods.isEmpty && sleepSessions.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.historyOutlined,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.frontingNoSessionHistory,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                  ),
                ],
              ),
            ),
          );
        }

        // Batch-load every member referenced by any period (active,
        // ephemeral, or always-present) plus sleep sessions in a single
        // query.
        final allMemberIds = <String>{};
        for (final p in periods) {
          allMemberIds.addAll(p.activeMembers);
          allMemberIds.addAll(p.alwaysPresentMembers);
          for (final v in p.briefVisitors) {
            allMemberIds.add(v.memberId);
          }
        }
        final key = memberIdsKey(allMemberIds);
        final membersAsync = ref.watch(membersByIdsProvider(key));
        final membersMap = membersAsync.whenOrNull(data: (m) => m) ?? {};

        final grouped = groupHistoryByDay(
          periods: periods,
          sleepSessions: sleepSessions,
        );

        return SliverList.builder(
          itemCount: grouped.length,
          itemBuilder: (context, index) => _DayGroupWidget(
            group: grouped[index],
            isFirstGroup: index == 0,
            membersMap: membersMap,
          ),
        );
      },
    );
  }
}

/// Renders a day header + a card containing all rows for that day.
class _DayGroupWidget extends StatelessWidget {
  const _DayGroupWidget({
    required this.group,
    this.isFirstGroup = false,
    required this.membersMap,
  });

  final HistoryDayGroup group;
  final bool isFirstGroup;
  final Map<String, Member> membersMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: DateChip(date: DateTime.parse(group.dayKey)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: PrismGroupedSectionCard(
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  _itemTile(group.items[i], i),
                  if (i < group.items.length - 1)
                    Divider(
                      height: 1,
                      indent: _isSleep(group.items[i]) ||
                              _isSleep(group.items[i + 1])
                          ? 16
                          : 64,
                      endIndent: 12,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.08),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _isSleep(HistoryDisplayItem item) => item is DisplaySleepItem;

  Widget _itemTile(HistoryDisplayItem item, int index) {
    if (item is DisplaySleepItem) {
      return _InlineSleepTile(displaySession: item.slice);
    }
    if (item is DisplayPeriod) {
      return _PeriodTile(
        slice: item,
        isLatest: isFirstGroup && index == 0,
        membersMap: membersMap,
      );
    }
    return const SizedBox.shrink();
  }
}

/// One row per derived period.
class _PeriodTile extends ConsumerWidget {
  const _PeriodTile({
    required this.slice,
    this.isLatest = false,
    required this.membersMap,
  });

  final DisplayPeriod slice;
  final bool isLatest;
  final Map<String, Member> membersMap;

  FrontingPeriod get period => slice.period;

  String _timeRange(String? locale, BuildContext context) {
    final startStr = slice.displayStart.toTimeString(locale);
    if (slice.continuesNextDay) {
      return '$startStr – 12:00 AM';
    }
    if (slice.isLiveOpenEnded) {
      return '$startStr – ongoing';
    }
    return '$startStr – ${slice.displayEnd.toTimeString(locale)}';
  }

  String _namesString(BuildContext context) {
    final names = period.activeMembers
        .map((id) => membersMap[id]?.name ?? 'Unknown')
        .toList();
    if (names.isEmpty) return 'Unknown';
    if (names.length == 1) return names[0];
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    if (names.length == 3) return '${names[0]}, ${names[1]} & ${names[2]}';
    // 4+: show first two, then "+N"
    return '${names[0]}, ${names[1]} +${names.length - 2}';
  }

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // For a multi-session period, deleting from the swipe still uses the
    // "delete the contributing sessions" semantics — we route the first
    // session through the existing delete-strategy flow. Period-level
    // delete UX is part of the period-detail screen (§3.1, not 1A).
    final firstSessionId =
        period.sessionIds.isNotEmpty ? period.sessionIds.first : null;
    if (firstSessionId == null) return false;

    final repo = ref.read(frontingSessionRepositoryProvider);
    final session = await repo.getSessionById(firstSessionId);
    if (session == null || !context.mounted) return false;
    final allSessions = await repo.getAllSessions();
    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService =
        ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);

    final sessionSnapshot = FrontingSanitizerService.toSnapshot(session);
    final allSnapshots =
        allSessions.map(FrontingSanitizerService.toSnapshot).toList();
    final deleteCtx =
        editGuard.getDeleteContext(sessionSnapshot, allSnapshots);

    if (!context.mounted) return false;
    final strategy = await showDeleteStrategyDialog(
      context,
      deleteContext: deleteCtx,
    );
    if (strategy == null || !context.mounted) return false;

    Haptics.heavy();
    final changes = resolutionService.computeDeleteChanges(deleteCtx, strategy);
    final result = await changeExecutor.execute(changes);
    return result.when(
      success: (_) {
        invalidateFrontingProviders(ref);
        triggerPostEditRescan(
          ref,
          sessionStart: session.startTime,
          sessionEnd: session.endTime,
        );
        ref.invalidate(frontingHistoryProvider);
        return true;
      },
      failure: (error) {
        if (context.mounted) {
          PrismToast.error(
            context,
            message: context.l10n.frontingErrorSavingSession(error),
          );
        }
        return false;
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final activeMemberObjs = period.activeMembers
        .map((id) => membersMap[id])
        .whereType<Member>()
        .toList();
    final isUnknown = period.activeMembers.isEmpty;

    final accentColor = activeMemberObjs.isNotEmpty &&
            activeMemberObjs.first.customColorEnabled &&
            activeMemberObjs.first.customColorHex != null
        ? AppColors.fromHex(activeMemberObjs.first.customColorHex!)
        : theme.colorScheme.primary;

    final timeRange = _timeRange(context.dateLocale, context);
    final name = _namesString(context);

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
        : _AvatarStack(members: activeMemberObjs);

    final showLiveTimer = slice.isLiveOpenEnded;
    final durationColor = isLatest ? accentColor : null;
    final subtitleWidget = showLiveTimer
        ? _ActiveSubtitle(
            startTime: slice.displayStart,
            timeRange: timeRange,
            accentColor: accentColor,
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: slice.displayDuration.toRoundedString(),
                  style: TextStyle(
                    color: durationColor,
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

    // Brief visitors chip ("+Sam briefly · +Aimee briefly").
    final briefChips = period.briefVisitors.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final v in period.briefVisitors)
                  _BriefVisitorChip(
                    name: membersMap[v.memberId]?.name ?? 'Unknown',
                  ),
              ],
            ),
          );

    // Always-present row above the period block (separate from the avatar
    // stack). Per spec: "If the implementation gets complicated, you can
    // simplify for 1A and surface the always-present member alongside but
    // visually distinct (e.g., separate row above the period block)."
    final alwaysPresentLine = period.alwaysPresentMembers.isEmpty
        ? null
        : Padding(
            padding:
                const EdgeInsets.only(top: 4, left: 0, right: 0, bottom: 0),
            child: Row(
              children: [
                Icon(
                  AppIcons.helpOutline,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Always-present: ${period.alwaysPresentMembers.map((id) => membersMap[id]?.name ?? 'Unknown').join(', ')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );

    const dimAlpha = 0.6;

    final tileContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Period-detail UX is §3.1 (not in 1A's scope). For 1A we route
          // to the first contributing session — preserves the existing
          // navigation pattern.
          if (period.sessionIds.isEmpty) return;
          context.go(AppRoutePaths.session(period.sessionIds.first));
        },
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
                    ?briefChips,
                    ?alwaysPresentLine,
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

    final sliceKey = slice.isContinuation
        ? '${period.sessionIds.join("|")}-cont-${slice.displayStart.toDayKey()}'
        : period.sessionIds.join('|');

    return Dismissible(
      key: ValueKey('period-$sliceKey'),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.2),
        ),
        child: Icon(AppIcons.delete, color: AppColors.error),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref),
      child: showLiveTimer
          ? AnimatedSwitcher(
              duration: Anim.lg,
              switchInCurve: Anim.enter,
              switchOutCurve: Anim.exit,
              child: KeyedSubtree(
                key: ValueKey('period-$sliceKey-active'),
                child: tileContent,
              ),
            )
          : tileContent,
    );
  }
}

/// An overlapping avatar stack (longest-active-at-period-start first leads).
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.members});
  final List<Member> members;

  static const double _avatarSize = 40;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox(width: _avatarSize, height: _avatarSize);

    // Cap the visible stack at 3 to keep the leading column from
    // overflowing the row; a "+N" pill represents the rest.
    final visible = members.take(3).toList();
    final extra = members.length - visible.length;
    final stackWidth = _avatarSize +
        (visible.length - 1) * (_avatarSize - _overlap) +
        (extra > 0 ? (_avatarSize - _overlap) : 0);

    return SizedBox(
      width: stackWidth,
      height: _avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (_avatarSize - _overlap),
              child: _BorderedAvatar(member: visible[i]),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * (_avatarSize - _overlap),
              child: _ExtraCountChip(count: extra),
            ),
        ],
      ),
    );
  }
}

class _BorderedAvatar extends StatelessWidget {
  const _BorderedAvatar({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.surface,
          width: 2,
        ),
      ),
      child: MemberAvatar(
        avatarImageData: member.avatarImageData,
        memberName: member.name,
        emoji: member.emoji,
        customColorEnabled: member.customColorEnabled,
        customColorHex: member.customColorHex,
        size: 40,
      ),
    );
  }
}

class _ExtraCountChip extends StatelessWidget {
  const _ExtraCountChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BriefVisitorChip extends StatelessWidget {
  const _BriefVisitorChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$name briefly',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Inline sleep session tile with tinted background. Unchanged from the
/// pre-period implementation — sleep tiles are not periods.
class _InlineSleepTile extends ConsumerWidget {
  const _InlineSleepTile({required this.displaySession});

  final DisplaySession displaySession;

  FrontingSession get session => displaySession.session;

  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.frontingDeleteSleepTitle,
      message: context.l10n.frontingDeleteSleepMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      await ref.read(sleepNotifierProvider.notifier).deleteSleep(session.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timeRange = displaySession.timeRangeString(context.dateLocale);
    final quality = session.quality;
    final hasQuality = quality != null && quality != SleepQuality.unknown;

    final trailing = hasQuality
        ? Text(
            quality.localizedLabel(context.l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.sleep(theme.brightness),
              fontWeight: FontWeight.w500,
            ),
          )
        : Icon(
            AppIcons.chevronRightRounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          );

    return Semantics(
      label: context.l10n.frontingSleepSessionSemantics(
          displaySession.displayDuration.toRoundedString(), timeRange),
      child: Container(
        color: AppColors.sleep(theme.brightness).withValues(alpha: 0.12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go(AppRoutePaths.session(session.id)),
            onLongPress: () => _showDeleteDialog(context, ref),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.sleep(theme.brightness)
                          .withValues(alpha: 0.2),
                    ),
                    child: PhosphorIcon(
                      AppIcons.duotoneSleep,
                      size: 20,
                      color: AppColors.sleep(theme.brightness),
                      semanticLabel: context.l10n.frontingSleeping,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.frontingSleeping,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: displaySession.displayDuration
                                    .toRoundedString(),
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
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtitle for active periods with live-updating duration.
class _ActiveSubtitle extends StatelessWidget {
  const _ActiveSubtitle({
    required this.startTime,
    required this.timeRange,
    required this.accentColor,
  });

  final DateTime startTime;
  final String timeRange;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        FrontingDurationText(
          startTime: startTime,
          rounded: true,
          style: theme.textTheme.bodySmall?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w600,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        Text(
          '  ·  $timeRange',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
