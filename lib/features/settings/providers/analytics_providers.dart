import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/models/analytics_insight.dart';

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

/// Computes analytics over per-member fronting rows.
///
/// Each row in [rows] is one member's continuous presence (post 0.7.0
/// per-member-sessions redesign — see `docs/plans/fronting-per-member-sessions.md`
/// §2.1, §4.3). `co_fronter_ids` is no longer read; co-fronting is the
/// emergent property of overlapping rows for different members.
///
/// Semantics:
/// - **Member totals** = sum of that member's own session durations
///   (clamped to [range]). One row per member means no double-count.
/// - **Co-fronting pair totals** = sum of overlap durations across all
///   pairs of overlapping sessions for the two members. Naive O(n^2);
///   fine for typical session counts. If a single member ever has
///   >1000 sessions in range, switch to a sweep-line algorithm.
/// - **Percentages** are member-minutes over total system member-minutes
///   (`member.totalTime / sum(all members' totalTime)`). Same math as
///   the pre-0.7.0 code, just with an honest label — see §4.3.
/// - **`totalTrackedTime`** is the sum of all member-minutes (which
///   inflates past wall-clock time when members co-front). The chart
///   axis is now labeled "member-minutes" to make this explicit.
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
      topCoFrontingPairs: [],
    );
  }

  // Per-member: one entry per row that belongs to the member, clamped
  // to the analytics range. Drives totals, averages, and percentage
  // share of system member-minutes.
  final memberDurations = <String, List<Duration>>{};
  final memberTimeBuckets = <String, Map<String, int>>{};
  // Flat list of every (clamped) session duration, for the system-wide
  // median session length stat.
  final allSessionDurations = <Duration>[];
  // Per-member clamped intervals, retained for the O(n^2) pair-overlap
  // pass below.
  final memberIntervals = <String, List<_Interval>>{};
  var totalMemberMinutes = Duration.zero;

  for (final session in rows) {
    final memberId = session.memberId as String?;
    if (memberId == null) continue; // sleep rows or pre-migration orphans

    final startTime = session.startTime as DateTime;
    final endTime =
        (session.endTime as DateTime?) ?? DateTime.now();

    final clampedStart =
        startTime.isBefore(range.start) ? range.start : startTime;
    final clampedEnd = endTime.isAfter(range.end) ? range.end : endTime;
    if (!clampedEnd.isAfter(clampedStart)) continue;

    final duration = clampedEnd.difference(clampedStart);
    totalMemberMinutes += duration;
    allSessionDurations.add(duration);

    memberDurations.putIfAbsent(memberId, () => []).add(duration);
    _addTimeBuckets(memberTimeBuckets, memberId, clampedStart, clampedEnd);
    memberIntervals
        .putIfAbsent(memberId, () => [])
        .add(_Interval(clampedStart, clampedEnd));
  }

  final rangeSpan = range.end.difference(range.start);
  // Gap-time semantics retained from pre-0.7.0: range duration minus the
  // sum of member-minutes. Under the per-member model with co-fronting,
  // this can underestimate "untracked" time (two members fronting an
  // overlapping hour count as two member-hours, so the gap shrinks twice
  // as fast). We accept that for 0.7.0 — the field has the same meaning
  // as before. A wall-clock-coverage stat is future work (§4.3).
  final totalGap = rangeSpan - totalMemberMinutes;
  final days = rangeSpan.inHours / 24.0;
  final switchesPerDay = days > 0 ? rows.length / days : 0.0;

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
      // % of system member-minutes — see method-level doc for the
      // semantic rename. Numerator and denominator both use member-minutes.
      percentageOfTotal: totalMemberMinutes.inMicroseconds > 0
          ? (total.inMicroseconds / totalMemberMinutes.inMicroseconds) * 100
          : 0,
      sessionCount: durations.length,
      averageDuration: avg,
      medianDuration: median,
      shortestSession: durations.first,
      longestSession: durations.last,
      timeOfDayBreakdown: memberTimeBuckets[entry.key] ?? {},
    ));
  }

  memberStats.sort((a, b) => b.totalTime.compareTo(a.totalTime));

  // System-wide median session length. For even counts we average the
  // two middle values; integer-truncated index alone returns the
  // upper-middle which biases the stat upward.
  allSessionDurations.sort();
  final medianSession = _median(allSessionDurations);

  // --- Co-fronting pairs ---
  // For each unordered pair (A, B) of members that both have at least
  // one session in range, accumulate the total wall-clock overlap of
  // their sessions. Overlap of intervals (s1, e1) and (s2, e2) is
  // `max(0, min(e1, e2) - max(s1, s2))`.
  //
  // Complexity: O(M^2 * N_a * N_b) where M = unique members in range
  // and N_x = sessions per member. Fine for typical Prism systems
  // (M < 50, N_x usually < 100). If a single member accumulates
  // >1000 sessions in range, replace the inner loops with a sweep-line
  // pass that emits overlap segments in O((N_a + N_b) log N).
  final Map<String, Duration> pairAccum = {};
  final memberIds = memberIntervals.keys.toList()..sort();
  for (var i = 0; i < memberIds.length; i++) {
    final idA = memberIds[i];
    final intervalsA = memberIntervals[idA]!;
    for (var j = i + 1; j < memberIds.length; j++) {
      final idB = memberIds[j];
      final intervalsB = memberIntervals[idB]!;
      var pairTotal = Duration.zero;
      for (final a in intervalsA) {
        for (final b in intervalsB) {
          final overlapStart =
              a.start.isAfter(b.start) ? a.start : b.start;
          final overlapEnd = a.end.isBefore(b.end) ? a.end : b.end;
          if (overlapEnd.isAfter(overlapStart)) {
            pairTotal += overlapEnd.difference(overlapStart);
          }
        }
      }
      if (pairTotal > Duration.zero) {
        // Member IDs already sorted (memberIds itself is sorted), so
        // `idA < idB` lexicographically and the key is canonical.
        pairAccum['$idA|$idB'] = pairTotal;
      }
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
    totalTrackedTime: totalMemberMinutes,
    totalGapTime: totalGap.isNegative ? Duration.zero : totalGap,
    totalSessions: rows.length,
    uniqueFronters: memberDurations.keys.length,
    switchesPerDay: switchesPerDay,
    memberStats: memberStats,
    medianSession: medianSession,
    topCoFrontingPairs: topCoFrontingPairs,
  );
}

