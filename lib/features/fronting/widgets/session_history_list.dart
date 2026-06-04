import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_screen.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/diagnostics/boot_timings.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/ui/delete_strategy_dialog.dart';
import 'package:prism_plurality/features/fronting/utils/period_day_grouping.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/fronting/widgets/wake_up_sleep_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/date_chip.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

const _frontingPlaceholderDelay = Duration(milliseconds: 800);
const _historyLoadingReservedHeight = 336.0;
const _historySkeletonRows = 4;

/// Opens a single session's detail: as a side sheet over the dashboard on wide
/// windows, or the full-screen route on narrow ones.
void _openSession(BuildContext context, String sessionId) {
  if (shouldUseDetailSideSheet(context)) {
    showDetailSideSheet(
      context,
      builder: (_) => SessionDetailScreen(sessionId: sessionId),
    );
  } else {
    context.push(AppRoutePaths.session(sessionId));
  }
}

/// A day-grouped list of fronting history rendered per the user's
/// `fronting_list_view_mode` preference (1B):
///
///  * `combinedPeriods` (default): one row per derived period with an
///    avatar stack — the §2.3 / §4.6 1A behavior, unchanged.
///  * `perMemberRows`: one row per raw per-member session. Always-present
///    members are filtered out date-scoped — see [_PerMemberRowsList].
///  * `timeline`: handled at the home-screen level by
///    `timelineViewActiveProvider`, which swaps in the full timeline view.
///    When this widget is invoked we are by definition on the list path,
///    so the timeline value is treated as `combinedPeriods` here — its
///    only effect on this widget is seeding the screen-level toggle to
///    timeline on first mount.
class SessionHistoryList extends ConsumerWidget {
  const SessionHistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode =
        ref
            .watch(systemSettingsProvider)
            .whenOrNull(data: (s) => s.frontingListViewMode) ??
        FrontingListViewMode.combinedPeriods;

    switch (viewMode) {
      case FrontingListViewMode.timeline:
      case FrontingListViewMode.combinedPeriods:
        return const _CombinedPeriodsList();
      case FrontingListViewMode.perMemberRows:
        return const _PerMemberRowsList();
    }
  }
}

@visibleForTesting
class FrontingHistoryRowMarker extends StatelessWidget {
  const FrontingHistoryRowMarker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class MemberFrontingHistoryList extends ConsumerWidget {
  const MemberFrontingHistoryList({
    super.key,
    required this.memberId,
    this.dayAnchors,
    this.onDayKeysChanged,
  });

  final String memberId;
  final Map<String, GlobalKey>? dayAnchors;
  final ValueChanged<List<String>>? onDayKeysChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(memberFrontingHistoryProvider(memberId));

    return historyAsync.when(
      skipLoadingOnReload: true,
      loading: _historyMembersLoadingSliver,
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.frontingErrorLoadingHistory(e)),
        ),
      ),
      data: (history) {
        if (history.periods.isEmpty) {
          _notifyDayKeys(const <String>[]);
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.historyOutlined,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.memberFrontingHistoryEmpty,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final membersAsync = ref.watch(allMemberListProvider);
        final membersMap = _loadedMembersMapOrNull(membersAsync);
        if (membersMap == null) return _historyMembersLoadingSliver();

        final grouped = groupHistoryByDay(
          periods: history.periods,
          sleepSessions: const <FrontingSession>[],
        );
        _notifyDayKeys(grouped.map((group) => group.dayKey).toList());

        return SliverList.builder(
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final group = grouped[index];
            final anchor = dayAnchors?.putIfAbsent(group.dayKey, GlobalKey.new);
            final child = _DayGroupWidget(
              group: group,
              isFirstGroup: index == 0,
              membersMap: membersMap,
            );
            return anchor == null
                ? child
                : KeyedSubtree(key: anchor, child: child);
          },
        );
      },
    );
  }

  void _notifyDayKeys(List<String> dayKeys) {
    final callback = onDayKeysChanged;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(dayKeys));
  }
}

/// Floating timeline affordance for the open fronting period.
///
/// Uses the same period-row renderer as the combined history list, so tapping
/// follows the list row's single-session vs. multi-contributor period routing.
class CurrentFrontingSessionChip extends ConsumerWidget {
  const CurrentFrontingSessionChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(derivedPeriodsProvider);
    final period = periodsAsync.whenOrNull(data: _currentOpenPeriod);
    if (period == null) {
      return const SizedBox.shrink();
    }

    final slices = splitPeriodAtMidnight(period);
    if (slices.isEmpty) {
      return const SizedBox.shrink();
    }
    final slice = slices.lastWhere(
      (candidate) => candidate.isLiveOpenEnded,
      orElse: () => slices.last,
    );

    final membersAsync = ref.watch(allMemberListProvider);
    final membersMap = _loadedMembersMapOrNull(membersAsync);
    if (membersMap == null) return const SizedBox.shrink();
    final tint = _periodTint(context, period, membersMap);
    final chipKey = slice.isContinuation
        ? '${period.sessionIds.join("|")}-current-${slice.displayStart.toDayKey()}'
        : '${period.sessionIds.join("|")}-current';

    return AnimatedSwitcher(
      duration: Anim.md,
      switchInCurve: Anim.enter,
      switchOutCurve: Anim.exit,
      child: Padding(
        key: ValueKey(chipKey),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GlassSurface(
          borderRadius: BorderRadius.circular(PrismTokens.radiusXLarge),
          tint: tint,
          sigma: PrismTokens.glassBlurStrong,
          padding: EdgeInsets.zero,
          child: _PeriodTile(
            slice: slice,
            isLatest: true,
            membersMap: membersMap,
          ),
        ),
      ),
    );
  }
}

