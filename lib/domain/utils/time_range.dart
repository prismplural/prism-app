/// Half-open time range `[start, end)` for domain-layer queries.
///
/// Domain repositories must not depend on Flutter, so they accept this
/// pure-Dart value type instead of `package:flutter/material.dart`'s
/// `DateTimeRange`. UI code that already holds a Flutter range should
/// construct [TimeRange] at the provider or widget boundary.
class TimeRange {
  const TimeRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  /// True when [moment] satisfies `start <= moment < end`.
  bool contains(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeRange($start, $end)';
}
