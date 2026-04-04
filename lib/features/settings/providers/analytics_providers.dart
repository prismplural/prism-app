import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/settings/models/analytics_insight.dart';

class _DayBucket {
  int minutes;
  int sessions;
  _DayBucket(this.minutes, this.sessions);
}

/// Wraps a DateTimeRange with an isAllTime flag so providers can
/// suppress prior-period comparisons when "All" is selected.
class AnalyticsDateRange {
  const AnalyticsDateRange({required this.range, this.isAllTime = false});
  final DateTimeRange range;
  final bool isAllTime;
}

/// The selected date range for analytics.
class AnalyticsRangeNotifier extends Notifier<AnalyticsDateRange> {
  @override
  AnalyticsDateRange build() => AnalyticsDateRange(
        range: DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 30)),
          end: DateTime.now(),
        ),
      );

  void setRange(DateTimeRange range, {bool isAllTime = false}) =>
      state = AnalyticsDateRange(range: range, isAllTime: isAllTime);
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, AnalyticsDateRange>(
        AnalyticsRangeNotifier.new);

/// Computes fronting analytics for the selected date range.
final frontingAnalyticsProvider =
    FutureProvider<FrontingAnalytics>((ref) async {
  final range = ref.watch(analyticsRangeProvider).range;
  final dao = ref.watch(frontingSessionsDaoProvider);

  final sessions = await dao.getSessionsInRange(range.start, range.end);

  return computeAnalyticsFromRows(sessions, range);
});

