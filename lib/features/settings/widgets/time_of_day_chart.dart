import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';

/// A 4-segment horizontal bar showing time-of-day distribution.
class TimeOfDayChart extends StatelessWidget {
  const TimeOfDayChart({super.key, required this.breakdown});

  final Map<String, int> breakdown;

  static const _bucketColors = {
    'morning': Colors.amber,
    'afternoon': Colors.orange,
    'evening': Colors.purple,
    'night': Colors.indigo,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = breakdown.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    return Semantics(
      label: _semanticsDescription(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 20,
              child: Row(
                children: [
                  for (final bucket in TimeBucket.values)
                    if ((breakdown[bucket.name] ?? 0) > 0)
                      Expanded(
                        flex: breakdown[bucket.name]!,
                        child: Container(
                          color: _bucketColors[bucket.name],
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final bucket in TimeBucket.values)
                if ((breakdown[bucket.name] ?? 0) > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _bucketColors[bucket.name],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${bucket.label} ${((breakdown[bucket.name]! / total) * 100).round()}%',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
            ],
          ),
        ],
      ),
    );
  }

  String _semanticsDescription() {
    final total = breakdown.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 'No time-of-day data';
    final parts = <String>[];
    for (final bucket in TimeBucket.values) {
      final mins = breakdown[bucket.name] ?? 0;
      if (mins > 0) {
        parts.add(
            '${bucket.label}: ${((mins / total) * 100).round()}%');
      }
    }
    return 'Time of day: ${parts.join(', ')}';
  }
}
