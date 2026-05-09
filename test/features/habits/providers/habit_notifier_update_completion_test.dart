import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/local_notification_service.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/services/habit_notification_service.dart';

// ── Mutable fake repository ───────────────────────────────────────────────────

class _MutableFakeHabitRepository implements HabitRepository {
  _MutableFakeHabitRepository({
    required Habit habit,
    required List<HabitCompletion> completions,
  }) : _habit = habit,
       _completions = List.of(completions);

  Habit _habit;
  final List<HabitCompletion> _completions;

  // Track updateHabit calls so tests can inspect the updated habit.
  final List<Habit> updateHabitCalls = [];
  final List<Map<String, dynamic>> updateHabitFieldsCalls = [];
  // Allow override to simulate tombstoned completions.
  int updateCompletionFieldsResult = 1;
  int updateHabitFieldsResult = 1;
  int deleteCompletionResult = 1;
  bool getHabitByIdReturnsNull = false;

  @override
  Future<int> createCompletion(HabitCompletion completion) async {
    if (getHabitByIdReturnsNull) return 0;
    _completions.add(completion);
    return 1;
  }

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<int> deleteCompletion(String id) async {
    if (deleteCompletionResult == 0) return 0;
    final before = _completions.length;
    _completions.removeWhere((c) => c.id == id);
    return _completions.length == before ? 0 : 1;
  }

  @override
  Future<void> deleteHabit(String id) async => throw UnimplementedError();

  @override
  Future<List<HabitCompletion>> getAllCompletions() async =>
      List.unmodifiable(_completions);

  @override
  Future<List<Habit>> getAllHabits() async => [_habit];

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async {
    return _completions.where((c) {
      if (c.habitId != habitId) return false;
      return since == null || !c.completedAt.isBefore(since);
    }).toList();
  }

  @override
  Future<Habit?> getHabitById(String id) async =>
      !getHabitByIdReturnsNull && _habit.id == id ? _habit : null;

  @override
  Future<void> updateHabit(Habit habit) async {
    updateHabitCalls.add(habit);
    _habit = habit;
  }

  @override
  Future<int> updateHabitFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    if (updateHabitFieldsResult == 0) return 0;
    if (_habit.id != id) return 0;
    updateHabitFieldsCalls.add(Map<String, dynamic>.from(changedFields));
    _habit = _applyHabitPatch(_habit, changedFields);
    return 1;
  }

  @override
  Future<int> updateCompletionFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    if (updateCompletionFieldsResult == 0) return 0;
    final idx = _completions.indexWhere((c) => c.id == id);
    if (idx == -1) return 0;
    // Apply the patch to the in-memory completion for streak recalculation.
    final existing = _completions[idx];
    final completedAt = changedFields.containsKey('completed_at')
        ? DateTime.parse(changedFields['completed_at'] as String)
        : existing.completedAt;
    _completions[idx] = existing.copyWith(completedAt: completedAt);
    return 1;
  }

  @override
  Future<HabitCompletion?> getCompletionById(String id) async =>
      _completions.where((c) => c.id == id).firstOrNull;

  @override
  Stream<List<HabitCompletion>> watchAllCompletions() =>
      Stream.value(List.unmodifiable(_completions));

  @override
  Stream<List<Habit>> watchAllHabits() => Stream.value([_habit]);

  @override
  Stream<List<Habit>> watchActiveHabits() =>
      Stream.value([if (_habit.isActive) _habit]);

  @override
  Stream<Habit?> watchHabitById(String id) =>
      Stream.value(_habit.id == id ? _habit : null);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return Stream.value(
      _completions.where((c) {
        return !c.completedAt.isBefore(start) && c.completedAt.isBefore(end);
      }).toList(),
    );
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  ) {
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));
    return Stream.value(
      _completions.where((c) {
        return !c.completedAt.isBefore(rangeStart) &&
            c.completedAt.isBefore(rangeEnd);
      }).toList(),
    );
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value(_completions.where((c) => c.habitId == habitId).toList());
}

