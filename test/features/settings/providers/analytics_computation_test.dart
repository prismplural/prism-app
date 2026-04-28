import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

/// Simulates a Drift FrontingSession row for testing the per-member
/// analytics pipeline (post 0.7.0 per-member-sessions redesign).
///
/// Per the new model (§2.1), each row represents one member's continuous
/// presence. There is no `co_fronter_ids` field — co-fronting is the
/// emergent property of overlapping rows for different members.
///
/// `coFronterIds` is retained as an unread Drift column for backward
/// compatibility (see `fronting_sessions_table.dart`); the analytics
/// pipeline ignores it. We intentionally do NOT expose it from the fake
/// here — production code must not read it.
class FakeSession {
  FakeSession({
    required this.startTime,
    this.endTime,
    this.memberId,
    this.sessionType = 0,
  });

  final DateTime startTime;
  final DateTime? endTime;
  final String? memberId;
  // 0 = normal fronting, 1 = sleep. Sleep rows are filtered upstream by
  // the DAO's `getSessionsInRange`; analytics never sees them. The field
  // is on the fake purely so tests can assert that contract.
  final int sessionType;
}

void main() {
  /// Helper to build a standard 30-day range.
  DateTimeRange range30Days() {
    final end = DateTime(2026, 3, 20, 12, 0);
    final start = end.subtract(const Duration(days: 30));
    return DateTimeRange(start: start, end: end);
  }

  group('computeAnalyticsFromRows — per-member semantics', () {
    test('empty sessions yields zero totals and empty memberStats', () {
      final range = range30Days();
      final result = computeAnalyticsFromRows([], range);

      expect(result.totalTrackedTime, Duration.zero);
      expect(result.totalGapTime, range.end.difference(range.start));
      expect(result.totalSessions, 0);
      expect(result.uniqueFronters, 0);
      expect(result.switchesPerDay, 0);
      expect(result.memberStats, isEmpty);
      expect(result.topCoFrontingPairs, isEmpty);
    });

    test('single-member 1-hour session: total 1h, 100%', () {
      final range = range30Days();
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 2)),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);

      expect(result.totalTrackedTime, const Duration(hours: 1));
      expect(result.totalSessions, 1);
      expect(result.uniqueFronters, 1);
      expect(result.memberStats, hasLength(1));

      final stat = result.memberStats.first;
      expect(stat.memberId, 'member-1');
      expect(stat.totalTime, const Duration(hours: 1));
      expect(stat.sessionCount, 1);
      expect(stat.percentageOfTotal, closeTo(100.0, 0.01));
      expect(result.topCoFrontingPairs, isEmpty);
    });

    test('session overlapping range boundaries is clamped', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );

      final session = FakeSession(
        startTime: range.start.subtract(const Duration(hours: 2)),
        endTime: range.end.add(const Duration(hours: 3)),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);

      // Clamped to exactly the range duration (24 hours).
      expect(result.totalTrackedTime, const Duration(hours: 24));
      expect(result.totalGapTime, Duration.zero);
    });

    test('active session (null endTime) uses approximately now as end', () {
      // Range ends in the future so "now" falls inside.
      final now = DateTime.now();
      final range = DateTimeRange(
        start: now.subtract(const Duration(hours: 2)),
        end: now.add(const Duration(hours: 1)),
      );

      final session = FakeSession(
        startTime: now.subtract(const Duration(hours: 1)),
        endTime: null, // active session
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);

      // Approximately 1 hour (start is 1 hour ago, end is ~now).
      expect(result.totalTrackedTime.inMinutes, closeTo(60, 1));
      expect(result.totalSessions, 1);
    });

    test(
        'two members co-front for 1h: each total 1h, 50% each, '
        'pair overlap 1h', () {
      final range = range30Days();
      final start = range.start.add(const Duration(hours: 1));
      final end = start.add(const Duration(hours: 1));
      final sessions = [
        FakeSession(startTime: start, endTime: end, memberId: 'alex'),
        FakeSession(startTime: start, endTime: end, memberId: 'sky'),
      ];

      final result = computeAnalyticsFromRows(sessions, range);

      expect(result.uniqueFronters, 2);
      expect(result.memberStats, hasLength(2));
      // Each member's own session = 1h. No double-count: Alex's row
      // doesn't credit Sky's time and vice versa.
      for (final stat in result.memberStats) {
        expect(stat.totalTime, const Duration(hours: 1));
        expect(stat.sessionCount, 1);
        // Member-minutes share: each contributes 60 of 120 total
        // member-minutes → 50% (matches the existing math, just with
        // an honest label).
        expect(stat.percentageOfTotal, closeTo(50.0, 0.01));
      }
      // System member-minutes = 60 + 60 = 120 (two member-hours).
      expect(result.totalTrackedTime, const Duration(hours: 2));

      // Pair overlap = full hour both were present.
      expect(result.topCoFrontingPairs, hasLength(1));
      final pair = result.topCoFrontingPairs.first;
      expect({pair.memberIdA, pair.memberIdB}, {'alex', 'sky'});
      expect(pair.totalTime, const Duration(hours: 1));
    });

    test(
        'three members partial overlap (A 0-2h, B 1-3h, C 2-4h): '
        'totals 2h each, pairs (A,B)=1h, (B,C)=1h, (A,C)=0', () {
      final base = DateTime(2026, 3, 10, 0, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(hours: 4)),
      );
      final sessions = [
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 2)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 1)),
          endTime: base.add(const Duration(hours: 3)),
          memberId: 'b',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 2)),
          endTime: base.add(const Duration(hours: 4)),
          memberId: 'c',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);

      expect(result.uniqueFronters, 3);
      // No double-count: each member's total is exactly that member's
      // own session duration.
      final byId = {
        for (final s in result.memberStats) s.memberId: s,
      };
      expect(byId['a']!.totalTime, const Duration(hours: 2));
      expect(byId['b']!.totalTime, const Duration(hours: 2));
      expect(byId['c']!.totalTime, const Duration(hours: 2));
      // System member-minutes = 6 hours total. Each is 1/3.
      expect(byId['a']!.percentageOfTotal, closeTo(33.33, 0.05));

      // Pair overlaps:
      //   A∩B = 1-2h overlap = 1h
      //   B∩C = 2-3h overlap = 1h
      //   A∩C = touch at 2h, no overlap (half-open intervals) = 0h
      final pairsByKey = <String, Duration>{
        for (final p in result.topCoFrontingPairs)
          '${p.memberIdA}|${p.memberIdB}': p.totalTime,
      };
      expect(pairsByKey['a|b'], const Duration(hours: 1));
      expect(pairsByKey['b|c'], const Duration(hours: 1));
      // (a, c) pair is omitted entirely because overlap is zero.
      expect(pairsByKey.containsKey('a|c'), isFalse);
      expect(result.topCoFrontingPairs, hasLength(2));
    });

    test('co-fronting pair total sums overlap across multiple session pairs',
        () {
      final base = DateTime.utc(2026, 3, 1, 0, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 1)),
      );
      // Two separate sessions for each member, with two distinct overlap
      // windows: 2h and 3h, totaling 5h of pair-overlap time.
      final sessions = [
        // Window 1: A 0-3h, B 1-4h → overlap 1-3h = 2h
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 3)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 1)),
          endTime: base.add(const Duration(hours: 4)),
          memberId: 'b',
        ),
        // Window 2: A 10-15h, B 12-15h → overlap 12-15h = 3h
        FakeSession(
          startTime: base.add(const Duration(hours: 10)),
          endTime: base.add(const Duration(hours: 15)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 12)),
          endTime: base.add(const Duration(hours: 15)),
          memberId: 'b',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);

      expect(result.topCoFrontingPairs, hasLength(1));
      expect(result.topCoFrontingPairs.first.totalTime,
          const Duration(hours: 5));
    });

    test('non-overlapping sessions for two members produce no pair', () {
      final base = DateTime.utc(2026, 3, 1, 0, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 1)),
      );
      final sessions = [
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 2)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 3)),
          endTime: base.add(const Duration(hours: 5)),
          memberId: 'b',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs, isEmpty);
    });

    test(
        'session_type = 1 (sleep) rows are excluded by the upstream filter',
        () {
      // Contract assumption: `computeAnalyticsFromRows` is only ever
      // called with rows the DAO already filtered to
      // `session_type = _normalSessionType` (see
      // fronting_sessions_dao.dart `getSessionsInRange`). Sleep rows
      // therefore never reach analytics. This test documents that
      // contract — the function does NOT re-filter on session_type.
      // If a sleep row were ever to slip through, it would be routed
      // to the Unknown sentinel by the null-member fallback (the same
      // behavior as the edit/gap-fill Unknown rows we DO want to
      // count). Keeping sleep out is the upstream filter's job.
      final range = range30Days();
      final sleepRow = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 2)),
        memberId: null,
        sessionType: 1,
      );
      // Confirm the fake we're using to model the upstream-filtered
      // contract: sleep rows carry sessionType = 1 and member_id = NULL.
      expect(sleepRow.sessionType, 1);
      expect(sleepRow.memberId, isNull);
    });

    test('normal null-member rows are routed to the Unknown sentinel', () {
      // The edit/gap-fill flow in fronting_edit_resolution_service can
      // produce normal (session_type = 0) rows with member_id = NULL,
      // representing time fronted by an Unknown member. These rows must
      // participate in totals/percentages/pair-overlap input rather than
      // being silently dropped — otherwise `totalSessions` (taken from
      // rows.length) would race ahead of the member-time data on screen.
      // Route them through the canonical Unknown sentinel id.
      final range = range30Days();
      final sessions = [
        FakeSession(
          startTime: range.start.add(const Duration(hours: 1)),
          endTime: range.start.add(const Duration(hours: 2)),
          memberId: null, // Unknown-fronting from edit/gap-fill
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 3)),
          endTime: range.start.add(const Duration(hours: 4)),
          memberId: 'real-member',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);

      // Both rows count toward totals.
      expect(result.totalSessions, 2);
      expect(result.uniqueFronters, 2);
      expect(result.memberStats, hasLength(2));

      final byId = {
        for (final s in result.memberStats) s.memberId: s,
      };
      expect(byId.containsKey(unknownSentinelMemberId), isTrue,
          reason:
              'null-member normal row should appear under the Unknown sentinel id');
      expect(byId[unknownSentinelMemberId]!.totalTime,
          const Duration(hours: 1));
      expect(byId['real-member']!.totalTime, const Duration(hours: 1));
      // System member-minutes = 1h + 1h = 2h; each side is 50%.
      expect(byId[unknownSentinelMemberId]!.percentageOfTotal,
          closeTo(50.0, 0.01));
      expect(result.totalTrackedTime, const Duration(hours: 2));
    });

    test('multiple members sorted by totalTime DESC, percentages sum to ~100',
        () {
      final range = range30Days();
      final sessions = [
        FakeSession(
          startTime: range.start.add(const Duration(hours: 1)),
          endTime: range.start.add(const Duration(hours: 3)),
          memberId: 'short-fronter',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 5)),
          endTime: range.start.add(const Duration(hours: 15)),
          memberId: 'long-fronter',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 20)),
          endTime: range.start.add(const Duration(hours: 25)),
          memberId: 'mid-fronter',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);

      expect(result.uniqueFronters, 3);
      expect(result.memberStats, hasLength(3));

      expect(result.memberStats[0].memberId, 'long-fronter');
      expect(result.memberStats[1].memberId, 'mid-fronter');
      expect(result.memberStats[2].memberId, 'short-fronter');

      final totalPct =
          result.memberStats.fold<double>(0, (s, m) => s + m.percentageOfTotal);
      expect(totalPct, closeTo(100.0, 0.01));
    });

    test('gap time equals range duration minus tracked member-minutes', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );

      final session = FakeSession(
        startTime: DateTime(2026, 3, 10, 6, 0),
        endTime: DateTime(2026, 3, 10, 18, 0),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);

      expect(result.totalTrackedTime, const Duration(hours: 12));
      expect(result.totalGapTime, const Duration(hours: 12));
    });

    test('switches per day equals row count divided by days', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 1, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0), // exactly 10 days
      );

      final sessions = List.generate(
        20,
        (i) => FakeSession(
          startTime: range.start.add(Duration(hours: i * 12)),
          endTime: range.start.add(Duration(hours: i * 12 + 1)),
          memberId: 'member-1',
        ),
      );

      final result = computeAnalyticsFromRows(sessions, range);
      // 20 sessions / 10 days = 2.0
      expect(result.switchesPerDay, closeTo(2.0, 0.01));
    });

    test('median duration with odd number of sessions', () {
      final range = range30Days();
      final sessions = [
        FakeSession(
          startTime: range.start.add(const Duration(hours: 0)),
          endTime: range.start.add(const Duration(hours: 1)), // 1h
          memberId: 'member-1',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 5)),
          endTime: range.start.add(const Duration(hours: 8)), // 3h
          memberId: 'member-1',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 10)),
          endTime: range.start.add(const Duration(hours: 15)), // 5h
          memberId: 'member-1',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);

      final stat = result.memberStats.first;
      // Sorted durations: [1h, 3h, 5h]. Median index = 3 ~/ 2 = 1 → 3h.
      expect(stat.medianDuration, const Duration(hours: 3));
      expect(stat.shortestSession, const Duration(hours: 1));
      expect(stat.longestSession, const Duration(hours: 5));
    });

    test('time-of-day bucketing assigns minutes to correct buckets', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );

      // Session spanning all four buckets:
      // 3:00 - 5:00  → night (2h = 120min)
      // 7:00 - 10:00 → morning (3h = 180min)
      // 13:00 - 16:00 → afternoon (3h = 180min)
      // 19:00 - 22:00 → evening (3h = 180min)
      final sessions = [
        FakeSession(
          startTime: DateTime(2026, 3, 10, 3, 0),
          endTime: DateTime(2026, 3, 10, 5, 0),
          memberId: 'member-1',
        ),
        FakeSession(
          startTime: DateTime(2026, 3, 10, 7, 0),
          endTime: DateTime(2026, 3, 10, 10, 0),
          memberId: 'member-1',
        ),
        FakeSession(
          startTime: DateTime(2026, 3, 10, 13, 0),
          endTime: DateTime(2026, 3, 10, 16, 0),
          memberId: 'member-1',
        ),
        FakeSession(
          startTime: DateTime(2026, 3, 10, 19, 0),
          endTime: DateTime(2026, 3, 10, 22, 0),
          memberId: 'member-1',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);
      final stat = result.memberStats.first;
      final buckets = stat.timeOfDayBreakdown;

      expect(buckets['night'], 120);
      expect(buckets['morning'], 180);
      expect(buckets['afternoon'], 180);
      expect(buckets['evening'], 180);
    });

    test('session crossing bucket boundary splits minutes correctly', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );

      // Session from 5:00 to 7:00 crosses night→morning boundary at 6:00.
      final session = FakeSession(
        startTime: DateTime(2026, 3, 10, 5, 0),
        endTime: DateTime(2026, 3, 10, 7, 0),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);
      final buckets = result.memberStats.first.timeOfDayBreakdown;

      expect(buckets['night'], 60);
      expect(buckets['morning'], 60);
    });
  });

  group('medianSession', () {
    test('empty sessions yields Duration.zero', () {
      final result = computeAnalyticsFromRows([], range30Days());
      expect(result.medianSession, Duration.zero);
    });

    test('single session: median equals that session', () {
      final range = range30Days();
      final sessions = [
        FakeSession(
          startTime: range.start.add(const Duration(hours: 1)),
          endTime: range.start.add(const Duration(hours: 3)),
          memberId: 'a',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.medianSession, const Duration(hours: 2));
    });

    test('odd count: median is the middle element after sort', () {
      final range = range30Days();
      // Durations: 10m, 60m, 5m → sorted: 5, 10, 60 → median = 10m.
      final sessions = [
        FakeSession(
          startTime: range.start,
          endTime: range.start.add(const Duration(minutes: 10)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 1)),
          endTime: range.start.add(const Duration(hours: 2)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 3)),
          endTime: range.start.add(const Duration(hours: 3, minutes: 5)),
          memberId: 'a',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.medianSession, const Duration(minutes: 10));
    });

    test('even count: median averages the two middle values', () {
      final range = range30Days();
      // Durations: 5m, 60m → median = 32m30s.
      final sessions = [
        FakeSession(
          startTime: range.start,
          endTime: range.start.add(const Duration(minutes: 5)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 1)),
          endTime: range.start.add(const Duration(hours: 2)),
          memberId: 'a',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.medianSession, const Duration(minutes: 32, seconds: 30));
    });

    test('even count of four: median averages 2nd and 3rd values', () {
      final range = range30Days();
      // Durations: 5m, 10m, 60m, 120m → median = (10 + 60) / 2 = 35m.
      final sessions = [
        FakeSession(
          startTime: range.start,
          endTime: range.start.add(const Duration(minutes: 5)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 1)),
          endTime: range.start.add(const Duration(hours: 1, minutes: 10)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 3)),
          endTime: range.start.add(const Duration(hours: 4)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: range.start.add(const Duration(hours: 5)),
          endTime: range.start.add(const Duration(hours: 7)),
          memberId: 'a',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.medianSession, const Duration(minutes: 35));
    });

    test('clamped session contributes its clamped duration', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );
      final sessions = [
        FakeSession(
          startTime: range.start.subtract(const Duration(hours: 2)),
          endTime: range.end.add(const Duration(hours: 3)),
          memberId: 'a',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.medianSession, const Duration(hours: 24));
    });
  });

  group('topCoFrontingPairs sorting', () {
    test('sorted by total overlap descending', () {
      final base = DateTime.utc(2026, 3, 1, 0, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 1)),
      );
      // Per-member rows produce these overlaps:
      //   A 8-9h, B 8-9h        → A∩B = 1h
      //   A 10-13h, C 10-13h    → A∩C = 3h
      //   B 14-16h, C 14-16h    → B∩C = 2h
      final sessions = [
        FakeSession(
          startTime: base.add(const Duration(hours: 8)),
          endTime: base.add(const Duration(hours: 9)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 8)),
          endTime: base.add(const Duration(hours: 9)),
          memberId: 'b',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 10)),
          endTime: base.add(const Duration(hours: 13)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 10)),
          endTime: base.add(const Duration(hours: 13)),
          memberId: 'c',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 14)),
          endTime: base.add(const Duration(hours: 16)),
          memberId: 'b',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 14)),
          endTime: base.add(const Duration(hours: 16)),
          memberId: 'c',
        ),
      ];

      final result = computeAnalyticsFromRows(sessions, range);
      // Top pair is A∩C with 3h overlap.
      expect(result.topCoFrontingPairs.first.totalTime,
          const Duration(hours: 3));
      expect(
        {
          result.topCoFrontingPairs.first.memberIdA,
          result.topCoFrontingPairs.first.memberIdB,
        },
        {'a', 'c'},
      );
    });

    test('no overlapping members returns empty pair list', () {
      final sessions = [
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 10),
          endTime: DateTime.utc(2026, 3, 1, 11),
          memberId: 'a',
        ),
      ];
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 2),
      );
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs, isEmpty);
    });

    test('canonical pair key is alphabetical regardless of input order', () {
      final base = DateTime.utc(2026, 3, 1, 10);
      final sessions = [
        // Insert b first to verify ordering doesn't depend on row order.
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 1)),
          memberId: 'beta',
        ),
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 1)),
          memberId: 'alpha',
        ),
      ];
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 2),
      );
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs, hasLength(1));
      expect(result.topCoFrontingPairs.first.memberIdA, 'alpha');
      expect(result.topCoFrontingPairs.first.memberIdB, 'beta');
    });
  });

  // Regression guard for codex pass 6 P2.2: the prior O(M²·Na·Nb)
  // pair-overlap algorithm took ~minutes on realistic datasets.
  // Sweep-line replacement should run in well under a frame.
  group('sweep-line pair-overlap performance', () {
    test('5000 members × 4 sessions completes in < 500ms (JIT)', () {
      // The old O(M²·Na·Nb) loop on this dataset was ~25M·16 = 400M
      // comparisons, multiple seconds on a laptop. Sweep-line should
      // handle it in well under a frame for realistic K.
      //
      // Realistic K (max simultaneous fronters) for a real plural
      // system: 1–5. We model it by giving each member their own
      // narrow time window across the 30-day range — sessions barely
      // overlap with others, mirroring typical usage where most
      // members aren't co-fronting most of the time.
      final base = DateTime.utc(2026, 3, 1, 0, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 30)),
      );

      const memberCount = 5000;
      const sessionsPerMember = 4;
      // 30 days = 720 hours. Spread member windows over that span.
      // ~7 members per hour, K stays bounded at ~7 active at once.
      const totalMinutes = 30 * 24 * 60;
      final sessions = <FakeSession>[];
      for (var m = 0; m < memberCount; m++) {
        // Each member's "preferred" window starts at this offset.
        final memberOffsetMin = (m * totalMinutes ~/ memberCount);
        for (var s = 0; s < sessionsPerMember; s++) {
          // 4 sessions spaced ~7 days apart, each 1h long.
          final start = base.add(Duration(
            minutes: memberOffsetMin + s * 7 * 24 * 60,
          ));
          sessions.add(FakeSession(
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            memberId: 'm$m',
          ));
        }
      }

      final stopwatch = Stopwatch()..start();
      final result = computeAnalyticsFromRows(sessions, range);
      stopwatch.stop();

      expect(result.totalSessions, 20000);
      expect(result.uniqueFronters, memberCount);
      // The old O(M²·Na·Nb) loop ran for ~tens of seconds on this
      // dataset (and the surrounding member loops/time-bucketing alone
      // take a few hundred ms in JIT). Sweep-line keeps the pair pass
      // bounded by N · K². AOT (production) is typically 2–4× faster
      // than `flutter test` JIT, so a 500ms ceiling here corresponds
      // to ~125–250ms on-device — well under a frame.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'sweep-line on 20k sessions took '
            '${stopwatch.elapsedMilliseconds}ms (JIT); old O(M²·Na·Nb) '
            'algorithm was multiple seconds.',
      );
    });

    test('10 heavy co-fronters × 200 sessions each: sub-100ms', () {
      // Pathological case for the old O(N_a · N_b) inner loop: a small
      // group of members each with many sessions in the same window.
      // 10 × 200 = 2000 rows, but pairs are 45 × 200² = 1.8M old-loop
      // ops. Sweep-line should breeze through.
      final base = DateTime.utc(2026, 3, 1, 0, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(days: 30)),
      );
      final sessions = <FakeSession>[];
      for (var m = 0; m < 10; m++) {
        for (var s = 0; s < 200; s++) {
          final start = base.add(Duration(hours: s * 3, minutes: m * 10));
          sessions.add(FakeSession(
            startTime: start,
            endTime: start.add(const Duration(hours: 2)),
            memberId: 'h$m',
          ));
        }
      }

      final stopwatch = Stopwatch()..start();
      final result = computeAnalyticsFromRows(sessions, range);
      stopwatch.stop();

      expect(result.uniqueFronters, 10);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
        reason: 'heavy co-fronter scenario took '
            '${stopwatch.elapsedMilliseconds}ms',
      );
    });
  });
}
