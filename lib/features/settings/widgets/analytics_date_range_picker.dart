import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

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
    final range = ref.watch(analyticsRangeProvider);
    final now = DateTime.now();
    final selectedDays = range.end.difference(range.start).inDays;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          for (final (label, days) in _presets) ...[
            FilterChip(
              label: Text(label),
              selected: (selectedDays - days).abs() <= 1,
              onSelected: (_) {
                ref.read(analyticsRangeProvider.notifier).setRange(
                    DateTimeRange(
                  start: now.subtract(Duration(days: days)),
                  end: now,
                ));
              },
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('Custom'),
            selected: !_presets.any((p) => (selectedDays - p.$2).abs() <= 1),
            onSelected: (_) => _showCustomPicker(context, ref),
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
      initialDateRange: ref.read(analyticsRangeProvider),
    );
    if (picked != null) {
      ref.read(analyticsRangeProvider.notifier).setRange(picked);
    }
  }
}