Habit _applyHabitPatch(Habit habit, Map<String, dynamic> fields) {
  return habit.copyWith(
    name: fields.containsKey('name') ? fields['name'] as String : habit.name,
    description: fields.containsKey('description')
        ? fields['description'] as String?
        : habit.description,
    icon: fields.containsKey('icon') ? fields['icon'] as String? : habit.icon,
    colorHex: fields.containsKey('color_hex')
        ? fields['color_hex'] as String?
        : habit.colorHex,
    isActive: fields.containsKey('is_active')
        ? fields['is_active'] as bool
        : habit.isActive,
    modifiedAt: fields.containsKey('modified_at')
        ? DateTime.parse(fields['modified_at'] as String)
        : habit.modifiedAt,
    currentStreak: fields.containsKey('current_streak')
        ? fields['current_streak'] as int
        : habit.currentStreak,
    bestStreak: fields.containsKey('best_streak')
        ? fields['best_streak'] as int
        : habit.bestStreak,
    totalCompletions: fields.containsKey('total_completions')
        ? fields['total_completions'] as int
        : habit.totalCompletions,
  );
}

// ── Spy notification service ──────────────────────────────────────────────────

class _SpyHabitNotificationService extends HabitNotificationService {
  _SpyHabitNotificationService() : super(_FakeLocalService());

  final List<({Habit habit, bool skipCurrentPeriod})> scheduleForHabitCalls =
      [];

  @override
  Future<void> scheduleForHabit(
    Habit habit, {
    bool skipCurrentPeriod = false,
    DateTime? now,
  }) async {
    scheduleForHabitCalls.add((
      habit: habit,
      skipCurrentPeriod: skipCurrentPeriod,
    ));
  }

  @override
  Future<void> cancelForHabit(String id) async {}
}

/// Minimal LocalNotificationService that the spy HabitNotificationService
/// constructor requires but never invokes (spy overrides scheduleForHabit
/// directly, so none of these are reached).
class _FakeLocalService extends LocalNotificationService {}

// ── Helpers ───────────────────────────────────────────────────────────────────

DateTime _daysAgo(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
}

