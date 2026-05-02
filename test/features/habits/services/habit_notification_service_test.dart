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
  final List<({int id, TimeOfDay time, DateTime? notBefore})>
      scheduleExactDailyCalls = [];
  final List<({int id, int weekday, TimeOfDay time, DateTime? notBefore})>
      scheduleExactWeeklyCalls = [];
  final List<({int idBase, int intervalDays, int n, DateTime? notBefore})>
      scheduleExactIntervalCalls = [];

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
    DateTime? notBefore,
  }) async {
    methodCalls.add('scheduleExactDaily');
    scheduleExactDailyCalls.add((id: id, time: time, notBefore: notBefore));
  }

  @override
  Future<void> scheduleExactWeekly({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required int weekday,
    required NotificationDetails details,
    DateTime? notBefore,
  }) async {
    methodCalls.add('scheduleExactWeekly');
    scheduleExactWeeklyCalls
        .add((id: id, weekday: weekday, time: time, notBefore: notBefore));
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
    DateTime? notBefore,
  }) async {
    final n = maxOccurrences ??
        (30 / intervalDays)
            .ceil()
            .clamp(2, LocalNotificationService.maxIntervalOccurrences);
    methodCalls.add('scheduleExactInterval');
    scheduleExactIntervalCalls.add(
      (idBase: idBase, intervalDays: intervalDays, n: n, notBefore: notBefore),
    );
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
      final call = fake.scheduleExactDailyCalls.first;
      expect(call.time.hour, 14);
      expect(call.time.minute, 30);
    });

    test('defaults to 9:00 AM when reminderTime is null', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily, reminderTime: null);

      await service.scheduleForHabit(habit);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      final call = fake.scheduleExactDailyCalls.first;
      expect(call.time.hour, 9);
      expect(call.time.minute, 0);
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

      final weekdays = fake.scheduleExactWeeklyCalls.map((c) => c.weekday).toList();
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
      final ids = fake.scheduleExactWeeklyCalls.map((c) => c.id).toList();
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

  // ── skipCurrentPeriod ───────────────────────────────────────────────

  group('scheduleForHabit — skipCurrentPeriod', () {
    test('daily passes notBefore=tomorrow', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily, reminderTime: '09:00');
      final now = DateTime(2026, 5, 1, 14, 0); // Friday

      await service.scheduleForHabit(habit, skipCurrentPeriod: true, now: now);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      expect(fake.scheduleExactDailyCalls.first.notBefore, DateTime(2026, 5, 2));
    });

    test('daily without skip passes notBefore=null', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(frequency: HabitFrequency.daily);

      await service.scheduleForHabit(habit, now: DateTime(2026, 5, 1));

      expect(fake.scheduleExactDailyCalls.first.notBefore, isNull);
    });

    test('weekly only sets notBefore on the slot matching today', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      // 2026-05-01 is a Friday — Dart weekday 5, weekly index 5 (Fri).
      // Habit configured Mon (1), Wed (3), Fri (5).
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        weeklyDays: [1, 3, 5],
      );
      final now = DateTime(2026, 5, 1, 8, 0);

      await service.scheduleForHabit(habit, skipCurrentPeriod: true, now: now);

      expect(fake.scheduleExactWeeklyCalls, hasLength(3));
      final friCall = fake.scheduleExactWeeklyCalls.firstWhere((c) => c.weekday == 5);
      final monCall = fake.scheduleExactWeeklyCalls.firstWhere((c) => c.weekday == 1);
      final wedCall = fake.scheduleExactWeeklyCalls.firstWhere((c) => c.weekday == 3);
      expect(friCall.notBefore, DateTime(2026, 5, 2));
      expect(monCall.notBefore, isNull);
      expect(wedCall.notBefore, isNull);
    });

    test('weekly when today is not a target → no slot gets notBefore', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      // Friday 2026-05-01, habit only Mon/Wed.
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        weeklyDays: [1, 3],
      );
      final now = DateTime(2026, 5, 1);

      await service.scheduleForHabit(habit, skipCurrentPeriod: true, now: now);

      expect(
        fake.scheduleExactWeeklyCalls.every((c) => c.notBefore == null),
        isTrue,
      );
    });

    test('interval (>1 day) passes notBefore = today + intervalDays', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.interval,
        intervalDays: 3,
      );
      final now = DateTime(2026, 5, 1, 12, 0);

      await service.scheduleForHabit(habit, skipCurrentPeriod: true, now: now);

      expect(fake.scheduleExactIntervalCalls, hasLength(1));
      expect(
        fake.scheduleExactIntervalCalls.first.notBefore,
        DateTime(2026, 5, 4),
      );
    });

    test('interval=1 routes to daily with notBefore=tomorrow', () async {
      final fake = _FakeLocalNotificationService();
      final service = HabitNotificationService(fake);
      final habit = _habit(
        frequency: HabitFrequency.interval,
        intervalDays: 1,
      );
      final now = DateTime(2026, 5, 1, 12, 0);

      await service.scheduleForHabit(habit, skipCurrentPeriod: true, now: now);

      expect(fake.scheduleExactDailyCalls, hasLength(1));
      expect(fake.scheduleExactDailyCalls.first.notBefore, DateTime(2026, 5, 2));
    });
  });

  // ── completeHabit cancels today's reminder ──────────────────────────

  group('HabitNotifier.completeHabit', () {
    test('reschedules with skipCurrentPeriod=true after writing completion',
        () async {
      const habitId = 'med';
      final habit = _habit(
        id: habitId,
        frequency: HabitFrequency.daily,
        reminderTime: '20:00',
      );
      final fakeLocal = _FakeLocalNotificationService();
      final notifService = HabitNotificationService(fakeLocal);
      final repo = _FakeHabitRepository(habits: [habit]);

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWithValue(notifService),
          currentDateProvider.overrideWith((_) => DateTime(2026, 5, 1)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(habitNotifierProvider.notifier).completeHabit(
            habitId: habitId,
            completedAt: DateTime(2026, 5, 1, 19, 0),
          );

      // Should have at least one daily schedule with a non-null notBefore
      // (the post-completion reschedule).
      final hasSkippedDaily = fakeLocal.scheduleExactDailyCalls
          .any((c) => c.notBefore != null);
      expect(hasSkippedDaily, isTrue);
    });
  });
}

// ── Fake repository ────────────────────────────────────────────────────────────

class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({required List<Habit> habits})
      : _habits = List.of(habits);

  final List<Habit> _habits;
  final List<HabitCompletion> _completions = [];
  final List<Habit> updated = [];

  @override
  Future<Habit?> getHabitById(String id) async {
    for (final h in _habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  Future<void> updateHabit(Habit habit) async {
    updated.add(habit);
    final i = _habits.indexWhere((h) => h.id == habit.id);
    if (i >= 0) _habits[i] = habit;
  }

  @override
  Future<void> createHabit(Habit habit) async {}

  @override
  Future<void> deleteHabit(String id) async {}

  @override
  Future<List<Habit>> getAllHabits() async => _habits;

  @override
  Future<List<HabitCompletion>> getAllCompletions() async => _completions;

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async => _completions.where((c) => c.habitId == habitId).toList();

  @override
  Future<void> createCompletion(HabitCompletion completion) async {
    _completions.add(completion);
  }

  @override
  Future<void> deleteCompletion(String id) async {
    _completions.removeWhere((c) => c.id == id);
  }

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
