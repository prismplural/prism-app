import 'package:flutter/foundation.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/shared/extensions/datetime_extensions.dart';

/// A display-only view of a session, possibly sliced at a midnight boundary.
class DisplaySession {
  final FrontingSession session;
  final DateTime displayStart;
  final DateTime? displayEnd;
  final bool isContinuation;
  final bool continuesNextDay;

  const DisplaySession({
    required this.session,
    required this.displayStart,
    required this.displayEnd,
    this.isContinuation = false,
    this.continuesNextDay = false,
  });

  bool get isActive => session.isActive;
  String get id => session.id;

  Duration get displayDuration =>
      (displayEnd ?? DateTime.now()).difference(displayStart);

  /// Formatted time range string (e.g. "11:00 PM – 2:00 AM" or "3:00 PM – ongoing").
  String get timeRangeString {
    final startStr = displayStart.toTimeString();
    final endStr = displayEnd?.toTimeString();
    if (isActive && !continuesNextDay) {
      return '$startStr \u2013 ongoing';
    } else if (continuesNextDay) {
      return '$startStr \u2013 12:00 AM';
    } else {
      return '$startStr \u2013 ${endStr ?? "?"}';
    }
  }
}

/// Sessions grouped by day key (e.g., "2026-03-20").
class DayGroup {
  final String dayKey;
  final List<DisplaySession> sessions;
  const DayGroup({required this.dayKey, required this.sessions});
}

/// Groups sessions by day, splitting those that span midnight.
/// Returns groups sorted newest-first.
List<DayGroup> groupSessionsByDay(List<FrontingSession> sessions) {
  final map = <String, List<DisplaySession>>{};
  final order = <String>[];

  for (final session in sessions) {
    final slices = splitAtMidnight(session);
    for (final slice in slices) {
      final key = slice.displayStart.toDayKey();
      if (!map.containsKey(key)) {
        map[key] = [];
        order.add(key);
      }
      map[key]!.add(slice);
    }
  }

  // Sort day keys descending so newest day (Today) always appears first,
  // regardless of encounter order from midnight-split slices.
  order.sort((a, b) => b.compareTo(a));

  return order
      .map((key) => DayGroup(dayKey: key, sessions: map[key]!))
      .toList();
}

/// Splits a session into display slices at each midnight boundary.
/// A session from 11 PM to 2 AM becomes two slices:
///   Day 1: 11:00 PM – 12:00 AM (continuesNextDay)
///   Day 2: 12:00 AM – 2:00 AM (isContinuation)
@visibleForTesting
List<DisplaySession> splitAtMidnight(FrontingSession session) {
  final end = session.endTime ?? DateTime.now();
  final startDay = DateTime(
    session.startTime.year,
    session.startTime.month,
    session.startTime.day,
  );
  final endDay = DateTime(end.year, end.month, end.day);

  // Same day — no split needed.
  if (startDay == endDay) {
    return [
      DisplaySession(
        session: session,
        displayStart: session.startTime,
        displayEnd: session.endTime,
      ),
    ];
  }

  final slices = <DisplaySession>[];
  var currentDayStart = session.startTime;

  while (true) {
    final nextMidnight = DateTime(
      currentDayStart.year,
      currentDayStart.month,
      currentDayStart.day + 1,
    );

    final isFirst = currentDayStart == session.startTime;
    final isLast = !nextMidnight.isBefore(end);

    slices.add(DisplaySession(
      session: session,
      displayStart: currentDayStart,
      displayEnd: isLast ? session.endTime : nextMidnight,
      isContinuation: !isFirst,
      continuesNextDay: !isLast,
    ));

    if (isLast) break;
    currentDayStart = nextMidnight;
  }

  return slices;
}
