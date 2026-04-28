import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // ── nextWeekdayOccurrenceFrom ──────────────────────────────────────
  //
  // Regression: the picker emits 0=Sunday..6=Saturday but Dart's
  // DateTime.weekday is 1=Monday..7=Sunday. The pre-fix walk used a
  // synchronous `while (candidate.weekday != weekday)` loop, which never
  // terminated for `weekday == 0` and froze the UI isolate. These tests
  // pin the picker→Dart conversion and confirm the loop is bounded.

  group('nextWeekdayOccurrenceFrom', () {
    setUpAll(() {
      tzdata.initializeTimeZones();
    });

    // Anchor on a known weekday so each case has a deterministic expected
    // jump. 2026-04-20 is a Monday in UTC.
    final monday = tz.TZDateTime.utc(2026, 4, 20, 9);

    test('weekday=0 (picker Sunday) lands on Dart Sunday=7 within 7 days', () {
      final result = nextWeekdayOccurrenceFrom(monday, 0);
      expect(result.weekday, DateTime.sunday);
      // Mon → next Sun is 6 days away.
      expect(result.difference(monday).inDays, 6);
    });

    test('weekday=1..6 already match Dart weekdays', () {
      for (var w = 1; w <= 6; w++) {
        final result = nextWeekdayOccurrenceFrom(monday, w);
        expect(result.weekday, w, reason: 'weekday=$w');
      }
    });

    test('weekday=1 on a Monday returns the same day', () {
      final result = nextWeekdayOccurrenceFrom(monday, 1);
      expect(result, monday);
    });

    test('out-of-range weekday cannot lock the loop', () {
      // 99 will never match candidate.weekday (1..7). Pre-fix this hung.
      // Post-fix the bounded loop returns after ≤ 7 day-adds; the result
      // weekday is undefined for bad input — only the bound matters.
      final result = nextWeekdayOccurrenceFrom(monday, 99);
      expect(result.difference(monday).inDays, lessThanOrEqualTo(7));
    });

    test('weekday=0 returns within 100 ms (no infinite loop)', () {
      final sw = Stopwatch()..start();
      nextWeekdayOccurrenceFrom(monday, 0);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(100));
    });
  });


  // ── Occurrence count formula ───────────────────────────────────────

  group('scheduleExactInterval occurrence count', () {
    // Formula: n = ceil(30 / intervalDays).clamp(2, maxIntervalOccurrences)

    int occurrences(int intervalDays) =>
        (30 / intervalDays).ceil().clamp(2, LocalNotificationService.maxIntervalOccurrences);

    test('intervalDays=1 → 30 occurrences', () {
      // ceil(30/1) = 30, clamp(2,30) = 30
      expect(occurrences(1), 30);
    });

    test('intervalDays=2 → 15 occurrences', () {
      // ceil(30/2) = 15, clamp(2,30) = 15
      expect(occurrences(2), 15);
    });

    test('intervalDays=3 → 10 occurrences', () {
      // ceil(30/3) = 10, clamp(2,30) = 10
      expect(occurrences(3), 10);
    });

    test('intervalDays=7 → 5 occurrences', () {
      // ceil(30/7) = 5, clamp(2,30) = 5
      expect(occurrences(7), 5);
    });

    test('intervalDays=14 → 3 occurrences', () {
      // ceil(30/14) = 3, clamp(2,30) = 3
      expect(occurrences(14), 3);
    });

    test('intervalDays=30 → 2 occurrences', () {
      // ceil(30/30) = 1, clamp(2,30) = 2 (minimum guaranteed)
      expect(occurrences(30), 2);
    });

    test('intervalDays=90 → 2 occurrences (minimum clamp)', () {
      // ceil(30/90) = 1, clamp(2,30) = 2
      expect(occurrences(90), 2);
    });

    test('any interval produces at least 2 occurrences', () {
      for (final d in [1, 2, 3, 7, 14, 30, 60, 365]) {
        expect(occurrences(d), greaterThanOrEqualTo(2));
      }
    });

    test('no interval exceeds maxIntervalOccurrences', () {
      for (final d in [1, 2, 3, 7, 14]) {
        expect(
          occurrences(d),
          lessThanOrEqualTo(LocalNotificationService.maxIntervalOccurrences),
        );
      }
    });
  });

  // ── maxIntervalOccurrences constant ──────────────────────────────────

  test('maxIntervalOccurrences is 30', () {
    expect(LocalNotificationService.maxIntervalOccurrences, 30);
  });
}
