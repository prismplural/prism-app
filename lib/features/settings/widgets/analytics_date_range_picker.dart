import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

/// Chip row for selecting analytics date range presets.
class AnalyticsDateRangePicker extends ConsumerWidget {
  const AnalyticsDateRangePicker({super.key});

  /// Default lower bound for the custom picker. Extended further back when a
  /// system has imported records that predate it (e.g. PluralKit history).
  static final DateTime _defaultFirstDate = DateTime(2020);

  static const _presets = [
    ('7d', 7),
    ('30d', 30),
    ('90d', 90),
    ('1y', 365),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsRange = ref.watch(analyticsRangeProvider);
    final isAllTime = analyticsRange.isAllTime;
    final now = DateTime.now();
    final selectedDays =
        analyticsRange.range.end.difference(analyticsRange.range.start).inDays;
    final matchesPreset =
        _presets.any((p) => (selectedDays - p.$2).abs() <= 1);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          for (final (label, days) in _presets) ...[
            PrismChip(
              label: label,
              selected: !isAllTime && (selectedDays - days).abs() <= 1,
              onTap: () {
                final range = DateTimeRange(
                  start: now.subtract(Duration(days: days)),
                  end: now,
                );
                ref.read(analyticsRangeProvider.notifier).setRange(range);
              },
            ),
            const SizedBox(width: 8),
          ],
          PrismChip(
            label: 'All',
            selected: isAllTime,
            onTap: () =>
                ref.read(analyticsRangeProvider.notifier).selectAllTime(),
          ),
          const SizedBox(width: 8),
          PrismChip(
            label: 'Custom',
            selected: !isAllTime && !matchesPreset,
            onTap: () => _showCustomPicker(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomPicker(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final selected = ref.read(analyticsRangeProvider);
    // Pre-2020 records (PK imports) are reachable via "All"; the lower bound
    // must cover them or showDateRangePicker asserts on an out-of-range start.
    final earliest =
        await ref.read(frontingSessionsDaoProvider).getEarliestSessionStart();
    if (!context.mounted) return;

    final lowerBound = (earliest != null && earliest.isBefore(_defaultFirstDate))
        ? earliest
        : _defaultFirstDate;
    // When "All" is active the stored range is a placeholder, so seed the
    // picker from the earliest record instead of opening on a zero-width span.
    final seed = selected.isAllTime
        ? DateTimeRange(
            start: earliest ?? now.subtract(const Duration(days: 30)),
            end: now,
          )
        : selected.range;
    final initStart = seed.start.isBefore(lowerBound)
        ? lowerBound
        : (seed.start.isAfter(now) ? now : seed.start);
    final initEnd = seed.end.isAfter(now) ? now : seed.end;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: lowerBound,
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: initStart,
        end: initEnd.isBefore(initStart) ? initStart : initEnd,
      ),
    );
    if (picked != null) {
      ref.read(analyticsRangeProvider.notifier).setRange(picked);
    }
  }
}
