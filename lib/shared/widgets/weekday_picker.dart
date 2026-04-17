import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/prism_chip.dart';

/// Presentational day-of-week selector.
///
/// Indexing: 0 = Sunday through 6 = Saturday.
/// The parent owns the [selected] set; this widget reflects it and emits the
/// updated set via [onChanged] on every toggle.
class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.dayLabels,
  });

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  /// Labels for each weekday (length 7). Defaults to English short labels
  /// `Sun`–`Sat` when null. Localization arrives in a later batch.
  final List<String>? dayLabels;

  static const _defaultLabels = <String>[
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  @override
  Widget build(BuildContext context) {
    final labels = dayLabels ?? _defaultLabels;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (i) {
        final isSelected = selected.contains(i);
        return PrismChip(
          label: labels[i],
          selected: isSelected,
          onTap: () {
            final newSet = Set<int>.from(selected);
            if (isSelected) {
              newSet.remove(i);
            } else {
              newSet.add(i);
            }
            onChanged(newSet);
          },
        );
      }),
    );
  }
}