class CurrentFrontingPresenceRow extends ConsumerWidget {
  const CurrentFrontingPresenceRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleepAsync = ref.watch(activeSleepSessionProvider);
    return sleepAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (sleepSession) {
        if (sleepSession != null) {
          return _CurrentSleepPresenceRow(session: sleepSession);
        }
        return const CurrentFrontingSessionChip();
      },
    );
  }
}

class _CurrentSleepPresenceRow extends ConsumerWidget {
  const _CurrentSleepPresenceRow({required this.session});

  final FrontingSession session;

  Future<void> _endSleep(BuildContext context, WidgetRef ref) async {
    try {
      Haptics.heavy();
      await ref.read(sleepNotifierProvider.notifier).endSleep(session.id);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sleepColor = AppColors.sleep(theme.brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(PrismTokens.radiusXLarge),
        tint: sleepColor,
        sigma: PrismTokens.glassBlurStrong,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(AppIcons.bedtimeRounded, size: 24, color: sleepColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FrontingDurationText(
                          startTime: session.startTime,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: sleepColor,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          context.l10n.frontingSleepingLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PrismButton(
                      label: context.l10n.frontingEndSessionButton,
                      icon: AppIcons.closeRounded,
                      onPressed: () => _endSleep(context, ref),
                      density: PrismControlDensity.compact,
                      tone: PrismButtonTone.subtle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrismButton(
                      label: context.l10n.frontingWakeUp,
                      icon: AppIcons.wbSunnyRounded,
                      onPressed: () => WakeUpSleepSheet.show(context, session),
                      density: PrismControlDensity.compact,
                      tone: PrismButtonTone.filled,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

FrontingPeriod? _currentOpenPeriod(List<FrontingPeriod> periods) {
  for (final period in periods.reversed) {
    if (period.isOpenEnded && !period.isEmpty) return period;
  }
  return null;
}

Color _periodTint(
  BuildContext context,
  FrontingPeriod period,
  Map<String, Member> membersMap,
) {
  for (final memberId in period.activeMembers) {
    final member = membersMap[memberId];
    if (member != null &&
        member.customColorEnabled &&
        member.customColorHex != null) {
      return AppColors.fromHex(member.customColorHex!);
    }
  }
  return Theme.of(context).colorScheme.primary;
}

Map<String, Member>? _loadedMembersMapOrNull(
  AsyncValue<List<Member>> membersAsync,
) {
  final members = membersAsync.value;
  if (members == null) return null;
  return {for (final member in members) member.id: member};
}

Widget _historyMembersLoadingSliver() {
  return const _DelayedHistoryLoadingSliver(
    key: ValueKey('fronting-history-members-loading'),
    skeletonMarkerLabel: 'frontingHistory members skeleton shown',
  );
}

class _DelayedHistoryLoadingSliver extends StatefulWidget {
  const _DelayedHistoryLoadingSliver({
    super.key,
    required this.skeletonMarkerLabel,
  });

  final String skeletonMarkerLabel;

  @override
  State<_DelayedHistoryLoadingSliver> createState() =>
      _DelayedHistoryLoadingSliverState();
}

class _DelayedHistoryLoadingSliverState
    extends State<_DelayedHistoryLoadingSliver> {
  Timer? _timer;
  bool _showSkeleton = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_frontingPlaceholderDelay, () {
      if (mounted) setState(() => _showSkeleton = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSkeleton) {
      return const SliverToBoxAdapter(
        child: SizedBox(height: _historyLoadingReservedHeight),
      );
    }
    BootTimings.markOnce(widget.skeletonMarkerLabel);
    return const SliverToBoxAdapter(child: _HistoryLoadingSkeleton());
  }
}

@visibleForTesting
class FrontingHistoryLoadingSkeletonMarker extends StatelessWidget {
  const FrontingHistoryLoadingSkeletonMarker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _HistoryLoadingSkeleton extends StatelessWidget {
  const _HistoryLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = PrismShapes.of(context).radius(PrismTokens.radiusMedium);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: theme.colorScheme.outlineVariant.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.35 : 0.28,
        ),
      ),
    );
    final fill = theme.colorScheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
    );
    final chipFill = theme.colorScheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.12 : 0.08,
    );

    return ExcludeSemantics(
      child: FrontingHistoryLoadingSkeletonMarker(
        child: SizedBox(
          height: _historyLoadingReservedHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: _SkeletonBlock(
                  width: 74,
                  height: 24,
                  color: chipFill,
                  radius: 999,
                ),
              ),
              for (var i = 0; i < _historySkeletonRows; i++)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    i == _historySkeletonRows - 1 ? 0 : 6,
                  ),
                  child: Material(
                    color: theme.cardColor,
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 66,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          _SkeletonBlock(
                            width: 40,
                            height: 40,
                            color: fill,
                            radius: 999,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SkeletonBlock(
                                  width: i == 0 ? 154 : 128,
                                  height: 13,
                                  color: fill,
                                  radius: 999,
                                ),
                                const SizedBox(height: 9),
                                _SkeletonBlock(
                                  width: i == 0 ? 108 : 88,
                                  height: 10,
                                  color: fill,
                                  radius: 999,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          _SkeletonBlock(
                            width: 48,
                            height: 12,
                            color: fill,
                            radius: 999,
                          ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.color,
    required this.radius,
  });

  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(radius),
        ),
      ),
    );
  }
}

/// 1A combined-period rendering: one row per derived period with avatar
/// stacks per period and inline sleep tiles. Default mode.
class _CombinedPeriodsList extends ConsumerWidget {
  const _CombinedPeriodsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(derivedPeriodsProvider);
    final sessionsAsync = ref.watch(unifiedHistoryProvider);
    final sessions = sessionsAsync.value;
    if (sessions != null) {
      BootTimings.markOnce(
        'frontingHistory combined sessions first emit',
        'count=${sessions.length}',
      );
    }

    return periodsAsync.when(
      skipLoadingOnReload: true,
      loading: () {
        BootTimings.markOnce('frontingHistory combined periods loader shown');
        return const _DelayedHistoryLoadingSliver(
          key: ValueKey('fronting-history-combined-loading'),
          skeletonMarkerLabel: 'frontingHistory combined skeleton shown',
        );
      },
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.frontingErrorLoadingHistory(e)),
        ),
      ),
      data: (periods) {
        BootTimings.markOnce(
          'frontingHistory combined periods first emit',
          'count=${periods.length}',
        );
        // Sleep tiles still come from the raw session stream — derived
        // periods only cover fronting (sleep is rendered as its own kind
        // of row). We pull sleep sessions out of the same upstream list
        // that fed the derivation.
        final sleepSessions =
            sessionsAsync.whenOrNull(
              data: (list) => list.where((s) => s.isSleep).toList(),
            ) ??
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
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.frontingNoSessionHistory,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final membersAsync = ref.watch(allMemberListProvider);
        final membersMap = _loadedMembersMapOrNull(membersAsync);
        if (membersMap == null) {
          BootTimings.markOnce('frontingHistory combined members loader shown');
          return _historyMembersLoadingSliver();
        }
        BootTimings.markOnce(
          'frontingHistory combined members first emit',
          'count=${membersMap.length}',
        );

        final grouped = groupHistoryByDay(
          periods: periods,
          sleepSessions: sleepSessions,
        );
        final sections = <_HistoryDaySection>[];
        for (var groupIndex = 0; groupIndex < grouped.length; groupIndex++) {
          final group = grouped[groupIndex];
          final rows = <_HistoryRow>[];
          for (var i = 0; i < group.items.length; i++) {
            final item = group.items[i];
            final isLatest = groupIndex == 0 && i == 0;
            rows.add(
              _HistoryRow(
                isSleep: item is DisplaySleepItem,
                buildChild: () => _combinedHistoryTile(
                  item: item,
                  isLatest: isLatest,
                  membersMap: membersMap,
                ),
              ),
            );
          }
          sections.add(_HistoryDaySection(dayKey: group.dayKey, rows: rows));
        }
        BootTimings.markOnce(
          'frontingHistory combined rows first ready',
          'sections=${sections.length} groups=${grouped.length} '
              'sleep=${sleepSessions.length}',
        );

        return _GroupedHistorySliver(sections: sections);
      },
    );
  }
}

