import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
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

  /// Optional override for the seven weekday chip labels.
  /// When null (the default), labels come from `intl`'s `DateFormat.E` for the
  /// active platform locale.
  final List<String>? dayLabels;

  // Jan 7 2024 is a Sunday — index 0 in this widget's Sun..Sat ordering.
  static final DateTime _baseSunday = DateTime(2024, 1, 7);

  @override
  Widget build(BuildContext context) {
    final labels = dayLabels ?? _localizedShortWeekdays(context.dateLocale);
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

  static List<String> _localizedShortWeekdays(String locale) {
    final fmt = DateFormat.E(locale);
    return List<String>.generate(
      7,
      (i) => fmt.format(_baseSunday.add(Duration(days: i))),
    );
  }
}
