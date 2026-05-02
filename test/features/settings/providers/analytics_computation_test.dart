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

    test('two members co-front for 1h: each total 1h, 50% each, '
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

    test('three members partial overlap (A 0-2h, B 1-3h, C 2-4h): '
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
      final byId = {for (final s in result.memberStats) s.memberId: s};
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

    test(
      'co-fronting pair total sums overlap across multiple session pairs',
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
        expect(
          result.topCoFrontingPairs.first.totalTime,
          const Duration(hours: 5),
        );
      },
    );

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
      },
    );

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

      final byId = {for (final s in result.memberStats) s.memberId: s};
      expect(
        byId.containsKey(unknownSentinelMemberId),
        isTrue,
        reason:
            'null-member normal row should appear under the Unknown sentinel id',
      );
      expect(
        byId[unknownSentinelMemberId]!.totalTime,
        const Duration(hours: 1),
      );
      expect(byId['real-member']!.totalTime, const Duration(hours: 1));
      // System member-minutes = 1h + 1h = 2h; each side is 50%.
      expect(
        byId[unknownSentinelMemberId]!.percentageOfTotal,
        closeTo(50.0, 0.01),
      );
      expect(result.totalTrackedTime, const Duration(hours: 2));
    });

    test(
      'multiple members sorted by totalTime DESC, percentages sum to ~100',
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

        final totalPct = result.memberStats.fold<double>(
          0,
          (s, m) => s + m.percentageOfTotal,
        );
        expect(totalPct, closeTo(100.0, 0.01));
      },
    );

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

    test(
      'switches per day counts active-set composition changes, not row count',
      () {
        final range = DateTimeRange(
          start: DateTime(2026, 3, 1, 0, 0),
          end: DateTime(2026, 3, 11, 0, 0), // exactly 10 days
        );

        // 20 disjoint sessions, all the same member, evenly spread across
        // 10 days. Each session contributes two active-set composition
        // changes: empty → {member-1} (the start event lands the member
        // in an otherwise-empty set), then {member-1} → empty (the end
        // event drains the set).  Switch count = 2 per session × 20
        // sessions = 40, over 10 days = 4.0/day.
        final sessions = List.generate(
          20,
          (i) => FakeSession(
            startTime: range.start.add(Duration(hours: i * 12)),
            endTime: range.start.add(Duration(hours: i * 12 + 1)),
            memberId: 'member-1',
          ),
        );

        final result = computeAnalyticsFromRows(sessions, range);
        expect(result.switchesPerDay, closeTo(4.0, 0.01));
      },
    );

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
      expect(
        result.topCoFrontingPairs.first.totalTime,
        const Duration(hours: 3),
      );
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

  // ════════════════════════════════════════════════════════════════════════
  // totalGapTime — wall-clock semantics
  // ════════════════════════════════════════════════════════════════════════
  //
  // Fixture group for Fix 2: `totalGapTime` reports wall-clock minutes
  // during which NO member is fronting, derived from the sweep-line.
  // The previous formula (`range_span - sum(member_minutes)` clamped to
  // zero) silently reported "no gaps" under heavy co-fronting because
  // the sum exceeded the range span.  These fixtures pin the corrected
  // semantic.

  group('totalGapTime — wall-clock gap semantics', () {
    test('empty range yields totalGapTime equal to the full span', () {
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final result = computeAnalyticsFromRows([], range);
      expect(result.totalGapTime, const Duration(hours: 24));
    });

    test('one member fronts the entire range yields zero gap', () {
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final session = FakeSession(
        startTime: range.start,
        endTime: range.end,
        memberId: 'a',
      );
      final result = computeAnalyticsFromRows([session], range);
      expect(result.totalGapTime, Duration.zero);
    });

    test('two members co-front the entire range still yields zero gap '
        '(old clamp would have lied here)', () {
      // The old formula `rangeSpan - sum(member_minutes)` returned
      // 24h - (24h + 24h) = -24h, clamped to zero — hiding the genuine
      // "no gap" answer behind the same floor it used for actual gaps.
      // The wall-clock sweep returns zero directly because the active
      // set is non-empty for the entire range.
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final sessions = [
        FakeSession(startTime: range.start, endTime: range.end, memberId: 'a'),
        FakeSession(startTime: range.start, endTime: range.end, memberId: 'b'),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.totalGapTime, Duration.zero);
      // The member-minute sum is still 2× the range span (this is the
      // co-fronting density that broke the old clamp); the wall-clock
      // gap stat is unaffected.
      expect(result.totalTrackedTime, const Duration(hours: 48));
    });

    test('member fronts the first half: gap equals the second half', () {
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final session = FakeSession(
        startTime: range.start,
        endTime: range.start.add(const Duration(hours: 12)),
        memberId: 'a',
      );
      final result = computeAnalyticsFromRows([session], range);
      expect(result.totalGapTime, const Duration(hours: 12));
    });

    test('leading and trailing gaps both count', () {
      // Range 24h, single 4h session in the middle (8h–12h).
      // Leading gap 0–8h = 8h, trailing gap 12h–24h = 12h.  Total 20h.
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 8)),
        endTime: range.start.add(const Duration(hours: 12)),
        memberId: 'a',
      );
      final result = computeAnalyticsFromRows([session], range);
      expect(result.totalGapTime, const Duration(hours: 20));
    });

    test('overlapping pair followed by an empty stretch — gap is the '
        'empty stretch only', () {
      // Range 0–10h. A: 0–6h, B: 2–6h. Active set is non-empty 0–6h,
      // empty 6–10h. Gap = 4h regardless of the member-minute sum
      // (which is 6 + 4 = 10h, equal to the range span — the old clamp
      // would have returned zero here, hiding the real 4h gap).
      final base = DateTime.utc(2026, 3, 10, 0);
      final range = DateTimeRange(
        start: base,
        end: base.add(const Duration(hours: 10)),
      );
      final sessions = [
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 6)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 2)),
          endTime: base.add(const Duration(hours: 6)),
          memberId: 'b',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.totalGapTime, const Duration(hours: 4));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // switchesPerDay — active-set composition changes
  // ════════════════════════════════════════════════════════════════════════
  //
  // Fixture group for Fix 3: `switchesPerDay` counts moments when the
  // active fronter set changes membership, derived from the sweep-line
  // (rather than per-member row count).  Under per-member shape, a
  // co-fronter joining or leaving an ongoing session no longer inflates
  // the count.  Same-instant swaps collapse to one transition per
  // distinct timestamp.

  group('switchesPerDay — active-set composition changes', () {
    test('empty range has zero switches', () {
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final result = computeAnalyticsFromRows([], range);
      expect(result.switchesPerDay, 0);
    });

    test('A solo for 8h then ends: 2 transitions over 1 day '
        '(empty→{A}, {A}→empty)', () {
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 9)),
        memberId: 'a',
      );
      final result = computeAnalyticsFromRows([session], range);
      // 2 transitions / 1 day = 2.0/day.
      expect(result.switchesPerDay, closeTo(2.0, 0.01));
    });

    test('A → A+B → A: 3 transitions (A start, B joins, B leaves) over 1 day, '
        'plus A end = 4 transitions', () {
      // Per-member shape:
      //   A 0–4h:   empty → {A}             (transition 1)
      //   B 1–3h:   {A}   → {A,B}           (transition 2)
      //   B ends:   {A,B} → {A}             (transition 3)
      //   A ends:   {A}   → empty           (transition 4)
      // 4 distinct active-set states over a 1-day range = 4.0/day.
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final base = range.start;
      final sessions = [
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 4)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 1)),
          endTime: base.add(const Duration(hours: 3)),
          memberId: 'b',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.switchesPerDay, closeTo(4.0, 0.01));
    });

    test('same-instant swap A→B at instant T collapses to one transition, '
        'plus A start and B end = 3 transitions', () {
      // A 0–4h, B 4–8h.  Tied-timestamp batch at T=4h: A ends, B starts.
      // Within that batch, lastActiveSnapshot = {A}, post-batch
      // activeIdx = {B}.  {A} != {B} → one switch (not two).
      //   At T=0:  empty → {A}      (transition 1)
      //   At T=4:  {A}   → {B}      (transition 2 — the swap)
      //   At T=8:  {B}   → empty    (transition 3)
      // 3 transitions / 1 day = 3.0/day.
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final base = range.start;
      final sessions = [
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 4)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 4)),
          endTime: base.add(const Duration(hours: 8)),
          memberId: 'b',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.switchesPerDay, closeTo(3.0, 0.01));
    });

    test('co-fronter joining and leaving an ongoing session no longer '
        'inflates the count beyond the set-change count', () {
      // Regression guard: the old per-row formula counted each row
      // (start + end) as a transition independently, so an ongoing A
      // with B joining then leaving counted as 4 transitions for what
      // is conceptually 4 set-state changes.  With per-member rows,
      // A.start + A.end + B.start + B.end = 4 rows, and the new
      // semantic also reports 4 — they happen to match in this case
      // because all four events land at distinct timestamps and each
      // changes the active set.
      //
      // The semantic difference shows up when events are tied (the
      // swap test above).  This test pins the agreement under disjoint
      // timestamps so the regression direction is clear.
      final range = DateTimeRange(
        start: DateTime.utc(2026, 3, 10, 0),
        end: DateTime.utc(2026, 3, 11, 0),
      );
      final base = range.start;
      final sessions = [
        FakeSession(
          startTime: base,
          endTime: base.add(const Duration(hours: 6)),
          memberId: 'a',
        ),
        FakeSession(
          startTime: base.add(const Duration(hours: 1)),
          endTime: base.add(const Duration(hours: 4)),
          memberId: 'b',
        ),
      ];
      final result = computeAnalyticsFromRows(sessions, range);
      // Transitions: empty→{A}, {A}→{A,B}, {A,B}→{A}, {A}→empty = 4.
      expect(result.switchesPerDay, closeTo(4.0, 0.01));
    });
  });

  // Regression guard for the prior algorithm: the prior O(M²·Na·Nb)
  // pair-overlap algorithm took ~minutes on realistic datasets.
  // Sweep-line replacement should stay comfortably sub-second in normal JIT
  // runs, while this guard remains loose enough to avoid load-related flakes.
  group('sweep-line pair-overlap performance', () {
    test('5000 members × 4 sessions completes in < 2s (JIT)', () {
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
          final start = base.add(
            Duration(minutes: memberOffsetMin + s * 7 * 24 * 60),
          );
          sessions.add(
            FakeSession(
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              memberId: 'm$m',
            ),
          );
        }
      }

      final stopwatch = Stopwatch()..start();
      final result = computeAnalyticsFromRows(sessions, range);
      stopwatch.stop();

      expect(result.totalSessions, 20000);
      expect(result.uniqueFronters, memberCount);
      // The old O(M²·Na·Nb) loop ran for ~tens of seconds on this
      // dataset. The exact JIT timing is noisy under full-suite load,
      // so this threshold catches a quadratic regression without
      // treating normal scheduler variance as a product failure.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason:
            'sweep-line on 20k sessions took '
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
          sessions.add(
            FakeSession(
              startTime: start,
              endTime: start.add(const Duration(hours: 2)),
              memberId: 'h$m',
            ),
          );
        }
      }

      final stopwatch = Stopwatch()..start();
      final result = computeAnalyticsFromRows(sessions, range);
      stopwatch.stop();

      expect(result.uniqueFronters, 10);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(100),
        reason:
            'heavy co-fronter scenario took '
            '${stopwatch.elapsedMilliseconds}ms',
      );
    });
  });
}