/// 1B per-member-rows rendering: one row per raw per-member session.
///
/// Source: [unifiedHistoryOverlapProvider] (raw sessions, NOT derived
/// periods). Sleep tiles intermix using the same upstream stream the
/// combined-period mode uses.
///
/// Date-scoped always-present filter: a session row is filtered out of
/// the inline list ONLY when its `memberId` is in the always-present set
/// AND its `startTime` is at or after the always-present session's
/// `startTime` for that member. Earlier sessions for that member (e.g.,
/// rows that ended before they became "always present") still appear
/// inline as guests on those older days. This preserves date-scoped
/// historical accuracy while keeping the pinned glass header (rendered
/// elsewhere) clean.
class _PerMemberRowsList extends ConsumerWidget {
  const _PerMemberRowsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(unifiedHistoryOverlapProvider);
    final unifiedAsync = ref.watch(unifiedHistoryProvider);
    final alwaysPresentAsync = ref.watch(alwaysPresentMembersProvider);
    final unifiedSessions = unifiedAsync.value;
    if (unifiedSessions != null) {
      BootTimings.markOnce(
        'frontingHistory perMember unified sessions first emit',
        'count=${unifiedSessions.length}',
      );
    }
    final alwaysPresent = alwaysPresentAsync.value;
    if (alwaysPresent != null) {
      BootTimings.markOnce(
        'frontingHistory perMember always-present first emit',
        'count=${alwaysPresent.length}',
      );
    }