/// Half-open interval used by the co-fronting pair-overlap pass.
class _Interval {
  const _Interval(this.start, this.end);
  final DateTime start;
  final DateTime end;
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
///
/// `names` maps memberId → display name (`displayName ?? name`). When a
/// referenced member is missing or has an empty name, headlines fall back to
/// generic copy ("A member") so the card still surfaces.
///
/// Exported for testing.
@visibleForTesting
List<AnalyticsInsight> computeInsights(
  FrontingAnalytics current,
  FrontingAnalytics? previous, {
  Map<String, String> names = const {},
}) {
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
    final nameA = _name(names, top.memberIdA);
    final nameB = _name(names, top.memberIdB);
    final headline = (nameA != null && nameB != null)
        ? '$nameA & $nameB co-fronted a lot this period'
        : 'Two members co-fronted a lot this period';
    insights.add(AnalyticsInsight(
      type: AnalyticsInsightType.coFrontingHighlight,
      iconType: AnalyticsInsightIconType.usersThree,
      headline: headline,
      body: '${_fmtDuration(top.totalTime)} together.',
      signalStrength: 30,
    ));
  }

  if (previous != null) {
    // 2. Quiet Member — appeared in previous but absent in current.
    // Surface the quiet member with the most prior-period time (strongest
    // signal); break ties by memberId for determinism.
    final currentIds =
        current.memberStats.map((m) => m.memberId).toSet();
    final quietMembers = previous.memberStats
        .where((m) => !currentIds.contains(m.memberId))
        .toList()
      ..sort((a, b) {
        final byTime = b.totalTime.compareTo(a.totalTime);
        return byTime != 0 ? byTime : a.memberId.compareTo(b.memberId);
      });
    if (quietMembers.isNotEmpty) {
      final quietest = quietMembers.first;
      final name = _name(names, quietest.memberId);
      insights.add(AnalyticsInsight(
        type: AnalyticsInsightType.quietMember,
        iconType: AnalyticsInsightIconType.moonStars,
        headline: name != null
            ? '$name hasn\'t fronted this period'
            : 'One member hasn\'t fronted this period',
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
        final name = _name(names, curr.memberId);
        final headline = name != null
            ? '$name\'s sessions are running ${longer ? "longer" : "shorter"}'
            : 'Session lengths are ${longer ? "longer" : "shorter"} for a member';
        insights.add(AnalyticsInsight(
          type: AnalyticsInsightType.sessionDrift,
          iconType: AnalyticsInsightIconType.arrowsHorizontal,
          headline: headline,
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
        final name = _name(names, curr.memberId);
        insights.add(AnalyticsInsight(
          type: AnalyticsInsightType.timeOfDayShift,
          iconType: isNightward
              ? AnalyticsInsightIconType.moon
              : AnalyticsInsightIconType.sun,
          headline: name != null
              ? '$name is fronting at a different time'
              : 'A member\'s fronting time of day shifted',
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

/// True median of a sorted duration list. Averages the two middle values
/// for even counts; returns [Duration.zero] for an empty list.
Duration _median(List<Duration> sorted) {
  if (sorted.isEmpty) return Duration.zero;
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  final lower = sorted[(n ~/ 2) - 1];
  final upper = sorted[n ~/ 2];
  return Duration(
    microseconds:
        (lower.inMicroseconds + upper.inMicroseconds) ~/ 2,
  );
}

/// Returns the display name for [memberId] from [names], or null if missing
/// or empty — callers fall back to generic copy in that case.
String? _name(Map<String, String> names, String memberId) {
  final n = names[memberId];
  if (n == null || n.isEmpty) return null;
  return n;
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
  final members = await ref.watch(allMembersProvider.future);
  final names = <String, String>{
    for (final m in members) m.id: m.displayName ?? m.name,
  };
  return computeInsights(current, previous, names: names);
});
