import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';
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

/// Threshold below which the analytics computation runs synchronously on
/// the UI isolate. `compute()` has ~10ms of isolate-spawn overhead, which
/// dwarfs the actual work for small datasets — for typical Prism systems
/// (a few dozen sessions per range), the synchronous path is faster.
///
/// At 500 rows, the sweep-line + member loop is well under a frame on
/// modern hardware; above that we hand it to a background isolate so the
/// UI never janks even for 10–20k-session systems.
@visibleForTesting
const int analyticsIsolateThreshold = 500;

/// Computes fronting analytics for the selected date range.
///
/// Watches [frontingTableTickerProvider] so a write to fronting_sessions
/// rebuilds this provider for free — no per-mutation invalidation call
/// is required at the mutation site. The ticker is debounced so a bulk
/// import (PK initial / SP / sanitizer batch) coalesces into one
/// rebuild.
final frontingAnalyticsProvider =
    FutureProvider<FrontingAnalytics>((ref) async {
  ref.watch(frontingTableTickerProvider);
  final range = ref.watch(analyticsRangeProvider).range;
  final dao = ref.watch(frontingSessionsDaoProvider);

  final sessions = await dao.getSessionsInRange(range.start, range.end);

  return _runAnalyticsCompute(sessions, range);
});

/// Analytics for the period immediately preceding the selected range.
/// Returns null for "All time" — no meaningful prior period exists.
final previousPeriodAnalyticsProvider =
    FutureProvider<FrontingAnalytics?>((ref) async {
  ref.watch(frontingTableTickerProvider);
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
  return _runAnalyticsCompute(sessions, prevRange);
});

/// Maps Drift session rows to a lightweight DTO and dispatches the
/// computation either synchronously (small inputs) or to a background
/// isolate via `compute()` (large inputs).
///
/// We project to [AnalyticsSessionRow] before crossing the isolate
/// boundary so the worker never depends on Drift types — keeps the
/// pure-function entry point trivially serializable and unit-testable.
Future<FrontingAnalytics> _runAnalyticsCompute(
  List<dynamic> rows,
  DateTimeRange range,
) async {
  final dtos = [
    for (final r in rows)
      AnalyticsSessionRow(
        memberId: r.memberId as String?,
        startTime: r.startTime as DateTime,
        endTime: r.endTime as DateTime?,
      ),
  ];
  final args = AnalyticsComputeArgs(rows: dtos, range: range);
  if (dtos.length < analyticsIsolateThreshold) {
    return _computeAnalyticsFromArgs(args);
  }
  return compute(_computeAnalyticsFromArgs, args);
}

/// Top-level isolate entry point. Must not capture closure state — the
/// `compute()` contract requires a top-level or static function.
FrontingAnalytics _computeAnalyticsFromArgs(AnalyticsComputeArgs args) {
  return computeAnalyticsFromRows(args.rows, args.range);
}

/// Lightweight, isolate-friendly projection of a fronting session row.
/// Only carries the fields analytics actually reads.
@visibleForTesting
class AnalyticsSessionRow {
  const AnalyticsSessionRow({
    required this.memberId,
    required this.startTime,
    required this.endTime,
  });

  final String? memberId;
  final DateTime startTime;
  final DateTime? endTime;
}

/// Args bundle for the isolate entry point.
@visibleForTesting
class AnalyticsComputeArgs {
  const AnalyticsComputeArgs({
    required this.rows,
    required this.range,
  });

