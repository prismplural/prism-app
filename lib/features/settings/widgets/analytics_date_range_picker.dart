import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

/// Chip row for selecting analytics date range presets.
class AnalyticsDateRangePicker extends ConsumerWidget {
  const AnalyticsDateRangePicker({super.key});

  static const _presets = [
    ('7d', 7),
    ('30d', 30),
    ('90d', 90),
    ('1y', 365),
    ('All', 3650),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsRange = ref.watch(analyticsRangeProvider);
    final now = DateTime.now();
    final selectedDays =
        analyticsRange.range.end.difference(analyticsRange.range.start).inDays;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          for (final (label, days) in _presets) ...[
            PrismChip(
              label: label,
              selected: (selectedDays - days).abs() <= 1,
              onTap: () {
                final range = DateTimeRange(
                  start: now.subtract(Duration(days: days)),
                  end: now,
                );
                ref.read(analyticsRangeProvider.notifier).setRange(
                      range,
                      isAllTime: days == 3650,
                    );
              },
            ),
            const SizedBox(width: 8),
          ],
          PrismChip(
            label: 'Custom',
            selected: !_presets.any((p) => (selectedDays - p.$2).abs() <= 1),
            onTap: () => _showCustomPicker(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomPicker(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: ref.read(analyticsRangeProvider).range,
    );
    if (picked != null) {
      ref.read(analyticsRangeProvider.notifier).setRange(picked);
    }
  }
}
