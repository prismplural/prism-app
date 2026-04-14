import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';

void main() {
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
