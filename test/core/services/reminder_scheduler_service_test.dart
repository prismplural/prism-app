import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/core/services/reminder_scheduler_service.dart';
import 'package:prism_plurality/domain/models/reminder.dart';

// ── Fake LocalNotificationService ─────────────────────────────────────────────

/// A [LocalNotificationService] subclass that captures scheduling/cancel calls
/// without touching the notification plugin. Safe to use in unit tests where
/// no platform channel is available.
class _FakeLocalNotificationService extends LocalNotificationService {
  final List<String> methodCalls = [];
  final List<(int, int)> cancelRangeCalls = []; // (base, count)
  final List<(int, TimeOfDay)> scheduleExactDailyCalls = []; // (id, time)
  final List<(int, int, TimeOfDay)> scheduleExactWeeklyCalls =
      []; // (id, weekday, time)
  final List<({int idBase, int intervalDays, TimeOfDay time})>
      scheduleExactIntervalCalls = [];
  final List<(int, String, String)> showImmediateCalls = []; // (id, title, body)

  @override
  Future<void> scheduleExactDaily({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required NotificationDetails details,
  }) async {
    methodCalls.add('scheduleExactDaily');
    scheduleExactDailyCalls.add((id, time));
  }

  @override
  Future<void> scheduleExactWeekly({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required int weekday,
    required NotificationDetails details,
  }) async {
    methodCalls.add('scheduleExactWeekly');
    scheduleExactWeeklyCalls.add((id, weekday, time));
  }

  @override
  Future<void> scheduleExactInterval({
    required int idBase,
    required String title,
    required String body,
    required TimeOfDay time,
    required int intervalDays,
    required NotificationDetails details,
    int? maxOccurrences,
  }) async {
    methodCalls.add('scheduleExactInterval');
    scheduleExactIntervalCalls
        .add((idBase: idBase, intervalDays: intervalDays, time: time));
  }