    return bundleAsync.when(
      skipLoadingOnReload: true,
      loading: () {
        BootTimings.markOnce('frontingHistory perMember bundle loader shown');
        return const _DelayedHistoryLoadingSliver(
          key: ValueKey('fronting-history-per-member-loading'),
          skeletonMarkerLabel: 'frontingHistory perMember skeleton shown',
        );
      },
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.frontingErrorLoadingHistory(e)),
        ),
      ),
      data: (bundle) {
        BootTimings.markOnce(
          'frontingHistory perMember bundle first emit',
          'sessions=${bundle.sessions.length}',
        );
        // Build the per-member always-present anchor map: memberId →
        // earliest startTime of an always-present (qualifying) session.
        // Sessions for this member at or after that anchor are filtered
        // out (covered by the pinned glass header); earlier sessions
        // stay inline so they appear as guests on past days.
        final alwaysPresentList = alwaysPresentAsync.maybeWhen(
          data: (list) => list,
          orElse: () => const <AlwaysPresentMember>[],
        );
        final anchorByMember = <String, DateTime>{};
        for (final ap in alwaysPresentList) {
          if (!ap.member.isAlwaysFronting) continue;
          final existing = anchorByMember[ap.member.id];
          if (existing == null || ap.session.startTime.isBefore(existing)) {
            anchorByMember[ap.member.id] = ap.session.startTime;
          }
        }

        // Split fronting vs. sleep. perMemberRows shows one row per
        // fronting session, with sleep tiles intermixed (same
        // visual treatment as combinedPeriods).
        final allSessions = _clampSessionsToRange(
          bundle.sessions,
          bundle.rangeStart,
        );
        final frontingSessions = <FrontingSession>[];
        for (final s in allSessions) {
          if (s.isSleep) continue;
          if (s.isDeleted) continue;
          if (s.memberId == null) continue;
          // Date-scoped always-present filter.
          final anchor = anchorByMember[s.memberId];
          if (anchor != null && !s.startTime.isBefore(anchor)) {
            continue;
          }
          frontingSessions.add(s);
        }

        final sleepSessions =
            unifiedAsync.whenOrNull(
              data: (list) => list.where((s) => s.isSleep).toList(),
            ) ??
            const <FrontingSession>[];

        if (frontingSessions.isEmpty && sleepSessions.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    AppIcons.historyOutlined,
                    size: 48,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.frontingNoSessionHistory,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final membersAsync = ref.watch(allMemberListProvider);
        final membersMap = _loadedMembersMapOrNull(membersAsync);
        if (membersMap == null) {
          BootTimings.markOnce(
            'frontingHistory perMember members loader shown',
          );
          return _historyMembersLoadingSliver();
        }
        BootTimings.markOnce(
          'frontingHistory perMember members first emit',
          'count=${membersMap.length}',
        );

        // Reuse groupSessionsByDay so day headers + midnight-split
        // semantics match combinedPeriods mode exactly.
        final frontGroups = groupSessionsByDay(frontingSessions);
        final sleepGroups = groupSessionsByDay(sleepSessions);

        final entriesByKey = <String, List<DisplaySession>>{};
        for (final g in frontGroups) {
          entriesByKey.putIfAbsent(g.dayKey, () => []).addAll(g.sessions);
        }
        for (final g in sleepGroups) {
          entriesByKey.putIfAbsent(g.dayKey, () => []).addAll(g.sessions);
        }
        final mergedByKey = <String, _PerMemberDayGroup>{};
        for (final entry in entriesByKey.entries) {
          final entries = entry.value
            ..sort((a, b) => b.displayStart.compareTo(a.displayStart));
          mergedByKey[entry.key] = _PerMemberDayGroup(
            dayKey: entry.key,
            entries: entries,
          );
        }
        final dayKeys = mergedByKey.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        final sections = <_HistoryDaySection>[];
        for (var groupIndex = 0; groupIndex < dayKeys.length; groupIndex++) {
          final group = mergedByKey[dayKeys[groupIndex]];
          if (group == null) continue;
          final rows = <_HistoryRow>[];
          for (var i = 0; i < group.entries.length; i++) {
            final slice = group.entries[i];
            final isSleep = slice.session.isSleep;
            final isLatest = groupIndex == 0 && i == 0;
            rows.add(
              _HistoryRow(
                isSleep: isSleep,
                buildChild: () => isSleep
                    ? _InlineSleepTile(displaySession: slice)
                    : _PerMemberSessionTile(
                        slice: slice,
                        isLatest: isLatest,
                        membersMap: membersMap,
                      ),
              ),
            );
          }
          sections.add(_HistoryDaySection(dayKey: group.dayKey, rows: rows));
        }
        BootTimings.markOnce(
          'frontingHistory perMember rows first ready',
          'sections=${sections.length} groups=${dayKeys.length} '
              'fronting=${frontingSessions.length} sleep=${sleepSessions.length}',
        );

        return _GroupedHistorySliver(sections: sections);
      },
    );
  }
}

List<FrontingSession> _clampSessionsToRange(
  List<FrontingSession> sessions,
  DateTime rangeStart,
) {
  final now = DateTime.now();
  return [
    for (final session in sessions)
      if ((session.endTime ?? now).isAfter(rangeStart))
        session.startTime.isBefore(rangeStart)
            ? session.copyWith(startTime: rangeStart)
            : session,
  ];
}

/// One day's worth of per-member rows, fronting and sleep interleaved
/// in chronological order (newest first).
class _PerMemberDayGroup {
  const _PerMemberDayGroup({required this.dayKey, required this.entries});

  final String dayKey;
  final List<DisplaySession> entries;
}

/// A single day's worth of history rows, rendered together as one grouped
/// card by [_GroupedHistorySliver].
class _HistoryDaySection {
  const _HistoryDaySection({required this.dayKey, required this.rows});

  final String dayKey;
  final List<_HistoryRow> rows;
}

/// One row in a day section. [isSleep] selects the divider inset; [buildChild]
/// builds the tile lazily, so off-screen rows never construct one.
class _HistoryRow {
  const _HistoryRow({required this.buildChild, required this.isSleep});

  final Widget Function() buildChild;
  final bool isSleep;
}

class _HistoryDayHeader extends StatelessWidget {
  const _HistoryDayHeader({required this.dayKey, required this.isFirstGroup});

  final String dayKey;
  final bool isFirstGroup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirstGroup ? 20 : 18, 16, 8),
      child: DateChip(date: DateTime.parse(dayKey)),
    );
  }
}

/// Day-grouped history as one card per day, over a single flat, lazy
/// [SliverList.builder]: day sections are flattened to interleaved header/row
/// items so only on-screen items build — no per-day sliver, no
/// `SliverMainAxisGroup`, so cost is O(visible) not O(dayCount).
///
/// Each day's card is faked per row — a clipped fill plus
/// [_GroupedCardBorderPainter] stroking only that row's outer edges, with inset
/// dividers between — so the grouped look survives without an eager whole-day
/// build.
class _GroupedHistorySliver extends StatelessWidget {
  const _GroupedHistorySliver({required this.sections});

