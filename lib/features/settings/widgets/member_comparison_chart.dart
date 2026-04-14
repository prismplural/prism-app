import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/extensions/duration_extensions.dart';

/// Horizontal bar chart comparing fronting time per member.
class MemberComparisonChart extends ConsumerWidget {
  const MemberComparisonChart({super.key, required this.memberStats});

  final List<MemberAnalytics> memberStats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (memberStats.isEmpty) return const SizedBox.shrink();

    final maxTime = memberStats.first.totalTime.inMinutes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fronting Time by Member',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            for (final stat in memberStats) ...[
              _MemberBar(
                stat: stat,
                maxMinutes: maxTime,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberBar extends ConsumerWidget {
  const _MemberBar({required this.stat, required this.maxMinutes});

  final MemberAnalytics stat;
  final int maxMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final memberAsync = ref.watch(memberByIdProvider(stat.memberId));
    final name = memberAsync.whenOrNull(data: (m) => m?.name) ?? '...';
    final colorHex =
        memberAsync.whenOrNull(data: (m) => m?.customColorHex);
    final barColor = colorHex != null
        ? _parseColor(colorHex)
        : theme.colorScheme.primary;

    final fraction = maxMinutes > 0 ? stat.totalTime.inMinutes / maxMinutes : 0.0;

    return Semantics(
      label:
          '$name: ${stat.totalTime.toRoundedString()} (${stat.percentageOfTotal.toStringAsFixed(1)}%)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${stat.percentageOfTotal.toStringAsFixed(1)}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 12,
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
