import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Grid card showing duration statistics for a member.
class DurationStatsCard extends StatelessWidget {
  const DurationStatsCard({super.key, required this.stat});

  final MemberAnalytics stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PrismSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.statisticsDurationStats,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatItem(
                   label: context.l10n.statisticsDurationSessions,
                  value: '${stat.sessionCount}',
                  theme: theme),
              _StatItem(
                   label: context.l10n.statisticsDurationTotal,
                  value: _fmt(stat.totalTime),
                  theme: theme),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatItem(
                   label: context.l10n.statisticsDurationAverage,
                  value: _fmt(stat.averageDuration),
                  theme: theme),
              _StatItem(
                   label: context.l10n.statisticsDurationMedian,
                  value: _fmt(stat.medianDuration),
                  theme: theme),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatItem(
                   label: context.l10n.statisticsDurationShortest,
                  value: _fmt(stat.shortestSession),
                  theme: theme),
              _StatItem(
                   label: context.l10n.statisticsDurationLongest,
                  value: _fmt(stat.longestSession),
                  theme: theme),
            ],
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

class _StatItem extends StatelessWidget {
  const _StatItem({
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
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