  final List<AnalyticsSessionRow> rows;
  final DateTimeRange range;
}

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
///   pairs of overlapping sessions for the two members. Computed by a
///   single sweep-line pass over session start/end events (see the
///   pair-overlap section below); O(N log N + N·K²) where K is the max
///   simultaneous fronters (typically 1–5). Replaces a prior
///   O(M²·Na·Nb) nested loop that janked the UI on systems with many
///   thousand sessions.
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
    // Sleep rows are already excluded upstream by the DAO's
    // `getSessionsInRange` (filters `session_type = _normalSessionType`).
    // The edit/gap-fill flow now writes the canonical Unknown sentinel
    // id directly (see `fronting_edit_resolution_service.dart`), so
    // freshly-produced rows already have a non-null memberId.  This
    // null-coalesce remains as defense in depth for pre-fix rows that
    // landed before the writer-side change shipped — without it those
    // legacy rows would silently drop out of analytics, leaving
    // `totalSessions` (which counts rows.length) ahead of the
    // member-time data on screen.
    final memberId =
        (session.memberId as String?) ?? unknownSentinelMemberId;

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
  // `totalGap` and `switchesPerDay` are now derived from the sweep-line
  // pass below (see "Wall-clock gap + switch count" block). The naive
  // `rangeSpan - totalMemberMinutes` formula clamped to zero whenever
  // co-fronting density pushed sum(member_minutes) past the span, hiding
  // genuine gaps; the row-count-based switch tally inflated whenever a
  // co-fronter joined or left an ongoing session. Both are corrected
  // below as O(1)-per-event additions to the existing sweep.

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

  // --- Co-fronting pairs (sweep-line) ---
  //
  // Naive nested-pair overlap is O(M²·Na·Nb). For 5k members × 4
  // sessions that's 400M comparisons per recompute — and the worker ran
  // synchronously on the UI isolate, so it janked badly on real
  // datasets (codex pass 6 P2.2).
  //
  // Sweep-line replacement: build an event stream of session
  // starts/ends, sort by timestamp (ENDs before STARTs on ties so
  // touching half-open intervals don't accrue spurious overlap), and
  // walk the stream. Between consecutive events `delta = t_now - t_prev`,
  // every unordered pair of members in the active set co-fronted for
  // exactly `delta`. Add it to that pair's accumulator.
  //
  // Active set is a Map<memberId, refCount>: a single member with two
  // overlapping rows of their own enters once and exits once (no
  // self-pairs, matches the pre-existing semantics). Pair iteration
  // walks distinct keys so self-overlap never produces a (A, A) pair.
  //
  // Complexity: O(N log N) sort + O(N · K²) pair updates, K = max
  // simultaneous fronters. K is typically 1–5, so the inner pass is
  // effectively linear in N. For 20k sessions at K=5 that's ~1M ops
  // total versus the prior ~400M.

  // Intern member ids to small ints. Sorting strings on the hot path
  // is dominated by allocation and char-by-char compare; ints keep the
  // inner loop branch-light. We assign indices in lex order so the
  // canonical pair key (idxA, idxB) with idxA < idxB matches the
  // alphabetical-id contract the tests expect.
  final sortedMemberIds = memberIntervals.keys.toList()..sort();
  final memberIdToIdx = <String, int>{
    for (var i = 0; i < sortedMemberIds.length; i++) sortedMemberIds[i]: i,
  };

  // Build flat parallel arrays for events: time[], order[], idx[].
  // Working in microseconds-since-epoch keeps the sort comparator a
  // single int compare instead of DateTime.compareTo, which is the
  // dominant cost for 10–40k events.
  final eventCount = memberIntervals.values
      .fold<int>(0, (s, list) => s + list.length * 2);
  final eventTime = List<int>.filled(eventCount, 0);
  final eventOrder = List<int>.filled(eventCount, 0);
  // Parallel `idx` array; sort uses a permutation index instead of
  // moving event records (avoids object construction in the hot path).
  final eventIdx = List<int>.filled(eventCount, 0);
  // kind packed into the same array: encode +1 as 1, -1 as 0 — we then
  // use it as a tiebreaker by storing it in eventOrder as
  // `time * 2 + kindBit` where kindBit=0 (end) sorts before 1 (start).
  // Half-open semantics: at a tied instant, ends (kind=-1) must be
  // processed before starts (kind=+1) so touching intervals don't
  // accrue spurious overlap (see the (a, c)=0 test).

  var ei = 0;
  for (final entry in memberIntervals.entries) {
    final idx = memberIdToIdx[entry.key]!;
    for (final iv in entry.value) {
      final startMicros = iv.start.microsecondsSinceEpoch;
      final endMicros = iv.end.microsecondsSinceEpoch;
      eventTime[ei] = startMicros;
      // start kindBit = 1 (sorts after ends at same instant)
      eventOrder[ei] = startMicros * 2 + 1;
      eventIdx[ei] = idx + 1; // sign-encode: positive = start, negative = end
      ei++;
      eventTime[ei] = endMicros;
      eventOrder[ei] = endMicros * 2;
      eventIdx[ei] = -(idx + 1);
      ei++;
    }
  }

  // Argsort: sort an index permutation by eventOrder.
  final perm = List<int>.generate(eventCount, (i) => i);
  perm.sort((a, b) => eventOrder[a].compareTo(eventOrder[b]));

  // Active members: ref-counted to handle a single member with two
  // overlapping rows of their own (no self-pairs — they enter the
  // active set once for the union of their rows). We track the active
  // *list* alongside the count map so the inner pair pass is O(K²)
  // without re-sorting K active ids per event.
  final activeCounts = List<int>.filled(sortedMemberIds.length, 0);
  // Sorted-by-idx active list (idx is already lex order).
  final activeIdx = <int>[];

  // Pair accumulator keyed by packed `a * memberCount + b` (a < b).
  // Map<int,int> avoids per-pair string allocations.
  final pairAccumMicros = <int, int>{};
  final memberCount = sortedMemberIds.length;

  // ── Wall-clock gap + switch count ────────────────────────────────────
  //
  // `gapMicros` accumulates wall-clock time during which the active set
  // is empty.  Replaces the old `rangeSpan - sum(member_minutes)` clamp,
  // which returned zero whenever heavy co-fronting pushed the sum past
  // the range span.  Initialized so the leading delta from `range.start`
  // up to the first event counts as a gap (the active set is empty
  // before the first start event lands).
  //
  // `switches` counts distinct active-set composition changes across
  // the sweep.  We collapse all events at a tied timestamp into a single
  // comparison: a same-instant swap (A ends at T, B starts at T) is one
  // transition, not two — even though the sweep emits two events for it.
  //
  // Switch semantic (pinned): every moment the active *set* changes
  // counts as one switch.  Sessions starting from an empty active set
  // (the first start event after a gap, or the first event in the range)
  // are switches.  A pure addition (A solo → A+B) and a pure removal
  // (A+B → A solo) are both switches.  A swap (A → B at instant T)
  // collapses to one switch because both events share a timestamp and
  // we compare set membership once per distinct timestamp.
  //
  // Both updates are O(1) per distinct-timestamp tick, so they don't
  // change the existing sweep's complexity.
  var gapMicros = 0;
  var switches = 0;
  final rangeStartMicros = range.start.microsecondsSinceEpoch;
  final rangeEndMicros = range.end.microsecondsSinceEpoch;
  // Seed `lastTime` at the range start so the leading delta (range start
  // → first event) is captured as a gap when no session is active yet.
  var lastTime = rangeStartMicros;
  // Remember the active-set membership snapshot at `lastTime` so a tied
  // batch of events is compared against the pre-batch state, not against
  // an intermediate state we observed mid-batch. We bump this whenever
  // we cross into a distinct timestamp.
  var lastActiveSnapshot = activeIdx.toList();

  for (var pIdx = 0; pIdx < perm.length; pIdx++) {
    final pi = perm[pIdx];
    final t = eventTime[pi];

    // First event in a tied-timestamp batch: process the delta from
    // `lastTime` to `t` against the pre-batch active set, and snapshot
    // the active set as it stood at `lastTime` for switch comparison
    // when the batch finishes processing.
    final isBatchStart = pIdx == 0 || eventTime[perm[pIdx - 1]] != t;
    if (isBatchStart) {
      final delta = t - lastTime;
      if (delta > 0) {
        if (activeIdx.isEmpty) {
          gapMicros += delta;
        } else if (activeIdx.length > 1) {
          final n = activeIdx.length;
          for (var i = 0; i < n; i++) {
            final a = activeIdx[i];
            final aBase = a * memberCount;
            for (var j = i + 1; j < n; j++) {
              final key = aBase + activeIdx[j];
              pairAccumMicros[key] = (pairAccumMicros[key] ?? 0) + delta;
            }
          }
        }
      }
      // Snapshot the pre-batch active set; the switch comparison at
      // batch-end is against this state.
      lastActiveSnapshot = activeIdx.toList();
    }

    final signed = eventIdx[pi];
    if (signed > 0) {
      // start
      final idx = signed - 1;
      final prev = activeCounts[idx];
      activeCounts[idx] = prev + 1;
      if (prev == 0) {
        // Insert idx into activeIdx maintaining ascending order.
        // Linear scan is fine for K ≤ a few dozen.
        var ins = activeIdx.length;
        for (var k = 0; k < activeIdx.length; k++) {
          if (activeIdx[k] > idx) {
            ins = k;
            break;
          }
        }
        activeIdx.insert(ins, idx);
      }
    } else {
      // end
      final idx = -signed - 1;
      final prev = activeCounts[idx];
      activeCounts[idx] = prev - 1;
      if (prev == 1) {
        // Remove idx from activeIdx.
        for (var k = 0; k < activeIdx.length; k++) {
          if (activeIdx[k] == idx) {
            activeIdx.removeAt(k);
            break;
          }
        }
      }
    }

    // Last event in a tied-timestamp batch: compare post-batch active
    // set against the pre-batch snapshot.  If membership differs, count
    // one switch and advance `lastTime`.
    final isBatchEnd =
        pIdx == perm.length - 1 || eventTime[perm[pIdx + 1]] != t;
    if (isBatchEnd) {
      if (!_listsEqual(lastActiveSnapshot, activeIdx)) {
        switches++;
      }
      lastTime = t;
    }
  }

  // Trailing gap: if the sweep ended with the active set empty before
  // `range.end`, the tail interval is also gap time.  (When the last
  // session was still active at `range.end`, all its endTimes were
  // clamped to `range.end` upstream — see the per-row clamp in the
  // ingest loop — so `lastTime` reaches `rangeEndMicros` and there is
  // no trailing gap to add.)
  if (lastTime < rangeEndMicros && activeIdx.isEmpty) {
    gapMicros += rangeEndMicros - lastTime;
  }

  final totalGap = Duration(microseconds: gapMicros);
  final days = rangeSpan.inHours / 24.0;
  final switchesPerDay = days > 0 ? switches / days : 0.0;

  final sortedPairs = pairAccumMicros.entries
      .map((e) {
        final a = e.key ~/ memberCount;
        final b = e.key % memberCount;
        return CoFrontingPair(
          memberIdA: sortedMemberIds[a],
          memberIdB: sortedMemberIds[b],
          totalTime: Duration(microseconds: e.value),
        );
      })
      .toList()
    ..sort((a, b) => b.totalTime.compareTo(a.totalTime));
  final topCoFrontingPairs = sortedPairs.take(3).toList();

  return FrontingAnalytics(
    rangeStart: range.start,
    rangeEnd: range.end,
    totalTrackedTime: totalMemberMinutes,
    // No clamp needed: `gapMicros` is non-negative by construction
    // (it's a running sum of strictly-positive deltas).
    totalGapTime: totalGap,
    totalSessions: rows.length,
    uniqueFronters: memberDurations.keys.length,
    switchesPerDay: switchesPerDay,
    memberStats: memberStats,
    medianSession: medianSession,
    topCoFrontingPairs: topCoFrontingPairs,
  );
}

/// Returns `true` when [a] and [b] hold the same ints in the same order.
/// Used by the sweep-line switch detector to compare pre-batch and
/// post-batch active sets without allocating a Set.
bool _listsEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