  final List<_HistoryDaySection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = PrismShapes.of(context).radius(PrismTokens.radiusMedium);
    final cardColor = theme.cardColor;
    final borderColor = theme.colorScheme.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.50 : 0.52,
    );
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.08);

    final items = <_HistoryListItem>[];
    for (var s = 0; s < sections.length; s++) {
      final section = sections[s];
      items.add(
        _HistoryHeaderItem(dayKey: section.dayKey, isFirstGroup: s == 0),
      );
      final rows = section.rows;
      for (var i = 0; i < rows.length; i++) {
        final edge = rows.length == 1
            ? _CardEdge.single
            : i == 0
            ? _CardEdge.top
            : i == rows.length - 1
            ? _CardEdge.bottom
            : _CardEdge.middle;
        final showDivider = i < rows.length - 1;
        items.add(
          _HistoryRowItem(
            buildChild: rows[i].buildChild,
            edge: edge,
            showDivider: showDivider,
            dividerInset:
                showDivider && (rows[i].isSleep || rows[i + 1].isSleep)
                ? 16
                : 64,
          ),
        );
      }
    }

    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        _HistoryHeaderItem(:final dayKey, :final isFirstGroup) =>
          _HistoryDayHeader(dayKey: dayKey, isFirstGroup: isFirstGroup),
        _HistoryRowItem(
          :final buildChild,
          :final edge,
          :final showDivider,
          :final dividerInset,
        ) =>
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: cardColor,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: edge.borderRadius(radius),
              ),
              child: CustomPaint(
                foregroundPainter: _GroupedCardBorderPainter(
                  edge: edge,
                  radius: radius,
                  color: borderColor,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FrontingHistoryRowMarker(child: buildChild()),
                    if (showDivider)
                      Divider(
                        height: 1,
                        indent: dividerInset,
                        endIndent: 12,
                        color: dividerColor,
                      ),
                  ],
                ),
              ),
            ),
          ),
      },
    );
  }
}

/// Position of a row within its day card. Determines which corners are rounded
/// and which border edges the row paints.
enum _CardEdge {
  single,
  top,
  middle,
  bottom;

  bool get roundTop => this == _CardEdge.single || this == _CardEdge.top;
  bool get roundBottom => this == _CardEdge.single || this == _CardEdge.bottom;

  BorderRadius borderRadius(double radius) => BorderRadius.vertical(
    top: roundTop ? Radius.circular(radius) : Radius.zero,
    bottom: roundBottom ? Radius.circular(radius) : Radius.zero,
  );
}

sealed class _HistoryListItem {
  const _HistoryListItem();
}

class _HistoryHeaderItem extends _HistoryListItem {
  const _HistoryHeaderItem({required this.dayKey, required this.isFirstGroup});

  final String dayKey;
  final bool isFirstGroup;
}

class _HistoryRowItem extends _HistoryListItem {
  const _HistoryRowItem({
    required this.buildChild,
    required this.edge,
    required this.showDivider,
    required this.dividerInset,
  });

  final Widget Function() buildChild;
  final _CardEdge edge;
  final bool showDivider;
  final double dividerInset;
}

/// Strokes only the edges a row owns — sides always, top on a day's first row,
/// bottom on its last — so stacked rows form one continuous border with no
/// doubled seams. Drawn inside the row's rounded clip, so corners stay crisp.
class _GroupedCardBorderPainter extends CustomPainter {
  _GroupedCardBorderPainter({
    required this.edge,
    required this.radius,
    required this.color,
  });

  static const double _stroke = 1.0;

  final _CardEdge edge;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    const half = _stroke / 2;
    const l = half;
    const t = half;
    final rt = size.width - half;
    final b = size.height - half;
    // Clamp before insetting by the stroke so an oversized radius can't cross
    // the side joins (mirrors Flutter's clip normalisation); 0 in angular mode.
    final clampedRadius = math.min(
      radius,
      math.min(size.width, size.height) / 2,
    );
    final r = math.max(0.0, clampedRadius - half);

    // Sides run edge-to-edge on unrounded corners (meeting the next row with no
    // gap), stopping short by `r` where an arc takes over.
    final topJoin = edge.roundTop ? t + r : 0.0;
    final bottomJoin = edge.roundBottom ? b - r : size.height;

    final path = Path()
      ..moveTo(l, topJoin)
      ..lineTo(l, bottomJoin)
      ..moveTo(rt, topJoin)
      ..lineTo(rt, bottomJoin);

    if (edge.roundTop) {
      path
        ..addArc(
          Rect.fromCircle(center: Offset(l + r, t + r), radius: r),
          math.pi,
          math.pi / 2,
        )
        ..moveTo(l + r, t)
        ..lineTo(rt - r, t)
        ..addArc(
          Rect.fromCircle(center: Offset(rt - r, t + r), radius: r),
          3 * math.pi / 2,
          math.pi / 2,
        );
    }
    if (edge.roundBottom) {
      path
        ..addArc(
          Rect.fromCircle(center: Offset(rt - r, b - r), radius: r),
          0,
          math.pi / 2,
        )
        ..moveTo(rt - r, b)
        ..lineTo(l + r, b)
        ..addArc(
          Rect.fromCircle(center: Offset(l + r, b - r), radius: r),
          math.pi / 2,
          math.pi / 2,
        );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GroupedCardBorderPainter old) =>
      old.edge != edge || old.radius != radius || old.color != color;
}

