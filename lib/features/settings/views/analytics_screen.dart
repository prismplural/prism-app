import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/analytics_date_range_picker.dart';
import 'package:prism_plurality/features/settings/widgets/analytics_insight_card.dart';
import 'package:prism_plurality/features/settings/widgets/member_ranking_chart.dart';
import 'package:prism_plurality/features/settings/widgets/time_of_day_chart.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Main statistics screen showing fronting analytics.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(frontingAnalyticsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.statisticsTitle,
        showBackButton: showBackButton,
      ),
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          const SizedBox(height: 8),
          const AnalyticsDateRangePicker(),
          const SizedBox(height: 16),
          Expanded(
            child: analyticsAsync.when(
              loading: () => const PrismLoadingState(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (analytics) {
                if (analytics.totalSessions == 0) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No fronting sessions in this date range',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return _AnalyticsBody(analytics: analytics);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  const _AnalyticsBody({required this.analytics});

  final FrontingAnalytics analytics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);

    // Previous period and insights load independently — degrade gracefully.
    final previousPeriod =
        ref.watch(previousPeriodAnalyticsProvider).whenOrNull(
              data: (p) => p,
            );
    final insights =
        ref.watch(analyticsInsightsProvider).whenOrNull(
              data: (list) => list,
            ) ??
            const [];

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, NavBarInset.of(context)),
      children: [
        // Hero ranking chart — vertical bars per member, sorted desc by total
        // time, horizontally scrollable.
        MemberRankingChart(memberStats: analytics.memberStats),
        const SizedBox(height: 16),

        // System overview with optional prior-period comparison
        PrismSectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.statisticsOverview,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _OverviewStat(
                    label: context.l10n.statisticsMedianSessionLabel,
                    value: _fmt(analytics.medianSession),
                    priorLabel: previousPeriod != null
                        ? '${_fmt(previousPeriod.medianSession)} last period'
                        : null,
                    theme: theme,
                  ),
                  _OverviewStat(
                    label: context.l10n.statisticsGapTimeLabel,
                    value: _fmt(analytics.totalGapTime),
                    priorLabel: previousPeriod != null
                        ? '${_fmt(previousPeriod.totalGapTime)} last period'
                        : null,
                    theme: theme,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _OverviewStat(
                    label: context.l10n.statisticsSwitchesPerDayLabel,
                    value: analytics.switchesPerDay.toStringAsFixed(1),
                    priorLabel: previousPeriod != null
                        ? '${previousPeriod.switchesPerDay.toStringAsFixed(1)} last period'
                        : null,
                    theme: theme,
                  ),
                  _OverviewStat(
                    label: context.l10n
                        .statisticsUniqueFrontersLabel(terms.plural),
                    value: '${analytics.uniqueFronters}',
                    priorLabel: previousPeriod != null
                        ? '${previousPeriod.uniqueFronters} last period'
                        : null,
                    theme: theme,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Insight cards
        for (final insight in insights) ...[
          AnalyticsInsightCard(insight: insight),
          const SizedBox(height: 8),
        ],
        if (insights.isNotEmpty) const SizedBox(height: 8),

        // Per-member expandable detail
        for (final stat in analytics.memberStats) ...[
          _ExpandableMemberDetail(stat: stat),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _fmt(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
    required this.theme,
    this.priorLabel,
  });

  final String label;
  final String value;
  final ThemeData theme;
  /// Muted prior-period text, e.g. "47h last period". Omitted when null.
  final String? priorLabel;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: priorLabel != null
            ? '$label: $value; prior period: $priorLabel'
            : '$label: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (priorLabel != null)
              Text(
                priorLabel!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableMemberDetail extends ConsumerStatefulWidget {
  const _ExpandableMemberDetail({required this.stat});

  final MemberAnalytics stat;

  @override
  ConsumerState<_ExpandableMemberDetail> createState() =>
      _ExpandableMemberDetailState();
}

class _ExpandableMemberDetailState
    extends ConsumerState<_ExpandableMemberDetail>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _chevronController;
  late final Animation<double> _chevronTurns;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _chevronTurns = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _chevronController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _chevronController.forward();
    } else {
      _chevronController.reverse();
    }
  }

  @override
  Widget build(BuildContext context, ) {
    final theme = Theme.of(context);
    final memberAsync = ref.watch(memberByIdProvider(widget.stat.memberId));
    final member = memberAsync.whenOrNull(data: (m) => m);
    final name = member?.name ?? '...';
    final accent = member?.customColorEnabled == true &&
            member?.customColorHex != null
        ? AppColors.fromHex(member!.customColorHex!)
        : theme.colorScheme.primary;

    return PrismSurface(
      onTap: _toggle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Collapsed header ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                MemberAvatar(
                  avatarImageData: member?.avatarImageData,
                  memberName: member?.name,
                  emoji: member?.emoji ?? '',
                  customColorEnabled: member?.customColorEnabled ?? false,
                  customColorHex: member?.customColorHex,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.stat.sessionCount} sessions · '
                        '${_fmt(widget.stat.totalTime)} total · '
                        'avg ${_fmt(widget.stat.averageDuration)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Share-of-total bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(3)),
                        child: LinearProgressIndicator(
                          value:
                              (widget.stat.percentageOfTotal / 100)
                                  .clamp(0.0, 1.0),
                          backgroundColor: theme
                              .colorScheme.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(accent.withValues(alpha: 0.7)),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.stat.percentageOfTotal.toStringAsFixed(1)}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RotationTransition(
                      turns: _chevronTurns,
                      child: Icon(
                        AppIcons.expandMore,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Expanded detail ────────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _StatsGrid(stat: widget.stat, accent: accent),
                ),
                if (widget.stat.timeOfDayBreakdown.isNotEmpty) ...[
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Time of Day',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: TimeOfDayChart(
                      breakdown: widget.stat.timeOfDayBreakdown,
                      accentColor: accent,
                    ),
                  ),
                ] else
                  const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stat, required this.accent});

  final MemberAnalytics stat;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Table(
      children: [
        _row(theme, [
          ('Sessions', '${stat.sessionCount}'),
          ('Total', _fmt(stat.totalTime)),
        ]),
        _row(theme, [
          ('Average', _fmt(stat.averageDuration)),
          ('Median', _fmt(stat.medianDuration)),
        ], topPadding: 10),
        _row(theme, [
          ('Shortest', _fmt(stat.shortestSession)),
          ('Longest', _fmt(stat.longestSession)),
        ], topPadding: 10),
      ],
    );
  }

  TableRow _row(
    ThemeData theme,
    List<(String, String)> cells, {
    double topPadding = 0,
  }) {
    return TableRow(
      children: cells.map((cell) {
        return Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cell.$1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                cell.$2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _fmt(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}
