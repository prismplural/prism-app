import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/providers/analytics_providers.dart';

/// Simulates a Drift FrontingSession row for testing.
///
/// [coFronterIds] accepts either a JSON-encoded String (e.g. `'[]'` or
/// `jsonEncode(['id1'])`) or a `List<String>` which will be JSON-encoded
/// automatically. Defaults to `'[]'`.
class FakeSession {
  final DateTime startTime;
  final DateTime? endTime;
  final String? memberId;
  final String coFronterIds;

  FakeSession({
    required this.startTime,
    this.endTime,
    this.memberId,
    Object coFronterIds = '[]',
  }) : coFronterIds = coFronterIds is List
            ? jsonEncode(coFronterIds)
            : coFronterIds as String;
}

void main() {
  /// Helper to build a standard 30-day range.
  DateTimeRange range30Days() {
    final end = DateTime(2026, 3, 20, 12, 0);
    final start = end.subtract(const Duration(days: 30));
    return DateTimeRange(start: start, end: end);
  }

  group('computeAnalyticsFromRows', () {
    test('empty sessions yields zero totals and empty memberStats', () {
      final range = range30Days();
      final result = computeAnalyticsFromRows([], range);

      expect(result.totalTrackedTime, Duration.zero);
      expect(result.totalGapTime, range.end.difference(range.start));
      expect(result.totalSessions, 0);
      expect(result.uniqueFronters, 0);
      expect(result.switchesPerDay, 0);
      expect(result.memberStats, isEmpty);
    });

    test('single session fully within range computes correctly', () {
      final range = range30Days();
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 3)),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);

      expect(result.totalTrackedTime, const Duration(hours: 2));
      expect(result.totalSessions, 1);
      expect(result.uniqueFronters, 1);
      expect(result.memberStats, hasLength(1));

      final stat = result.memberStats.first;
      expect(stat.memberId, 'member-1');
      expect(stat.totalTime, const Duration(hours: 2));
      expect(stat.sessionCount, 1);
      expect(stat.percentageOfTotal, closeTo(100.0, 0.01));
    });

    test('session overlapping range boundaries is clamped', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );

      // Session starts 2 hours before range, ends 3 hours after range
      final session = FakeSession(
        startTime: range.start.subtract(const Duration(hours: 2)),
        endTime: range.end.add(const Duration(hours: 3)),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);

      // Should be clamped to exactly the range duration (24 hours)
      expect(result.totalTrackedTime, const Duration(hours: 24));
      expect(result.totalGapTime, Duration.zero);
    });

    test('active session (null endTime) uses approximately now as end', () {
      // Use a range that ends in the future so the "now" value falls inside
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

      // Should be approximately 1 hour (since start is 1 hour ago, end is ~now)
      expect(result.totalTrackedTime.inMinutes, closeTo(60, 1));
      expect(result.totalSessions, 1);
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

      // Sorted DESC by totalTime
      expect(result.memberStats[0].memberId, 'long-fronter');
      expect(result.memberStats[1].memberId, 'mid-fronter');
      expect(result.memberStats[2].memberId, 'short-fronter');

      final totalPct =
          result.memberStats.fold<double>(0, (s, m) => s + m.percentageOfTotal);
      expect(totalPct, closeTo(100.0, 0.01));
    });

    test('co-fronters each get credit for the full session duration', () {
      final range = range30Days();
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 4)),
        memberId: 'primary',
        coFronterIds: jsonEncode(['co-1', 'co-2']),
      );

      final result = computeAnalyticsFromRows([session], range);

      expect(result.uniqueFronters, 3);
      expect(result.memberStats, hasLength(3));

      // Each member (primary + 2 co-fronters) should have 3 hours
      for (final stat in result.memberStats) {
        expect(stat.totalTime, const Duration(hours: 3));
        expect(stat.sessionCount, 1);
      }
    });

    test('co-fronter parsing with empty string does not crash', () {
      final range = range30Days();
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 2)),
        memberId: 'member-1',
        coFronterIds: '',
      );

      final result = computeAnalyticsFromRows([session], range);

      expect(result.uniqueFronters, 1);
      expect(result.memberStats, hasLength(1));
    });

    test('co-fronter parsing with malformed JSON does not crash', () {
      final range = range30Days();
      final session = FakeSession(
        startTime: range.start.add(const Duration(hours: 1)),
        endTime: range.start.add(const Duration(hours: 2)),
        memberId: 'member-1',
        coFronterIds: '{not valid json!!!',
      );

      final result = computeAnalyticsFromRows([session], range);

      // Should silently catch the JSON error and only count the primary
      expect(result.uniqueFronters, 1);
      expect(result.memberStats, hasLength(1));
    });

    test('gap time equals range duration minus tracked time', () {
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

    test('switches per day equals sessions divided by days', () {
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

      // 20 sessions / 10 days = 2.0 switches per day
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
      // Sorted durations: [1h, 3h, 5h]. Median index = 3 ~/ 2 = 1 → 3h
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

      expect(buckets['night'], 120); // 3:00-5:00
      expect(buckets['morning'], 180); // 7:00-10:00
      expect(buckets['afternoon'], 180); // 13:00-16:00
      expect(buckets['evening'], 180); // 19:00-22:00
    });

    test('session crossing bucket boundary splits minutes correctly', () {
      final range = DateTimeRange(
        start: DateTime(2026, 3, 10, 0, 0),
        end: DateTime(2026, 3, 11, 0, 0),
      );

      // Session from 5:00 to 7:00 crosses night→morning boundary at 6:00
      final session = FakeSession(
        startTime: DateTime(2026, 3, 10, 5, 0),
        endTime: DateTime(2026, 3, 10, 7, 0),
        memberId: 'member-1',
      );

      final result = computeAnalyticsFromRows([session], range);
      final buckets = result.memberStats.first.timeOfDayBreakdown;

      expect(buckets['night'], 60); // 5:00-6:00
      expect(buckets['morning'], 60); // 6:00-7:00
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
      // Durations: 10m, 60m, 5m → sorted: 5, 10, 60 → median = 10m
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
      // Durations: 5m, 60m → median = 32m30s
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
      // Durations: 5m, 10m, 60m, 120m → median = (10 + 60) / 2 = 35m
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
      // Session starts before range and ends after; clamped to 24h.
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

  group('topCoFrontingPairs', () {
    test('pair counted once regardless of who is primary', () {
      final sessions = [
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 10),
          endTime: DateTime.utc(2026, 3, 1, 12),
          memberId: 'member-a',
          coFronterIds: ['member-b'],
        ),
      ];
      final range = DateTimeRange(
          start: DateTime.utc(2026, 3, 1), end: DateTime.utc(2026, 3, 2));
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs, hasLength(1));
      expect(result.topCoFrontingPairs.first.totalTime.inMinutes, 120);
    });

    test('alphabetical key ordering consistent regardless of primary', () {
      // Session A primary + B co, then B primary + A co — should accumulate to same pair
      final sessions = [
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 8),
          endTime: DateTime.utc(2026, 3, 1, 9),
          memberId: 'member-a',
          coFronterIds: ['member-b'],
        ),
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 10),
          endTime: DateTime.utc(2026, 3, 1, 11),
          memberId: 'member-b',
          coFronterIds: ['member-a'],
        ),
      ];
      final range = DateTimeRange(
          start: DateTime.utc(2026, 3, 1), end: DateTime.utc(2026, 3, 2));
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs, hasLength(1));
      expect(result.topCoFrontingPairs.first.totalTime.inMinutes, 120);
    });

    test('sorted by totalTime descending', () {
      final sessions = [
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 8),
          endTime: DateTime.utc(2026, 3, 1, 9),
          memberId: 'a',
          coFronterIds: ['b'], // 1h A+B
        ),
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 10),
          endTime: DateTime.utc(2026, 3, 1, 13),
          memberId: 'a',
          coFronterIds: ['c'], // 3h A+C
        ),
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 14),
          endTime: DateTime.utc(2026, 3, 1, 16),
          memberId: 'b',
          coFronterIds: ['c'], // 2h B+C
        ),
      ];
      final range = DateTimeRange(
          start: DateTime.utc(2026, 3, 1), end: DateTime.utc(2026, 3, 2));
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs.first.totalTime.inHours, 3); // A+C is top
    });

    test('no co-fronters returns empty list', () {
      final sessions = [
        FakeSession(
          startTime: DateTime.utc(2026, 3, 1, 10),
          endTime: DateTime.utc(2026, 3, 1, 11),
          memberId: 'a',
        ),
      ];
      final range = DateTimeRange(
          start: DateTime.utc(2026, 3, 1), end: DateTime.utc(2026, 3, 2));
      final result = computeAnalyticsFromRows(sessions, range);
      expect(result.topCoFrontingPairs, isEmpty);
    });
  });
}