Widget _combinedHistoryTile({
  required HistoryDisplayItem item,
  required bool isLatest,
  required Map<String, Member> membersMap,
}) {
  if (item is DisplaySleepItem) {
    return _InlineSleepTile(displaySession: item.slice);
  }
  if (item is DisplayPeriod) {
    return _PeriodTile(slice: item, isLatest: isLatest, membersMap: membersMap);
  }
  return const SizedBox.shrink();
}

/// One row per per-member session in `perMemberRows` mode. Visually
/// matches the combined-period tile (same row height, same avatar
/// treatment) but renders a single member rather than an avatar stack.
class _PerMemberSessionTile extends ConsumerWidget {
  const _PerMemberSessionTile({
    required this.slice,
    this.isLatest = false,
    required this.membersMap,
  });

  final DisplaySession slice;
  final bool isLatest;
  final Map<String, Member> membersMap;

  FrontingSession get session => slice.session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memberId = session.memberId;
    final member = memberId == null ? null : membersMap[memberId];
    final isUnknown = member == null;

    final accentColor =
        member != null &&
            member.customColorEnabled &&
            member.customColorHex != null
        ? AppColors.fromHex(member.customColorHex!)
        : theme.colorScheme.primary;
    final durationAccentColor = _durationAccentColor(context, accentColor);

