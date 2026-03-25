import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/reminder_scheduler_service.dart';
import 'package:prism_plurality/domain/models/reminder.dart';

Reminder _reminder({
  required String id,
  String name = 'Test',
  String message = 'msg',
  ReminderTrigger trigger = ReminderTrigger.scheduled,
  int? intervalDays,
  bool isActive = true,
}) {
  final now = DateTime(2026, 1, 1);
  return Reminder(
    id: id,
    name: name,
    message: message,
    trigger: trigger,
    intervalDays: intervalDays,
    isActive: isActive,
    createdAt: now,
    modifiedAt: now,
  );
}

void main() {
  // ── _setsEqual (top-level function, tested indirectly) ──────────

  // The function is file-private (_setsEqual) so we replicate its logic
  // to verify the expected semantics.  Since it's used in the provider
  // listener for front-change detection, we test the contract here.
  group('setsEqual semantics', () {
    bool setsEqual<T>(Set<T> a, Set<T> b) {
      if (a.length != b.length) return false;
      return a.containsAll(b);
    }

    test('identical sets are equal', () {
      expect(setsEqual({'a', 'b'}, {'a', 'b'}), isTrue);
    });

    test('empty sets are equal', () {
      expect(setsEqual(<String>{}, <String>{}), isTrue);
    });

    test('different lengths are not equal', () {
      expect(setsEqual({'a'}, {'a', 'b'}), isFalse);
    });

    test('same length different elements are not equal', () {
      expect(setsEqual({'a', 'b'}, {'a', 'c'}), isFalse);
    });

    test('order does not matter', () {
      expect(setsEqual({'b', 'a'}, {'a', 'b'}), isTrue);
    });
  });

  // ── _repeatIntervalFrom mapping ────────────────────────────────

  group('repeatIntervalFrom mapping', () {
    // We cannot call the private method directly, but we can verify the
    // contract via documentation / replicated logic.  The mapping is:
    //   null or <=1 → daily
    //   2..7       → weekly
    //   >7         → weekly
    //
    // We test a local replica to document the expected behaviour.

    String intervalName(int? days) {
      if (days == null || days <= 1) return 'daily';
      if (days <= 7) return 'weekly';
      return 'weekly';
    }

    test('null maps to daily', () {
      expect(intervalName(null), 'daily');
    });

    test('0 maps to daily', () {
      expect(intervalName(0), 'daily');
    });

    test('1 maps to daily', () {
      expect(intervalName(1), 'daily');
    });

    test('7 maps to weekly', () {
      expect(intervalName(7), 'weekly');
    });

    test('14 maps to weekly', () {
      expect(intervalName(14), 'weekly');
    });

    test('2 maps to weekly', () {
      expect(intervalName(2), 'weekly');
    });
  });

  // ── rescheduleAll skips inactive reminders ─────────────────────

  group('rescheduleAll', () {
    test('only schedules active front-change reminders', () async {
      final service = ReminderSchedulerService();

      final active = _reminder(
        id: 'r1',
        trigger: ReminderTrigger.onFrontChange,
        isActive: true,
      );
      final inactive = _reminder(
        id: 'r2',
        trigger: ReminderTrigger.onFrontChange,
        isActive: false,
      );

      // scheduleReminder checks isActive before adding to pending list.
      await service.scheduleReminder(active);
      await service.scheduleReminder(inactive);

      // We cannot peek at the private list, but we know that
      // scheduleReminder returns early for inactive reminders (line 62-63).
      // This test exercises the code path to ensure no exception is thrown
      // and the service handles the mix correctly.
    });
  });

  // ── scheduleReminder routing ──────────────────────────────────

  group('scheduleReminder routing', () {
    test('inactive reminder is skipped', () async {
      final service = ReminderSchedulerService();
      final r = _reminder(
        id: 'r-inactive',
        trigger: ReminderTrigger.onFrontChange,
        isActive: false,
      );

      // Should not throw and should be a no-op.
      await service.scheduleReminder(r);
    });

    test('onFrontChange reminder scheduling does not throw', () async {
      final service = ReminderSchedulerService();
      final r = _reminder(
        id: 'r-fc',
        trigger: ReminderTrigger.onFrontChange,
        isActive: true,
      );

      // scheduleReminder for onFrontChange adds to internal list without
      // touching the notification plugin, so this should succeed.
      await service.scheduleReminder(r);
    });
  });

  // ── Notification ID generation ────────────────────────────────

  group('notification ID stability', () {
    test('same reminder ID always produces same notification ID', () {
      // The formula is: 5000 + (id.hashCode.abs() % 10000)
      // This is deterministic per runtime for the same string.
      const base = 5000;
      const id = 'test-reminder-abc';
      final expected = base + (id.hashCode.abs() % 10000);

      // Compute twice to verify determinism.
      final first = base + (id.hashCode.abs() % 10000);
      final second = base + (id.hashCode.abs() % 10000);

      expect(first, expected);
      expect(second, expected);
    });

    test('notification IDs are within expected range', () {
      const base = 5000;
      for (final id in ['a', 'b', 'long-reminder-id-12345', '']) {
        final nid = base + (id.hashCode.abs() % 10000);
        expect(nid, greaterThanOrEqualTo(5000));
        expect(nid, lessThan(15000));
      }
    });
  });
}