/// Analytics for the period immediately preceding the selected range.
/// Returns null for "All time" — no meaningful prior period exists.
final previousPeriodAnalyticsProvider =
    FutureProvider<FrontingAnalytics?>((ref) async {
  final dateRange = ref.watch(analyticsRangeProvider);
  if (dateRange.isAllTime) return null;

  final range = dateRange.range;
  final duration = range.end.difference(range.start);
  final prevStart = range.start.subtract(duration);
  final prevEnd = range.start;
  final prevRange = DateTimeRange(start: prevStart, end: prevEnd);

  final dao = ref.watch(frontingSessionsDaoProvider);
  // Use getSessionsInRange (overlap query), NOT getSessionsBetween (start-time only)
  final sessions = await dao.getSessionsInRange(prevStart, prevEnd);
  return computeAnalyticsFromRows(sessions, prevRange);
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
      dailyActivity: [],
      topCoFrontingPairs: [],
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

  // --- Daily activity bucketing ---
  final Map<DateTime, _DayBucket> dailyMap = {};
  for (final session in rows) {
    final startTime = session.startTime as DateTime;
    final endTime = (session.endTime as DateTime?) ?? DateTime.now();

    final effectiveStart =
        startTime.isBefore(range.start) ? range.start : startTime;
    final effectiveEnd = endTime.isAfter(range.end) ? range.end : endTime;
    if (effectiveStart.isAfter(effectiveEnd)) continue;

    var cursor = effectiveStart;
    while (cursor.isBefore(effectiveEnd)) {
      final dayStart =
          DateTime.utc(cursor.year, cursor.month, cursor.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final sliceEnd =
          effectiveEnd.isBefore(dayEnd) ? effectiveEnd : dayEnd;
      final sliceMinutes = sliceEnd.difference(cursor).inMinutes;
      if (sliceMinutes > 0) {
        dailyMap.update(
          dayStart,
          (b) => _DayBucket(b.minutes + sliceMinutes, b.sessions + 1),
          ifAbsent: () => _DayBucket(sliceMinutes, 1),
        );
      }
      cursor = dayEnd;
    }
  }

  final dailyActivity = dailyMap.entries
      .map((e) => DailyActivity(
            date: e.key,
            totalMinutes: e.value.minutes,
            sessionCount: e.value.sessions,
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // --- Co-fronting pairs ---
  final Map<String, Duration> pairAccum = {};
  for (final session in rows) {
    final primaryId = session.memberId as String?;
    if (primaryId == null) continue;

    final coFronterIdsRaw = session.coFronterIds as String;
    List<String> coIds = [];
    if (coFronterIdsRaw.isNotEmpty && coFronterIdsRaw != '[]') {
      try {
        final decoded = jsonDecode(coFronterIdsRaw);
        coIds = decoded is List
            ? decoded
                .map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .toList()
            : [];
      } catch (_) {}
    }
    if (coIds.isEmpty) continue;

    final startTime = session.startTime as DateTime;
    final endTime = (session.endTime as DateTime?) ?? DateTime.now();
    final effectiveStart =
        startTime.isBefore(range.start) ? range.start : startTime;
    final effectiveEnd = endTime.isAfter(range.end) ? range.end : endTime;
    final duration = effectiveEnd.difference(effectiveStart);
    if (duration <= Duration.zero) continue;

    for (final coId in coIds) {
      if (coId == primaryId) continue;
      final ids = [primaryId, coId]..sort();
      final key = '${ids[0]}|${ids[1]}';
      pairAccum[key] = (pairAccum[key] ?? Duration.zero) + duration;
    }
  }

  final sortedPairs = pairAccum.entries
      .map((e) {
        final ids = e.key.split('|');
        return CoFrontingPair(
            memberIdA: ids[0], memberIdB: ids[1], totalTime: e.value);
      })
      .toList()
    ..sort((a, b) => b.totalTime.compareTo(a.totalTime));
  final topCoFrontingPairs = sortedPairs.take(3).toList();

  return FrontingAnalytics(
    rangeStart: range.start,
    rangeEnd: range.end,
    totalTrackedTime: totalTracked,
    totalGapTime: totalGap.isNegative ? Duration.zero : totalGap,
    totalSessions: rows.length,
    uniqueFronters: memberDurations.keys.length,
    switchesPerDay: switchesPerDay,
    memberStats: memberStats,
    dailyActivity: dailyActivity,
    topCoFrontingPairs: topCoFrontingPairs,
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

/// Generates insight cards from current and (optionally) prior period analytics.
/// Exported for testing.
@visibleForTesting
List<AnalyticsInsight> computeInsights(
  FrontingAnalytics current,
  FrontingAnalytics? previous,
) {
  final insights = <AnalyticsInsight>[];

  // 1. Gap Alert — single window, no prior period needed
  final totalRangeMinutes =
      current.rangeEnd.difference(current.rangeStart).inMinutes;
  if (totalRangeMinutes > 0) {
    final gapPct = current.totalGapTime.inMinutes / totalRangeMinutes;
    if (gapPct > 0.25) {
      insights.add(AnalyticsInsight(
        type: AnalyticsInsightType.gapAlert,
        iconType: AnalyticsInsightIconType.clockCountdown,
        headline: '${_fmtDuration(current.totalGapTime)} untracked this period',
        body:
            '${(gapPct * 100).round()}% of the time wasn\'t logged.',
        signalStrength: 80,
      ));
    }
  }

  // Co-Fronting Highlight — single window (pair data lives in current)
  if (current.topCoFrontingPairs.isNotEmpty) {
    final top = current.topCoFrontingPairs.first;
    insights.add(AnalyticsInsight(
      type: AnalyticsInsightType.coFrontingHighlight,
      iconType: AnalyticsInsightIconType.usersThree,
      headline: 'Two members co-fronted a lot this period',
      body: '${_fmtDuration(top.totalTime)} together.',
      signalStrength: 30,
    ));
  }

  if (previous != null) {
    // 2. Quiet Member — appeared in previous but absent in current
    final currentIds =
        current.memberStats.map((m) => m.memberId).toSet();
    final quietMembers = previous.memberStats
        .where((m) => !currentIds.contains(m.memberId))
        .toList();
    if (quietMembers.isNotEmpty) {
      insights.add(const AnalyticsInsight(
        type: AnalyticsInsightType.quietMember,
        iconType: AnalyticsInsightIconType.moonStars,
        headline: 'One member hasn\'t fronted this period',
        body: 'They were active in the last one.',
        signalStrength: 70,
      ));
    }

    // 3. Session Drift — avg duration changed ≥25%, prior period must have ≥2 sessions
    for (final curr in current.memberStats) {
      final prev = previous.memberStats
          .where((m) => m.memberId == curr.memberId)
          .firstOrNull;
      if (prev == null || prev.sessionCount < 2) continue;
      final prevAvgMin = prev.averageDuration.inMinutes;
      if (prevAvgMin == 0) continue;
      final change =
          (curr.averageDuration.inMinutes - prevAvgMin) / prevAvgMin;
      if (change.abs() >= 0.25) {
        final longer = change > 0;
        insights.add(AnalyticsInsight(
          type: AnalyticsInsightType.sessionDrift,
          iconType: AnalyticsInsightIconType.arrowsHorizontal,
          headline:
              'Session lengths are ${longer ? "longer" : "shorter"} for a member',
          body:
              '${_fmtDuration(curr.averageDuration)} avg, ${longer ? "up" : "down"} from ${_fmtDuration(prev.averageDuration)}.',
          signalStrength: 60,
        ));
        break; // surface at most one drift insight
      }
    }

    // 5. Time-of-Day Shift — modal bucket changed vs prior period
    for (final curr in current.memberStats) {
      final prev = previous.memberStats
          .where((m) => m.memberId == curr.memberId)
          .firstOrNull;
      if (prev == null) continue;
      final currModal = _modalBucket(curr.timeOfDayBreakdown);
      final prevModal = _modalBucket(prev.timeOfDayBreakdown);
      if (currModal != null && prevModal != null && currModal != prevModal) {
        final isNightward = currModal == 'evening' || currModal == 'night';
        insights.add(AnalyticsInsight(
          type: AnalyticsInsightType.timeOfDayShift,
          iconType: isNightward
              ? AnalyticsInsightIconType.moon
              : AnalyticsInsightIconType.sun,
          headline: 'A member\'s fronting time of day shifted',
          body:
              'Mostly ${_bucketLabel(currModal)} lately — ${_bucketLabel(prevModal)} is more typical.',
          signalStrength: 40,
        ));
        break; // surface at most one shift insight
      }
    }
  }

  insights.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
  return insights.take(3).toList();
}

String _fmtDuration(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

String? _modalBucket(Map<String, int> breakdown) {
  if (breakdown.isEmpty) return null;
  return breakdown.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;
}

String _bucketLabel(String bucket) => switch (bucket) {
      'morning' => 'mornings',
      'afternoon' => 'afternoons',
      'evening' => 'evenings',
      'night' => 'nights',
      _ => bucket,
    };

/// Auto-generated insight cards for the analytics screen.
final analyticsInsightsProvider =
    FutureProvider<List<AnalyticsInsight>>((ref) async {
  final current = await ref.watch(frontingAnalyticsProvider.future);
  final previous = await ref.watch(previousPeriodAnalyticsProvider.future);
  return computeInsights(current, previous);
});