    final timeRange = slice.timeRangeString(context);
    final name = member?.name ?? 'Unknown';

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
            memberId: member.id,
            deferAvatarLookup: true,
            memberName: member.name,
            emoji: member.emoji,
            customColorEnabled: member.customColorEnabled,
            customColorHex: member.customColorHex,
            size: 40,
          );

    final showLiveTimer = slice.isActive && !slice.continuesNextDay;
    final durationColor = isLatest ? durationAccentColor : null;
    final subtitleWidget = showLiveTimer
        ? _ActiveSubtitle(
            startTime: slice.displayStart,
            timeRange: timeRange,
            accentColor: durationAccentColor,
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
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );

    const dimAlpha = 0.6;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSession(context, session.id),
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
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: dimAlpha,
                              ),
                            )
                          : theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: (theme.textTheme.bodySmall ?? const TextStyle())
                          .copyWith(
                            color: isUnknown
                                ? theme.colorScheme.onSurface.withValues(
                                    alpha: dimAlpha,
                                  )
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
                      indent:
                          _isSleep(group.items[i]) ||
                              _isSleep(group.items[i + 1])
                          ? 16
                          : 64,
                      endIndent: 12,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
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
const _periodRosterNameLimit = 3;
const _periodAvatarMemberLimit = 4;
const _briefVisitorChipLimit = 4;

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

  String _timeRange(BuildContext context) {
    final startStr = context.formatTime(slice.displayStart);
    final midnight = context.use24HourTime ? '00:00' : '12:00 AM';
    if (slice.continuesNextDay) {
      return '$startStr – $midnight';
    }
    if (slice.isLiveOpenEnded) {
      return '$startStr – ongoing';
    }
    return '$startStr – ${context.formatTime(slice.displayEnd)}';
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (period.sessionIds.isEmpty) return;

    final repo = ref.read(frontingSessionRepositoryProvider);
    final allSessions = await repo.getAllSessions();
    if (!context.mounted) return;

    final editGuard = ref.read(frontingEditGuardProvider);
    final allSnapshots = allSessions.map((s) => s.toSnapshot()).toList();
    // For ongoing periods `period.end` is the substituted "now" from
    // derivation time — stale by the time the user picks a strategy.
    // A session that ended in between would classify as straddle-end
    // and leave a microsecond ghost row after the slice.
    final periodEnd = period.isOpenEnded ? DateTime.now() : period.end;
    final deleteCtx = editGuard.getDeletePeriodContext(
      periodStart: period.start,
      periodEnd: periodEnd,
      isOngoing: period.isOpenEnded,
      periodSessionIds: period.sessionIds.toSet(),
      allSessions: allSnapshots,
    );

    final strategy = await showDeletePeriodStrategyDialog(
      context,
      deleteContext: deleteCtx,
    );
    if (strategy == null || !context.mounted) return;

    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);

    Haptics.heavy();
    final changes = resolutionService.computeDeletePeriodChanges(
      deleteCtx,
      strategy,
    );
    final result = await changeExecutor.execute(changes);
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
    if (period.activeMembers.isEmpty) return;
    try {
      await ref
          .read(frontingNotifierProvider.notifier)
          .endFronting(period.activeMembers.toList());
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSavingSession(e.toString()),
        );
      }
    }
  }

  void _editSession(BuildContext context) {
    if (period.sessionIds.isEmpty) return;
    context.push(AppRoutePaths.sessionEdit(period.sessionIds.first));
  }

  List<_TileContextAction> _contextActions(
    BuildContext context,
    WidgetRef ref,
  ) {
    // Edit hidden on multi-contributor periods: there's no period-level edit
    // UI today, so an Edit action would silently route to sessionIds.first —
    // the same first-of-N silent-drop bug Delete was fixed for. Long-press
    // a single contributor on the new period detail screen to edit one.
    final isMultiContributor = period.sessionIds.length >= 2;
    return [
      if (slice.isLiveOpenEnded)
        _TileContextAction(
          label: context.l10n.frontingEndSessionButton,
          icon: AppIcons.exitToApp,
          onSelected: () => _endFronting(context, ref),
        ),
      if (!isMultiContributor)
        _TileContextAction(
          label: context.l10n.edit,
          icon: AppIcons.editOutlined,
          onSelected: () => _editSession(context),
        ),
      _TileContextAction(
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

    final avatarMembers = <Member>[];
    final rosterNames = <String>[];
    for (final id in period.activeMembers) {
      final member = membersMap[id];
      if (rosterNames.length < _periodRosterNameLimit) {
        rosterNames.add(member?.name ?? 'Unknown');
      }
      if (member != null && avatarMembers.length < _periodAvatarMemberLimit) {
        avatarMembers.add(member);
      }
      if (rosterNames.length >= _periodRosterNameLimit &&
          avatarMembers.length >= _periodAvatarMemberLimit) {
        break;
      }
    }
    final hiddenRosterCount = period.activeMembers.length - rosterNames.length;
    final isUnknown = period.activeMembers.isEmpty || avatarMembers.isEmpty;

    final accentColor =
        avatarMembers.isNotEmpty &&
            avatarMembers.first.customColorEnabled &&
            avatarMembers.first.customColorHex != null
        ? AppColors.fromHex(avatarMembers.first.customColorHex!)
        : theme.colorScheme.primary;
    final durationAccentColor = _durationAccentColor(context, accentColor);

    final timeRange = _timeRange(context);
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
        : GroupMemberAvatar(
            size: 40,
            members: [
              for (final m in avatarMembers)
                GroupAvatarMember(
                  memberId: m.id,
                  avatarImageData: m.avatarImageData,
                  deferAvatarLookup: true,
                  emoji: m.emoji,
                  customColorEnabled: m.customColorEnabled,
                  customColorHex: m.customColorHex,
                ),
            ],
          );

    final showLiveTimer = slice.isLiveOpenEnded;
    final durationColor = isLatest ? durationAccentColor : null;
    final subtitleWidget = showLiveTimer
        ? _ActiveSubtitle(
            startTime: slice.displayStart,
            timeRange: timeRange,
            accentColor: durationAccentColor,
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
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );

    // Brief visitors chip ("+Sam briefly · +Aimee briefly").
    // Per-slice filtered: when a period crosses midnight, only the
    // briefs whose visit overlaps THIS slice show on this row.
    final briefChips = slice.briefVisitors.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final v in slice.briefVisitors.take(
                  _briefVisitorChipLimit,
                ))
                  _BriefVisitorChip(
                    name: membersMap[v.memberId]?.name ?? 'Unknown',
                  ),
                if (slice.briefVisitors.length > _briefVisitorChipLimit)
                  _BriefVisitorOverflowChip(
                    count: slice.briefVisitors.length - _briefVisitorChipLimit,
                  ),
              ],
            ),
          );

    // Always-present row above the period block (separate from the avatar
    // stack). Per spec: "If the implementation gets complicated, you can
    // simplify for 1A and surface the always-present member alongside but
    // visually distinct (e.g., separate row above the period block)."
    const Widget? alwaysPresentLine = null;

    const dimAlpha = 0.6;

    final tileContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Period-detail routing:
          //   1 contributor  → existing single-session detail (unchanged behavior)
          //   2+ contributors → new /period screen with the full session set
          //
          // PeriodDetailArgs carries the FULL period bounds (period.start /
          // period.end), not the slice bounds, so a midnight-crossing period
          // shows its complete extent on the detail view.
          if (period.sessionIds.isEmpty) return;
          final wide = shouldUseDetailSideSheet(context);
          if (period.sessionIds.length == 1 &&
              period.alwaysPresentMembers.isEmpty) {
            _openSession(context, period.sessionIds.first);
            return;
          }
          final hint = PeriodDetailArgs(
            activeMembers: period.activeMembers
                .map((id) => membersMap[id])
                .whereType<Member>()
                .toList(),
            start: period.start,
            end: period.end,
            isOpenEnded: period.isOpenEnded,
            alwaysPresentMembers: period.alwaysPresentMembers
                .map((id) => membersMap[id])
                .whereType<Member>()
                .toList(),
          );
          // On wide windows open the period over the dashboard in a side sheet;
          // push the full-screen route on narrow.
          if (wide) {
            showDetailSideSheet(
              context,
              builder: (_) =>
                  PeriodDetailScreen(sessionIds: period.sessionIds, hint: hint),
            );
          } else {
            context.push(AppRoutePaths.period(period.sessionIds), extra: hint);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              leadingWidget,
              const SizedBox(width: 12),
              Expanded(
                child: _PeriodTitleBlock(
                  names: rosterNames,
                  titleStyle: isUnknown
                      ? theme.textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w300,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: dimAlpha,
                          ),
                        )
                      : theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  subtitleStyle:
                      (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                        color: isUnknown
                            ? theme.colorScheme.onSurface.withValues(
                                alpha: dimAlpha,
                              )
                            : null,
                      ),
                  subtitle: subtitleWidget,
                  briefChips: briefChips,
                  alwaysPresentLine: alwaysPresentLine,
                  overflowChipColor: theme.colorScheme.secondaryContainer
                      .withValues(alpha: 0.5),
                  overflowChipForeground:
                      theme.colorScheme.onSecondaryContainer,
                  hiddenNameCount: hiddenRosterCount,
                  semanticsLabel: _cappedRosterLabel(
                    rosterNames,
                    hiddenRosterCount,
                  ),
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

    final actions = _contextActions(context, ref);
    final wrappedContent = showLiveTimer
        ? AnimatedSwitcher(
            duration: Anim.lg,
            switchInCurve: Anim.enter,
            switchOutCurve: Anim.exit,
            child: KeyedSubtree(
              key: ValueKey('period-$sliceKey-active'),
              child: tileContent,
            ),
          )
        : tileContent;

    return BlurPopupAnchor(
      key: ValueKey('period-$sliceKey'),
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
      child: wrappedContent,
    );
  }
}

