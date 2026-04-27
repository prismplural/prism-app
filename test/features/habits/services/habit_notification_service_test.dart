import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/services/habit_notification_service.dart';

// ── Fake LocalNotificationService ─────────────────────────────────────────────

/// A [LocalNotificationService] subclass that captures scheduling/cancel calls
/// without touching the notification plugin. Safe to use in unit tests where
/// no platform channel is available.
class _FakeLocalNotificationService extends LocalNotificationService {
  final List<String> methodCalls = [];
  final List<(int, int)> cancelRangeCalls = []; // (base, count)
  final List<(int, TimeOfDay)> scheduleExactDailyCalls = []; // (id, time)
  final List<(int, int, TimeOfDay)> scheduleExactWeeklyCalls = []; // (id, weekday, time)
  final List<({int idBase, int intervalDays, int n})> scheduleExactIntervalCalls = [];

  void reset() {
    methodCalls.clear();
    cancelRangeCalls.clear();
    scheduleExactDailyCalls.clear();
    scheduleExactWeeklyCalls.clear();
    scheduleExactIntervalCalls.clear();
  }

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
    final n = maxOccurrences ??
        (30 / intervalDays)
            .ceil()
            .clamp(2, LocalNotificationService.maxIntervalOccurrences);
    methodCalls.add('scheduleExactInterval');
    scheduleExactIntervalCalls.add((idBase: idBase, intervalDays: intervalDays, n: n));
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

Habit _habit({
  String id = 'habit-1',
  String name = 'Morning Run',
  HabitFrequency frequency = HabitFrequency.daily,
  List<int>? weeklyDays,
  int? intervalDays,
  bool isActive = true,
  bool notificationsEnabled = true,
  String? reminderTime = '09:00',
}) {
  final now = DateTime(2026, 1, 1);
  return Habit(
    id: id,
    name: name,
    frequency: frequency,
    weeklyDays: weeklyDays,
    intervalDays: intervalDays,
    isActive: isActive,
    notificationsEnabled: notificationsEnabled,
    reminderTime: reminderTime,
    createdAt: now,
    modifiedAt: now,
  );
}

/// Computes the expected base notification ID for a given habit ID.
/// Mirrors the private _baseId logic in HabitNotificationService.
int _expectedBaseId(String id) => 3000000 + (id.hashCode.abs() % 100000);

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── scheduleForHabit: daily routing ─────────────────────────────────

  group('scheduleForHabit — daily', () {
    test('calls cancelRange then scheduleExactDaily', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily, reminderTime: '09:00');

      await service.scheduleForHabit(habit);

      // cancelRange comes BEFORE scheduleExactDaily
      expect(fake.methodCalls, containsAllInOrder(['cancelRange', 'scheduleExactDaily']));
    });

    test('schedules at the parsed reminder time', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily, reminderTime: '14:30');