  @override
  Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
  }) async {
    methodCalls.add('showImmediate');
    showImmediateCalls.add((id, title, body));
  }

  @override
  Future<void> cancel(int id) async {
    methodCalls.add('cancel');
  }

  @override
  Future<void> cancelRange(int base, int count) async {
    methodCalls.add('cancelRange');
    cancelRangeCalls.add((base, count));
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Reminder _reminder({
  required String id,
  String name = 'Test',
  String message = 'msg',
  ReminderTrigger trigger = ReminderTrigger.scheduled,
  ReminderFrequency frequency = ReminderFrequency.daily,
  List<int>? weeklyDays,
  int? intervalDays,
  String? timeOfDay = '09:00',
  String? targetMemberId,
  bool isActive = true,
}) {
  final now = DateTime(2026, 1, 1);
  return Reminder(
    id: id,
    name: name,
    message: message,
    trigger: trigger,
    frequency: frequency,
    weeklyDays: weeklyDays,
    intervalDays: intervalDays,
    timeOfDay: timeOfDay,
    targetMemberId: targetMemberId,
    isActive: isActive,
    createdAt: now,
    modifiedAt: now,
  );
}

void main() {
  // ── scheduleReminder: daily routing ────────────────────────────────

  group('scheduleReminder — daily', () {
    test('routes to scheduleExactDaily exactly once', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(id: 'r1', frequency: ReminderFrequency.daily);

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        1,
      );
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactWeekly').length,
        0,
      );
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactInterval').length,
        0,
      );
    });

    test('schedules at the parsed reminder time', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r1',
        frequency: ReminderFrequency.daily,
        timeOfDay: '14:30',
      );

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      final (_, time) = fake.scheduleExactDailyCalls.first;
      expect(time.hour, 14);
      expect(time.minute, 30);
    });
  });

  // ── scheduleReminder: weekly routing ───────────────────────────────

  group('scheduleReminder — weekly', () {
    test('weeklyDays [1,3,5] → three scheduleExactWeekly calls', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [1, 3, 5],
      );

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactWeeklyCalls, hasLength(3));
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        0,
      );
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactInterval').length,
        0,
      );
    });

    test('weekly IDs are consecutive base..base+2', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-ids',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [1, 3, 5],
      );

      await service.scheduleReminder(reminder);

      final ids = fake.scheduleExactWeeklyCalls.map((c) => c.$1).toList();
      expect(ids, hasLength(3));
      expect(ids[1], ids[0] + 1);
      expect(ids[2], ids[0] + 2);
    });

    test('weekday values match order [1, 3, 5]', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-order',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [1, 3, 5],
      );

      await service.scheduleReminder(reminder);

      final weekdays =
          fake.scheduleExactWeeklyCalls.map((c) => c.$2).toList();
      expect(weekdays, [1, 3, 5]);
    });

    test('weeklyDays [] → zero scheduling calls', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-empty',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [],
      );

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });

    test('weeklyDays null → zero calls, no crash', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-null',
        frequency: ReminderFrequency.weekly,
        weeklyDays: null,
      );

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });

    test('weeklyDays [1, 1, 3] → dedup to 2 calls with weekdays [1, 3]',
        () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-dedup',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [1, 1, 3],
      );

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactWeeklyCalls, hasLength(2));
      final weekdays =
          fake.scheduleExactWeeklyCalls.map((c) => c.$2).toList();
      expect(weekdays, [1, 3]);
    });

    test('weeklyDays [-1, 7, 99] → zero calls (all invalid)', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-invalid',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [-1, 7, 99],
      );

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });

    test('weeklyDays [1, -1, 3] → 2 calls with weekdays [1, 3]', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-mixed',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [1, -1, 3],
      );

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactWeeklyCalls, hasLength(2));
      final weekdays =
          fake.scheduleExactWeeklyCalls.map((c) => c.$2).toList();
      expect(weekdays, [1, 3]);
    });

    test(
        'weekly with intervalDays=1 → weekly path wins (not daily)',
        () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-weekly-with-interval',
        frequency: ReminderFrequency.weekly,
        intervalDays: 1,
        weeklyDays: [2],
      );

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactWeekly').length,
        1,
      );
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        0,
      );
    });
  });

  // ── scheduleReminder: interval routing ─────────────────────────────

  group('scheduleReminder — interval', () {
    test('intervalDays=3 → exactly one scheduleExactInterval', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-interval',
        frequency: ReminderFrequency.interval,
        intervalDays: 3,
      );

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactIntervalCalls, hasLength(1));
      expect(fake.scheduleExactIntervalCalls.first.intervalDays, 3);
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        0,
      );
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactWeekly').length,
        0,
      );
    });
  });

  // ── Notification ID range bump ──────────────────────────────────────

  group('notification ID range', () {
    test('daily notification id is >= 20000', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(id: 'id-range-daily');

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      final id = fake.scheduleExactDailyCalls.first.$1;
      expect(id, greaterThanOrEqualTo(20000));
    });

    test('weekly notification ids are all >= 20000', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'id-range-weekly',
        frequency: ReminderFrequency.weekly,
        weeklyDays: [1, 2, 3],
      );

      await service.scheduleReminder(reminder);

      for (final (id, _, _) in fake.scheduleExactWeeklyCalls) {
        expect(id, greaterThanOrEqualTo(20000));
      }
    });

    test('interval notification id base is >= 20000', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'id-range-interval',
        frequency: ReminderFrequency.interval,
        intervalDays: 3,
      );

      await service.scheduleReminder(reminder);

      expect(fake.scheduleExactIntervalCalls, hasLength(1));
      expect(
        fake.scheduleExactIntervalCalls.first.idBase,
        greaterThanOrEqualTo(20000),
      );
    });
  });

  // ── cancelReminder ──────────────────────────────────────────────────

  group('cancelReminder', () {
    test('cancels a full range (>= 7 slots to cover weekly)', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);

      await service.cancelReminder('r-cancel');

      expect(fake.cancelRangeCalls, hasLength(1));
      final (_, count) = fake.cancelRangeCalls.first;
      // Must be at least 7 to cover all possible weekly slots.
      expect(count, greaterThanOrEqualTo(7));
    });
  });

  // ── Inactive / onFrontChange routing guards ────────────────────────

  group('scheduleReminder — guards', () {
    test('inactive reminder is skipped', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(id: 'r-inactive', isActive: false);

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });

    test('onFrontChange reminder does not call the notification plugin',
        () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      final reminder = _reminder(
        id: 'r-fc',
        trigger: ReminderTrigger.onFrontChange,
      );

      await service.scheduleReminder(reminder);

      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });
  });

  // ── Per-member firing filter (plan 06) ──────────────────────────────

  group('fireFrontChangeReminders — target filter', () {
    test('null target fires on any switch', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      await service.scheduleReminder(_reminder(
        id: 'r-any',
        trigger: ReminderTrigger.onFrontChange,
        // targetMemberId intentionally null.
      ));

      await service.fireFrontChangeReminders({'alex'});
      await service.fireFrontChangeReminders({'sam'});
      await service.fireFrontChangeReminders(const <String>{});

      expect(fake.showImmediateCalls, hasLength(3));
    });

    test('member target fires only when that member is fronting', () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      await service.scheduleReminder(_reminder(
        id: 'r-alex',
        trigger: ReminderTrigger.onFrontChange,
        targetMemberId: 'alex',
      ));

      await service.fireFrontChangeReminders({'sam'}); // not alex
      expect(fake.showImmediateCalls, isEmpty);

      await service.fireFrontChangeReminders({'alex'});
      expect(fake.showImmediateCalls, hasLength(1));

      await service.fireFrontChangeReminders({'alex', 'sam'}); // co-front
      expect(fake.showImmediateCalls, hasLength(2));
    });

    test('mix: null target always fires, targeted only when matching',
        () async {
      final fake = _FakeLocalNotificationService();
      final service = ReminderSchedulerService(fake);
      await service.scheduleReminder(_reminder(
        id: 'r-any',
        name: 'any',
        trigger: ReminderTrigger.onFrontChange,
      ));
      await service.scheduleReminder(_reminder(
        id: 'r-alex',
        name: 'alex',
        trigger: ReminderTrigger.onFrontChange,
        targetMemberId: 'alex',
      ));

      await service.fireFrontChangeReminders({'sam'});
      // Only the null-target reminder fires.
      expect(fake.showImmediateCalls, hasLength(1));
      expect(fake.showImmediateCalls.single.$2, 'any');

      fake.showImmediateCalls.clear();
      await service.fireFrontChangeReminders({'alex'});
      // Both fire.
      expect(fake.showImmediateCalls, hasLength(2));
    });
  });
}
