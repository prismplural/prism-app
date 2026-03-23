import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';

/// The selected date range for analytics.
class AnalyticsRangeNotifier extends Notifier<DateTimeRange> {
  @override
  DateTimeRange build() {
    final now = DateTime.now();
    return DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );
  }

  void setRange(DateTimeRange range) => state = range;
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, DateTimeRange>(
        AnalyticsRangeNotifier.new);

/// Computes fronting analytics for the selected date range.
final frontingAnalyticsProvider =
    FutureProvider<FrontingAnalytics>((ref) async {
  final range = ref.watch(analyticsRangeProvider);
  final dao = ref.watch(frontingSessionsDaoProvider);

  final sessions = await dao.getSessionsInRange(range.start, range.end);

  return computeAnalyticsFromRows(sessions, range);
});

@visibleForTesting
FrontingAnalytics computeAnalyticsFromRows(
  List<dynamic> rows,
  DateTimeRange range,
) {
  if (rows.isEmpty) {
    return FrontingAnalytics(
      rangeStart: range.start,
      rangeEnd: range.end,
      totalTrackedTime: Duration.zero,
      totalGapTime: range.end.difference(range.start),
      totalSessions: 0,
      uniqueFronters: 0,
      switchesPerDay: 0,
      memberStats: [],
    );
  }

  // Collect per-member durations
  final memberDurations = <String, List<Duration>>{};
  final memberTimeBuckets = <String, Map<String, int>>{};
  var totalTracked = Duration.zero;

  for (final session in rows) {
    final startTime = session.startTime as DateTime;
    final endTime =
        (session.endTime as DateTime?) ?? DateTime.now();

    // Clamp to range
    final clampedStart =
        startTime.isBefore(range.start) ? range.start : startTime;
    final clampedEnd = endTime.isAfter(range.end) ? range.end : endTime;
    if (clampedEnd.isBefore(clampedStart)) continue;

    final duration = clampedEnd.difference(clampedStart);
    totalTracked += duration;

    // Primary fronter
    final memberId = session.memberId as String?;
    if (memberId != null) {
      memberDurations.putIfAbsent(memberId, () => []).add(duration);
      _addTimeBuckets(
          memberTimeBuckets, memberId, clampedStart, clampedEnd);
    }

    // Co-fronters
    final coFronterIdsRaw = session.coFronterIds as String;
    if (coFronterIdsRaw.isNotEmpty && coFronterIdsRaw != '[]') {
      try {
        final decoded = jsonDecode(coFronterIdsRaw);
        final ids = decoded is List
            ? decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
            : <String>[];
        for (final coId in ids) {
          memberDurations.putIfAbsent(coId, () => []).add(duration);
          _addTimeBuckets(
              memberTimeBuckets, coId, clampedStart, clampedEnd);
        }
      } catch (_) {}
    }
  }

  final rangeSpan = range.end.difference(range.start);
  final totalGap = rangeSpan - totalTracked;
  final days =
      rangeSpan.inHours / 24.0;
  final switchesPerDay =
      days > 0 ? rows.length / days : 0.0;

  // Build member stats
  final memberStats = <MemberAnalytics>[];
  for (final entry in memberDurations.entries) {
    final durations = entry.value..sort();
    final total =
        durations.fold<Duration>(Duration.zero, (a, b) => a + b);
    final median = durations[durations.length ~/ 2];
    final avg = Duration(
        microseconds: total.inMicroseconds ~/ durations.length);

    memberStats.add(MemberAnalytics(
      memberId: entry.key,
      totalTime: total,
      percentageOfTotal: totalTracked.inMicroseconds > 0
          ? (total.inMicroseconds / totalTracked.inMicroseconds) * 100
          : 0,
      sessionCount: durations.length,
      averageDuration: avg,
      medianDuration: median,
      shortestSession: durations.first,
      longestSession: durations.last,
      timeOfDayBreakdown:
          memberTimeBuckets[entry.key] ?? {},
    ));
  }

  memberStats.sort((a, b) => b.totalTime.compareTo(a.totalTime));

  return FrontingAnalytics(
    rangeStart: range.start,
    rangeEnd: range.end,
    totalTrackedTime: totalTracked,
    totalGapTime: totalGap.isNegative ? Duration.zero : totalGap,
    totalSessions: rows.length,
    uniqueFronters: memberDurations.keys.length,
    switchesPerDay: switchesPerDay,
    memberStats: memberStats,
  );
}

void _addTimeBuckets(
  Map<String, Map<String, int>> memberTimeBuckets,
  String memberId,
  DateTime start,
  DateTime end,
) {
  final buckets = memberTimeBuckets.putIfAbsent(memberId, () => {});
  // Walk through the time range in hourly chunks to assign to buckets
  var cursor = start;
  while (cursor.isBefore(end)) {
    final nextHour = DateTime(
        cursor.year, cursor.month, cursor.day, cursor.hour + 1);
    final chunkEnd = nextHour.isAfter(end) ? end : nextHour;
    final minutes = chunkEnd.difference(cursor).inMinutes;
    final bucket = TimeBucket.fromHour(cursor.hour).name;
    buckets[bucket] = (buckets[bucket] ?? 0) + minutes;
    cursor = chunkEnd;
  }
}
