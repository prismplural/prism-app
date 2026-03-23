import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';
import 'package:prism_plurality/features/settings/widgets/analytics_date_range_picker.dart';
import 'package:prism_plurality/features/settings/widgets/duration_stats_card.dart';
import 'package:prism_plurality/features/settings/widgets/member_comparison_chart.dart';
import 'package:prism_plurality/features/settings/widgets/time_of_day_chart.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Main analytics screen showing fronting statistics.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(frontingAnalyticsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: 'Analytics', showBackButton: showBackButton),
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

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({required this.analytics});

  final FrontingAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, NavBarInset.of(context)),
      children: [
        // System overview
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overview',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _OverviewStat(
                      label: 'Total Time',
                      value: _fmt(analytics.totalTrackedTime),
                      theme: theme,
                    ),
                    _OverviewStat(
                      label: 'Gap Time',
                      value: _fmt(analytics.totalGapTime),
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _OverviewStat(
                      label: 'Switches/Day',
                      value:
                          analytics.switchesPerDay.toStringAsFixed(1),
                      theme: theme,
                    ),
                    _OverviewStat(
                      label: 'Unique Fronters',
                      value: '${analytics.uniqueFronters}',
                      theme: theme,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Member comparison chart
        MemberComparisonChart(memberStats: analytics.memberStats),
        const SizedBox(height: 16),

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
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
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
        ],
      ),
    );
  }
}

class _ExpandableMemberDetail extends ConsumerWidget {
  const _ExpandableMemberDetail({required this.stat});

  final MemberAnalytics stat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memberAsync = ref.watch(memberByIdProvider(stat.memberId));
    final name = memberAsync.whenOrNull(data: (m) => m?.name) ?? '...';

    return ExpansionTile(
      title: Text(name),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        DurationStatsCard(stat: stat),
        const SizedBox(height: 8),
        if (stat.timeOfDayBreakdown.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time of Day',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TimeOfDayChart(breakdown: stat.timeOfDayBreakdown),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