      await service.scheduleForHabit(habit);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      final (_, time) = fake.scheduleExactDailyCalls.first;
      expect(time.hour, 14);
      expect(time.minute, 30);
    });

    test('defaults to 9:00 AM when reminderTime is null', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily, reminderTime: null);

      await service.scheduleForHabit(habit);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      final (_, time) = fake.scheduleExactDailyCalls.first;
      expect(time.hour, 9);
      expect(time.minute, 0);
    });

    test('cancelRange uses maxIntervalOccurrences as count', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily);

      await service.scheduleForHabit(habit);

      // Expect two cancelRange calls: one from the isActive guard, one from
      // the explicit cancel before rescheduling.
      expect(fake.cancelRangeCalls, isNotEmpty);
      for (final (_, count) in fake.cancelRangeCalls) {
        expect(count, LocalNotificationService.maxIntervalOccurrences);
      }
    });
  });

  // ── scheduleForHabit: weekly routing ────────────────────────────────

  group('scheduleForHabit — weekly', () {
    test('calls scheduleExactWeekly once per weekday', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      // M, W, F = weekdays 1, 3, 5
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        weeklyDays: [1, 3, 5],
      );

      await service.scheduleForHabit(habit);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactWeekly').length,
        3,
      );
    });

    test('passes correct weekday values', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        weeklyDays: [2, 4], // T, Th
      );

      await service.scheduleForHabit(habit);

      final weekdays = fake.scheduleExactWeeklyCalls.map((c) => c.$2).toList();
      expect(weekdays, containsAll([2, 4]));
    });

    test('skips scheduling when weeklyDays is empty', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        weeklyDays: [],
      );

      await service.scheduleForHabit(habit);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactWeekly').length,
        0,
      );
    });

    test('weekly IDs are base + index', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        id: 'my-habit',
        frequency: HabitFrequency.weekly,
        weeklyDays: [1, 2, 3],
      );

      await service.scheduleForHabit(habit);

      final base = _expectedBaseId('my-habit');
      final ids = fake.scheduleExactWeeklyCalls.map((c) => c.$1).toList();
      expect(ids, [base, base + 1, base + 2]);
    });
  });

  // ── scheduleForHabit: interval routing ──────────────────────────────

  group('scheduleForHabit — interval', () {
    test('uses scheduleExactInterval for intervalDays > 1', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.interval,
        intervalDays: 3,
      );

      await service.scheduleForHabit(habit);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactInterval').length,
        1,
      );
    });

    test('intervalDays=3 → 10 occurrences (ceil(30/3))', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.interval,
        intervalDays: 3,
      );

      await service.scheduleForHabit(habit);

      expect(fake.scheduleExactIntervalCalls, hasLength(1));
      expect(fake.scheduleExactIntervalCalls.first.n, 10);
    });

    test('intervalDays=1 routes to scheduleExactDaily', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.interval,
        intervalDays: 1,
      );

      await service.scheduleForHabit(habit);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        1,
      );
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactInterval').length,
        0,
      );
    });
  });

  // ── scheduleForHabit: inactive / disabled guard ──────────────────────

  group('scheduleForHabit — guard cases', () {
    test('inactive habit calls cancelForHabit and returns without scheduling', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(isActive: false, notificationsEnabled: true);

      await service.scheduleForHabit(habit);

      expect(
        fake.methodCalls.where((m) => m == 'cancelRange').length,
        1, // only the guard cancel, no reschedule cancel
      );
      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });

    test('notificationsDisabled habit calls cancelForHabit and returns', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(isActive: true, notificationsEnabled: false);

      await service.scheduleForHabit(habit);

      expect(
        fake.methodCalls.where((m) => m.startsWith('scheduleExact')).length,
        0,
      );
    });
  });

  // ── cancelForHabit ────────────────────────────────────────────────────

  group('cancelForHabit', () {
    test('calls cancelRange with correct base and maxIntervalOccurrences count', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      const habitId = 'habit-abc';

      await service.cancelForHabit(habitId);

      expect(fake.cancelRangeCalls, hasLength(1));
      final (base, count) = fake.cancelRangeCalls.first;
      expect(base, _expectedBaseId(habitId));
      expect(count, LocalNotificationService.maxIntervalOccurrences);
    });
  });

  // ── rescheduleAll ─────────────────────────────────────────────────────

  group('rescheduleAll', () {
    test('calls scheduleForHabit for each habit', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habits = [
        _habit(id: 'h1', frequency: HabitFrequency.daily),
        _habit(id: 'h2', frequency: HabitFrequency.daily),
      ];

      await service.rescheduleAll(habits);

      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        2,
      );
    });

    test('skips inactive habits in rescheduleAll', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habits = [
        _habit(id: 'h1', isActive: true, frequency: HabitFrequency.daily),
        _habit(id: 'h2', isActive: false, frequency: HabitFrequency.daily),
      ];

      await service.rescheduleAll(habits);

      // Only one call to scheduleExactDaily (for the active habit).
      expect(
        fake.methodCalls.where((m) => m == 'scheduleExactDaily').length,
        1,
      );
    });
  });

  // ── HabitNotifier.toggleActive ─────────────────────────────────────────

  group('HabitNotifier.toggleActive — notification cancel', () {
    late _FakeLocalNotificationService fakeLocal;
    late HabitNotificationService fakeHabitService;

    setUp(() {
      fakeLocal = _FakeLocalNotificationService();
      fakeHabitService = HabitNotificationService(fakeLocal);
    });

    test('deactivating an active habit calls cancelForHabit', () async {
      const habitId = 'deactivate-me';
      final habit = _habit(id: habitId, isActive: true);

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(
            _FakeHabitRepository(habits: [habit]),
          ),
          habitNotificationServiceProvider.overrideWithValue(fakeHabitService),
          currentDateProvider.overrideWith((_) => DateTime(2026, 1, 1)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(habitNotifierProvider.notifier).toggleActive(habitId);

      // cancelForHabit → cancelRange called once
      expect(
        fakeLocal.cancelRangeCalls.any((c) => c.$1 == _expectedBaseId(habitId)),
        isTrue,
      );
    });

    test('reactivating an inactive habit does NOT call cancelForHabit', () async {
      const habitId = 'reactivate-me';
      final habit = _habit(id: habitId, isActive: false);

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(
            _FakeHabitRepository(habits: [habit]),
          ),
          habitNotificationServiceProvider.overrideWithValue(fakeHabitService),
          currentDateProvider.overrideWith((_) => DateTime(2026, 1, 1)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(habitNotifierProvider.notifier).toggleActive(habitId);

      // No cancel calls — reactivation is handled by the listener
      expect(fakeLocal.cancelRangeCalls, isEmpty);
    });
  });
}

// ── Fake repository ────────────────────────────────────────────────────────────

class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({required List<Habit> habits})
      : _habits = List.unmodifiable(habits);

  final List<Habit> _habits;
  final List<Habit> _updated = [];

  @override
  Future<Habit?> getHabitById(String id) async {
    for (final h in _habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  Future<void> updateHabit(Habit habit) async => _updated.add(habit);

  @override
  Future<void> createHabit(Habit habit) async {}

  @override
  Future<void> deleteHabit(String id) async {}

  @override
  Future<List<Habit>> getAllHabits() async => _habits;

  @override
  Future<List<HabitCompletion>> getAllCompletions() async => [];

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async => [];

  @override
  Future<void> createCompletion(HabitCompletion completion) async {}

  @override
  Future<void> deleteCompletion(String id) async {}

  @override
  Stream<List<Habit>> watchActiveHabits() =>
      Stream.value(_habits.where((h) => h.isActive).toList());

  @override
  Stream<List<Habit>> watchAllHabits() => Stream.value(_habits);

  @override
  Stream<Habit?> watchHabitById(String id) {
    final match = _habits.cast<Habit?>().firstWhere(
      (h) => h?.id == id,
      orElse: () => null,
    );
    return Stream.value(match);
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value([]);

  @override
  Stream<List<HabitCompletion>> watchAllCompletions() => Stream.value([]);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) =>
      Stream.value([]);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  ) => Stream.value([]);
}