class _PeriodTitleBlock extends StatelessWidget {
  const _PeriodTitleBlock({
    required this.names,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.subtitle,
    required this.briefChips,
    required this.alwaysPresentLine,
    required this.overflowChipColor,
    required this.overflowChipForeground,
    required this.hiddenNameCount,
    required this.semanticsLabel,
  });

  final List<String> names;
  final TextStyle? titleStyle;
  final TextStyle subtitleStyle;
  final Widget subtitle;
  final Widget? briefChips;
  final Widget? alwaysPresentLine;
  final Color overflowChipColor;
  final Color overflowChipForeground;
  final int hiddenNameCount;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final effectiveTitleStyle =
        titleStyle ??
        Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600) ??
        const TextStyle(fontWeight: FontWeight.w600);

    final overflowChipTextStyle =
        Theme.of(context).textTheme.labelSmall?.copyWith(
          color: overflowChipForeground,
          fontWeight: FontWeight.w600,
        ) ??
        TextStyle(color: overflowChipForeground, fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AdaptiveRosterSummary(
          names: names,
          hiddenNameCount: hiddenNameCount,
          titleStyle: effectiveTitleStyle,
          overflowChipColor: overflowChipColor,
          overflowChipForeground: overflowChipForeground,
          overflowChipTextStyle: overflowChipTextStyle,
          semanticsLabel: semanticsLabel,
        ),
        const SizedBox(height: 2),
        DefaultTextStyle(style: subtitleStyle, child: subtitle),
        ?briefChips,
        ?alwaysPresentLine,
      ],
    );
  }
}

class _AdaptiveRosterSummary extends StatelessWidget {
  const _AdaptiveRosterSummary({
    required this.names,
    required this.hiddenNameCount,
    required this.titleStyle,
    required this.overflowChipColor,
    required this.overflowChipForeground,
    required this.overflowChipTextStyle,
    required this.semanticsLabel,
  });

  final List<String> names;
  final int hiddenNameCount;
  final TextStyle titleStyle;
  final Color overflowChipColor;
  final Color overflowChipForeground;
  final TextStyle overflowChipTextStyle;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return Text('Unknown', style: titleStyle);
    }

    return Text.rich(
      TextSpan(
        style: titleStyle,
        children: [
          TextSpan(text: _formatRosterNames(names)),
          if (hiddenNameCount > 0) ...[
            const TextSpan(text: ' '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _OverflowRosterChip(
                label: '+$hiddenNameCount',
                foregroundColor: overflowChipForeground,
                backgroundColor: overflowChipColor,
                textStyle: overflowChipTextStyle,
              ),
            ),
          ],
        ],
      ),
      style: titleStyle,
      softWrap: true,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      semanticsLabel: semanticsLabel,
    );
  }
}

class _OverflowRosterChip extends StatelessWidget {
  const _OverflowRosterChip({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.textStyle,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: textStyle.copyWith(color: foregroundColor)),
    );
  }
}

String _formatRosterNames(List<String> names) {
  if (names.isEmpty) return 'Unknown';
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]} & ${names[1]}';
  return '${names.take(names.length - 1).join(', ')} & ${names.last}';
}

String _cappedRosterLabel(List<String> visibleNames, int hiddenNameCount) {
  final visibleLabel = _formatRosterNames(visibleNames);
  if (hiddenNameCount <= 0) return visibleLabel;
  return '$visibleLabel, +$hiddenNameCount more';
}

class _TileContextAction {
  const _TileContextAction({
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

class _BriefVisitorOverflowChip extends StatelessWidget {
  const _BriefVisitorOverflowChip({required this.count});

  final int count;

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
        '+$count more',
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

  Future<void> _wakeUp(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(sleepNotifierProvider.notifier).endSleep(session.id);
    } catch (e) {
      if (context.mounted) {
        PrismToast.error(context, message: e.toString());
      }
    }
  }

  void _editSession(BuildContext context) {
    context.push(AppRoutePaths.sessionEdit(session.id));
  }

  List<_TileContextAction> _contextActions(
    BuildContext context,
    WidgetRef ref,
  ) {
    return [
      if (session.endTime == null)
        _TileContextAction(
          label: context.l10n.frontingWakeUp,
          icon: AppIcons.wbSunnyRounded,
          onSelected: () => _wakeUp(context, ref),
        ),
      _TileContextAction(
        label: context.l10n.edit,
        icon: AppIcons.editOutlined,
        onSelected: () => _editSession(context),
      ),
      _TileContextAction(
        label: context.l10n.delete,
        icon: AppIcons.deleteOutline,
        destructive: true,
        onSelected: () => _showDeleteDialog(context, ref),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timeRange = displaySession.timeRangeString(context);
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

    final actions = _contextActions(context, ref);

    final tileContent = Container(
      color: AppColors.sleep(theme.brightness).withValues(alpha: 0.12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openSession(context, session.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.sleep(
                      theme.brightness,
                    ).withValues(alpha: 0.2),
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
    );

    return Semantics(
      label: context.l10n.frontingSleepSessionSemantics(
        displaySession.displayDuration.toRoundedString(),
        timeRange,
      ),
      child: BlurPopupAnchor(
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
      ),
    );
  }
}

Color _durationAccentColor(BuildContext context, Color rawAccent) {
  final theme = Theme.of(context);
  return contrastAdjustedAccent(rawAccent, theme.scaffoldBackgroundColor);
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