HabitCompletion _completion({
  required String id,
  required String habitId,
  required DateTime completedAt,
}) {
  final now = DateTime.now();
  return HabitCompletion(
    id: id,
    habitId: habitId,
    completedAt: completedAt,
    createdAt: now,
    modifiedAt: now,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('HabitNotifier daily streak calculation', () {
    test(
      'counts consecutive local days across DST spring-forward boundaries',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(habitNotifierProvider.notifier);
        final completions = [
          _completion(
            id: 'c1',
            habitId: 'h1',
            completedAt: DateTime(2026, 3, 7, 9),
          ),
          _completion(
            id: 'c2',
            habitId: 'h1',
            completedAt: DateTime(2026, 3, 8, 9),
          ),
          _completion(
            id: 'c3',
            habitId: 'h1',
            completedAt: DateTime(2026, 3, 9, 9),
          ),
        ];

        expect(
          notifier.calculateDailyStreakForTest(
            completions,
            DateTime(2026, 3, 9, 12),
          ),
          3,
        );
      },
    );
  });

  group('HabitNotifier.updateCompletion', () {
    test(
      'moves daily completion across day boundary, currentStreak updates',
      () async {
        final today = _daysAgo(0);
        final habit = Habit(
          id: 'h1',
          name: 'Exercise',
          createdAt: _daysAgo(10),
          modifiedAt: _daysAgo(10),
          frequency: HabitFrequency.daily,
        );

        // Days 1-3 ago + today → streak should be 4
        final completions = [
          _completion(id: 'c1', habitId: 'h1', completedAt: _daysAgo(3)),
          _completion(id: 'c2', habitId: 'h1', completedAt: _daysAgo(2)),
          _completion(id: 'c3', habitId: 'h1', completedAt: _daysAgo(1)),
          _completion(id: 'c4', habitId: 'h1', completedAt: today),
        ];

        final repo = _MutableFakeHabitRepository(
          habit: habit,
          completions: completions,
        );
        final spy = _SpyHabitNotificationService();

        final container = ProviderContainer(
          overrides: [
            habitRepositoryProvider.overrideWithValue(repo),
            habitNotificationServiceProvider.overrideWith((ref) => spy),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(habitNotifierProvider.notifier);

        // Move c3 (yesterday) to 4 days ago — breaks the streak from today back
        await notifier.updateCompletion(
          completionId: completions[2].id,
          habitId: 'h1',
          changedFields: {
            'completed_at': _daysAgo(4).toUtc().toIso8601String(),
          },
        );

        // After moving c3 to day-4, completions are: day-4, day-3, day-2 (gap at day-1), today
        // Current streak (today-backwards): today only → 1
        expect(repo.updateHabitCalls, isEmpty);
        expect(repo.updateHabitFieldsCalls, hasLength(1));
        final updatedHabit = await repo.getHabitById('h1');
        expect(updatedHabit!.currentStreak, 1);
      },
    );

    test('notes-only edit does not change currentStreak', () async {
      final today = _daysAgo(0);
      final habit = Habit(
        id: 'h1',
        name: 'Read',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(10),
        frequency: HabitFrequency.daily,
        currentStreak: 3,
        bestStreak: 5,
      );

      final completions = [
        _completion(id: 'c1', habitId: 'h1', completedAt: _daysAgo(2)),
        _completion(id: 'c2', habitId: 'h1', completedAt: _daysAgo(1)),
        _completion(id: 'c3', habitId: 'h1', completedAt: today),
      ];

      final repo = _MutableFakeHabitRepository(
        habit: habit,
        completions: completions,
      );
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      // Notes-only edit: completedAt unchanged
      await notifier.updateCompletion(
        completionId: completions[2].id,
        habitId: 'h1',
        changedFields: {'notes': 'Updated notes'},
      );

      // Streak fields are unchanged (currentStreak=3 == 3, bestStreak=5 == 5),
      // so no habit stat patch is needed.
      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, isEmpty);
      // The habit in the repo still has the original streak values.
      final currentHabit = await repo.getHabitById('h1');
      expect(currentHabit!.currentStreak, 3);
      expect(currentHabit.bestStreak, 5);
    });

    test(
      'historical-gap test: filling a 30-day past streak updates bestStreak',
      () async {
        // Last month: create completions on days 30-26 ago (5 days = potential bestStreak 5)
        // But the habit's stored bestStreak is only 3 (ratchet missed it).
        // We add a completion that fills into that 5-day run.
        // After updateCompletion, bestStreak should be >= 5.
        final now = DateTime.now();
        final lastMonth = DateTime(now.year, now.month - 1, 1);

        final habit = Habit(
          id: 'h1',
          name: 'Journal',
          createdAt: lastMonth.subtract(const Duration(days: 5)),
          modifiedAt: lastMonth,
          frequency: HabitFrequency.daily,
          bestStreak: 3, // stale/wrong ratchet value
          currentStreak: 1,
        );

        // 5-day run in the past (days 1-5 of last month)
        final day1 = DateTime(lastMonth.year, lastMonth.month, 1);
        final day2 = DateTime(lastMonth.year, lastMonth.month, 2);
        final day3 = DateTime(lastMonth.year, lastMonth.month, 3);
        final day4 = DateTime(lastMonth.year, lastMonth.month, 4);
        // day5 is MISSING → gap. We'll fill it via updateCompletion.
        final today = DateTime(now.year, now.month, now.day);

        final existingCompletions = [
          _completion(id: 'c1', habitId: 'h1', completedAt: day1),
          _completion(id: 'c2', habitId: 'h1', completedAt: day2),
          _completion(id: 'c3', habitId: 'h1', completedAt: day3),
          _completion(id: 'c4', habitId: 'h1', completedAt: day4),
          // c5 is the one we're "filling": originally at today, we move it to day5
          _completion(id: 'c5', habitId: 'h1', completedAt: today),
        ];

        final repo = _MutableFakeHabitRepository(
          habit: habit,
          completions: existingCompletions,
        );
        final spy = _SpyHabitNotificationService();

        final container = ProviderContainer(
          overrides: [
            habitRepositoryProvider.overrideWithValue(repo),
            habitNotificationServiceProvider.overrideWith((ref) => spy),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(habitNotifierProvider.notifier);

        // Move today's completion to day5, filling the 5-day run
        final day5 = DateTime(lastMonth.year, lastMonth.month, 5);
        await notifier.updateCompletion(
          completionId: existingCompletions.last.id,
          habitId: 'h1',
          changedFields: {'completed_at': day5.toUtc().toIso8601String()},
        );

        expect(repo.updateHabitCalls, isEmpty);
        expect(repo.updateHabitFieldsCalls, hasLength(1));
        final updatedHabit = await repo.getHabitById('h1');
        // all-time best should now be >= 5 (days 1-5 of last month contiguous)
        expect(updatedHabit!.bestStreak, greaterThanOrEqualTo(5));
      },
    );

    test('bestStreak ratchet: never decreases', () async {
      final today = _daysAgo(0);
      final habit = Habit(
        id: 'h1',
        name: 'Meditate',
        createdAt: _daysAgo(200),
        modifiedAt: _daysAgo(1),
        frequency: HabitFrequency.daily,
        bestStreak: 100, // high stored value
        currentStreak: 1,
      );

      // Only 2 completions: yesterday and today → all-time best is 2
      final completions = [
        _completion(id: 'c1', habitId: 'h1', completedAt: _daysAgo(1)),
        _completion(id: 'c2', habitId: 'h1', completedAt: today),
      ];

      final repo = _MutableFakeHabitRepository(
        habit: habit,
        completions: completions,
      );
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      // Notes-only edit: all-time best stays 2, but stored bestStreak is 100
      await notifier.updateCompletion(
        completionId: completions[1].id,
        habitId: 'h1',
        changedFields: {'notes': 'calm session'},
      );

      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, hasLength(1));
      final updatedHabit = await repo.getHabitById('h1');
      // bestStreak must never decrease below persisted 100
      expect(updatedHabit!.bestStreak, 100);
    });

    test('returns silently when affected==0 (tombstoned)', () async {
      final today = _daysAgo(0);
      final habit = Habit(
        id: 'h1',
        name: 'Walk',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(1),
        frequency: HabitFrequency.daily,
      );

      final completions = [
        _completion(id: 'c1', habitId: 'h1', completedAt: today),
      ];

      final repo = _MutableFakeHabitRepository(
        habit: habit,
        completions: completions,
      )..updateCompletionFieldsResult = 0; // simulate tombstoned

      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      await notifier.updateCompletion(
        completionId: completions[0].id,
        habitId: 'h1',
        changedFields: {'notes': 'some change'},
      );

      // No habit update should have fired
      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, isEmpty);
      // No notification scheduling
      expect(spy.scheduleForHabitCalls, isEmpty);
    });

    test('notes-only edit does NOT call repo.updateHabit', () async {
      final today = _daysAgo(0);
      final habit = Habit(
        id: 'h1',
        name: 'Read',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(10),
        frequency: HabitFrequency.daily,
        currentStreak: 3,
        bestStreak: 5,
      );

      // Three consecutive completions producing streak=3, best=5 unchanged.
      final completions = [
        _completion(id: 'c1', habitId: 'h1', completedAt: _daysAgo(2)),
        _completion(id: 'c2', habitId: 'h1', completedAt: _daysAgo(1)),
        _completion(id: 'c3', habitId: 'h1', completedAt: today),
      ];

      final repo = _MutableFakeHabitRepository(
        habit: habit,
        completions: completions,
      );
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      // Notes-only edit: streaks are unchanged (currentStreak=3 == habit.currentStreak=3,
      // bestStreak=5 == habit.bestStreak=5).
      await notifier.updateCompletion(
        completionId: completions[2].id,
        habitId: 'h1',
        changedFields: {'notes': 'just a note'},
      );

      // updateHabit must NOT have been called — streaks unchanged.
      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, isEmpty);
      // But notification reschedule must still have fired.
      expect(spy.scheduleForHabitCalls, hasLength(1));
    });

    test('day-boundary move DOES patch habit stats', () async {
      final today = _daysAgo(0);
      final habit = Habit(
        id: 'h1',
        name: 'Run',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(10),
        frequency: HabitFrequency.daily,
        currentStreak: 3,
        bestStreak: 3,
      );

      // Three consecutive completions: streak=3.
      final completions = [
        _completion(id: 'c1', habitId: 'h1', completedAt: _daysAgo(2)),
        _completion(id: 'c2', habitId: 'h1', completedAt: _daysAgo(1)),
        _completion(id: 'c3', habitId: 'h1', completedAt: today),
      ];

      final repo = _MutableFakeHabitRepository(
        habit: habit,
        completions: completions,
      );
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      // Move today's completion to 4 days ago — breaks the streak (currentStreak drops to 2).
      await notifier.updateCompletion(
        completionId: completions[2].id,
        habitId: 'h1',
        changedFields: {'completed_at': _daysAgo(4).toUtc().toIso8601String()},
      );

      // Streak changed → partial habit stat patch must have been written.
      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, hasLength(1));
      expect(
        repo.updateHabitFieldsCalls.first.keys,
        contains('current_streak'),
      );
      expect(
        repo.updateHabitFieldsCalls.first.keys,
        isNot(contains('is_deleted')),
      );
      // currentStreak should now be 2 (days: yesterday, 2-days-ago; today empty).
      final currentHabit = await repo.getHabitById('h1');
      expect(currentHabit!.currentStreak, 2);
    });

    test(
      'reschedules notifications with skipCurrentPeriod recomputed',
      () async {
        final today = _daysAgo(0);
        final yesterday = _daysAgo(1);

        final habit = Habit(
          id: 'h1',
          name: 'Stretch',
          createdAt: _daysAgo(10),
          modifiedAt: _daysAgo(1),
          frequency: HabitFrequency.daily,
          notificationsEnabled: true,
        );

        // Only completion is today
        final completions = [
          _completion(id: 'c1', habitId: 'h1', completedAt: today),
        ];

        final repo = _MutableFakeHabitRepository(
          habit: habit,
          completions: completions,
        );
        final spy = _SpyHabitNotificationService();

        final container = ProviderContainer(
          overrides: [
            habitRepositoryProvider.overrideWithValue(repo),
            habitNotificationServiceProvider.overrideWith((ref) => spy),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(habitNotifierProvider.notifier);

        // Move today's completion to yesterday → today is no longer complete
        await notifier.updateCompletion(
          completionId: completions[0].id,
          habitId: 'h1',
          changedFields: {'completed_at': yesterday.toUtc().toIso8601String()},
        );

        expect(spy.scheduleForHabitCalls, hasLength(1));
        // Today is now uncompleted → skipCurrentPeriod should be false
        expect(spy.scheduleForHabitCalls.first.skipCurrentPeriod, isFalse);
      },
    );
  });

  group('HabitNotifier.uncompleteHabit reschedule fix', () {
    test('uncompleteHabit calls scheduleForHabit explicitly', () async {
      final today = _daysAgo(0);
      final habit = Habit(
        id: 'h1',
        name: 'Yoga',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(1),
        frequency: HabitFrequency.daily,
        currentStreak: 1,
        bestStreak: 1,
        totalCompletions: 1,
        notificationsEnabled: true,
      );

      final completions = [
        _completion(id: 'c1', habitId: 'h1', completedAt: today),
      ];

      final repo = _MutableFakeHabitRepository(
        habit: habit,
        completions: completions,
      );
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      await notifier.uncompleteHabit(habitId: 'h1', completionId: 'c1');

      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, hasLength(1));
      expect(
        repo.updateHabitFieldsCalls.first.keys,
        containsAll({
          'total_completions',
          'current_streak',
          'best_streak',
          'modified_at',
        }),
      );
      expect(
        repo.updateHabitFieldsCalls.first.keys,
        isNot(contains('is_deleted')),
      );
      // After uncomplete, scheduleForHabit MUST have been called explicitly
      expect(spy.scheduleForHabitCalls, hasLength(1));
      // Today has no completion anymore → skipCurrentPeriod should be false
      expect(spy.scheduleForHabitCalls.first.skipCurrentPeriod, isFalse);
    });

    test(
      'uncompleteHabit no-ops when completion is already tombstoned',
      () async {
        final habit = Habit(
          id: 'h1',
          name: 'Yoga',
          createdAt: _daysAgo(10),
          modifiedAt: _daysAgo(1),
          frequency: HabitFrequency.daily,
          currentStreak: 1,
          bestStreak: 1,
          totalCompletions: 1,
          notificationsEnabled: true,
        );

        final repo = _MutableFakeHabitRepository(habit: habit, completions: [])
          ..deleteCompletionResult = 0;
        final spy = _SpyHabitNotificationService();

        final container = ProviderContainer(
          overrides: [
            habitRepositoryProvider.overrideWithValue(repo),
            habitNotificationServiceProvider.overrideWith((ref) => spy),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(habitNotifierProvider.notifier);

        await notifier.uncompleteHabit(habitId: 'h1', completionId: 'c1');

        expect(repo.updateHabitCalls, isEmpty);
        expect(repo.updateHabitFieldsCalls, isEmpty);
        expect(spy.scheduleForHabitCalls, isEmpty);
        final currentHabit = await repo.getHabitById('h1');
        expect(currentHabit!.totalCompletions, 1);
      },
    );
  });

  group('HabitNotifier.completeHabit past-date schedule fix', () {
    test('completeHabit no-ops when habit is missing or tombstoned', () async {
      final habit = Habit(
        id: 'h1',
        name: 'Walk',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(1),
        frequency: HabitFrequency.daily,
        notificationsEnabled: true,
      );

      final repo = _MutableFakeHabitRepository(habit: habit, completions: [])
        ..getHabitByIdReturnsNull = true;
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      await notifier.completeHabit(habitId: 'h1');

      expect(await repo.getAllCompletions(), isEmpty);
      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, isEmpty);
      expect(spy.scheduleForHabitCalls, isEmpty);
    });

    test('past-dated completion does NOT skip today reminder', () async {
      // Habit: daily, no completions today. Log a missed completion for yesterday.
      // Today is still incomplete → skipCurrentPeriod must be false.
      final now = DateTime.now();
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));

      final habit = Habit(
        id: 'h1',
        name: 'Walk',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(1),
        frequency: HabitFrequency.daily,
        notificationsEnabled: true,
      );

      final repo = _MutableFakeHabitRepository(habit: habit, completions: []);
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      await notifier.completeHabit(
        habitId: 'h1',
        completedAt: yesterday, // logging a missed completion for yesterday
      );

      expect(spy.scheduleForHabitCalls, hasLength(1));
      // Today is still incomplete → reminder should NOT be skipped
      expect(spy.scheduleForHabitCalls.first.skipCurrentPeriod, isFalse);
    });

    test('today completion DOES skip today reminder', () async {
      // Habit: daily, no completions. Log for today (default path).
      // skipCurrentPeriod must be true.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final habit = Habit(
        id: 'h1',
        name: 'Meditate',
        createdAt: _daysAgo(10),
        modifiedAt: _daysAgo(1),
        frequency: HabitFrequency.daily,
        notificationsEnabled: true,
      );

      final repo = _MutableFakeHabitRepository(habit: habit, completions: []);
      final spy = _SpyHabitNotificationService();

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(repo),
          habitNotificationServiceProvider.overrideWith((ref) => spy),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(habitNotifierProvider.notifier);

      await notifier.completeHabit(
        habitId: 'h1',
        completedAt: today, // today's completion
      );

      expect(repo.updateHabitCalls, isEmpty);
      expect(repo.updateHabitFieldsCalls, hasLength(1));
      expect(
        repo.updateHabitFieldsCalls.first.keys,
        containsAll({
          'total_completions',
          'current_streak',
          'best_streak',
          'modified_at',
        }),
      );
      expect(
        repo.updateHabitFieldsCalls.first.keys,
        isNot(contains('is_deleted')),
      );
      expect(spy.scheduleForHabitCalls, hasLength(1));
      // Today is completed → reminder SHOULD be skipped
      expect(spy.scheduleForHabitCalls.first.skipCurrentPeriod, isTrue);
    });

    test(
      'completeHabit deletes the created completion when stats patch loses a delete race',
      () async {
        final habit = Habit(
          id: 'h1',
          name: 'Meditate',
          createdAt: _daysAgo(10),
          modifiedAt: _daysAgo(1),
          frequency: HabitFrequency.daily,
          notificationsEnabled: true,
        );

        final repo = _MutableFakeHabitRepository(habit: habit, completions: [])
          ..updateHabitFieldsResult = 0;
        final spy = _SpyHabitNotificationService();

        final container = ProviderContainer(
          overrides: [
            habitRepositoryProvider.overrideWithValue(repo),
            habitNotificationServiceProvider.overrideWith((ref) => spy),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(habitNotifierProvider.notifier);

        await notifier.completeHabit(habitId: 'h1');

        expect(await repo.getAllCompletions(), isEmpty);
        expect(repo.updateHabitCalls, isEmpty);
        expect(spy.scheduleForHabitCalls, isEmpty);
      },
    );
  });
}
