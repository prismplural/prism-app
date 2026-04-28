import 'package:flutter/foundation.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/utils/session_day_grouping.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';

/// One row to render in the unified history list — either a fronting
/// period (potentially crossing midnight, sliced by [splitPeriodAtMidnight])
/// or a sleep session slice.
@immutable
sealed class HistoryDisplayItem {
  const HistoryDisplayItem();

  DateTime get displayStart;
  DateTime get displayEnd;
}

class DisplayPeriod extends HistoryDisplayItem {
  const DisplayPeriod({
    required this.period,
    required DateTime start,
    required DateTime end,
    required this.isContinuation,
    required this.continuesNextDay,
  })  : _start = start,
        _end = end;

  final FrontingPeriod period;
  final DateTime _start;
  final DateTime _end;
  final bool isContinuation;
  final bool continuesNextDay;

  @override
  DateTime get displayStart => _start;
  @override
  DateTime get displayEnd => _end;

  Duration get displayDuration => _end.difference(_start);

  /// True iff this is the slice that ends at the period's true end AND
  /// the period is open-ended.
  bool get isLiveOpenEnded => period.isOpenEnded && !continuesNextDay;
}

class DisplaySleepItem extends HistoryDisplayItem {
  const DisplaySleepItem({required this.slice});
  final DisplaySession slice;

  @override
  DateTime get displayStart => slice.displayStart;
  @override
  DateTime get displayEnd => slice.displayEnd ?? slice.displayStart;
}

class HistoryDayGroup {
  const HistoryDayGroup({required this.dayKey, required this.items});
  final String dayKey;
  final List<HistoryDisplayItem> items;
}

/// Splits a [FrontingPeriod] at each midnight boundary.
///
/// Mirrors [splitAtMidnight] for sessions. A period from 11 PM to 2 AM
/// becomes two slices, with `continuesNextDay` / `isContinuation` flags
/// driving the time-range render ("11:00 PM – 12:00 AM" vs "12:00 AM –
/// 2:00 AM").
@visibleForTesting
List<DisplayPeriod> splitPeriodAtMidnight(FrontingPeriod period) {
  final startDay = DateTime(period.start.year, period.start.month, period.start.day);
  final endDay = DateTime(period.end.year, period.end.month, period.end.day);

  if (startDay == endDay) {
    return [
      DisplayPeriod(
        period: period,
        start: period.start,
        end: period.end,
        isContinuation: false,
        continuesNextDay: false,
      ),
    ];
  }

  final slices = <DisplayPeriod>[];
  var currentStart = period.start;

  while (true) {
    final nextMidnight = DateTime(
      currentStart.year,
      currentStart.month,
      currentStart.day + 1,
    );
    final isFirst = currentStart == period.start;
    final isLast = !nextMidnight.isBefore(period.end);

    slices.add(DisplayPeriod(
      period: period,
      start: currentStart,
      end: isLast ? period.end : nextMidnight,
      isContinuation: !isFirst,
      continuesNextDay: !isLast,
    ));

    if (isLast) break;
    currentStart = nextMidnight;
  }

  return slices;
}

/// Groups derived periods + sleep sessions into newest-first day buckets.
///
/// Each day bucket interleaves period slices and sleep slices in
/// descending start-time order so the most recent activity for the day
/// appears at the top of the card.
List<HistoryDayGroup> groupHistoryByDay({
  required List<FrontingPeriod> periods,
  required List<FrontingSession> sleepSessions,
}) {
  final map = <String, List<HistoryDisplayItem>>{};

  void put(String key, HistoryDisplayItem item) {
    (map[key] ??= []).add(item);
  }

  for (final period in periods) {
    if (period.isEmpty) continue;
    for (final slice in splitPeriodAtMidnight(period)) {
      put(slice.displayStart.toDayKey(), slice);
    }
  }

  for (final session in sleepSessions) {
    if (!session.isSleep) continue;
    for (final slice in splitAtMidnight(session)) {
      put(slice.displayStart.toDayKey(), DisplaySleepItem(slice: slice));
    }
  }

  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return keys.map((k) {
    final items = map[k]!
      ..sort((a, b) => b.displayStart.compareTo(a.displayStart));
    return HistoryDayGroup(dayKey: k, items: items);
  }).toList();
}
