import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/utils/habit_due.dart';

void main() {
  group('dueHabitsCountProvider', () {
    test('interval habit completed yesterday is not due', () async {
      final now = DateTime(2026, 4, 7, 10);
      final today = DateTime(now.year, now.month, now.day);
      final habit = Habit(
        id: 'habit-1',
        name: 'Water plants',
        createdAt: now.subtract(const Duration(days: 30)),
        modifiedAt: now,
        frequency: HabitFrequency.interval,
        intervalDays: 5,
      );
      final completion = HabitCompletion(
        id: 'completion-1',
        habitId: habit.id,
        completedAt: DateTime(2026, 4, 6, 20),
        createdAt: now,
        modifiedAt: now,
      );

      final container = ProviderContainer(
        overrides: [
          habitRepositoryProvider.overrideWithValue(
            _FakeHabitRepository(habits: [habit], allCompletions: [completion]),
          ),
          currentDateProvider.overrideWith((ref) => today),
        ],
      );
      addTearDown(container.dispose);

      container.read(habitsProvider);
      container.read(todayCompletionsProvider);
      container.read(allCompletionsProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(dueHabitsCountProvider), 0);
    });

    test('interval habit is due once interval days have elapsed', () {
      final now = DateTime(2026, 4, 7, 10);
      final today = DateTime(now.year, now.month, now.day);
      final habit = Habit(
        id: 'habit-1',
        name: 'Water plants',
        createdAt: now.subtract(const Duration(days: 30)),
        modifiedAt: now,
        frequency: HabitFrequency.interval,
        intervalDays: 5,
      );
      final completion = HabitCompletion(
        id: 'completion-1',
        habitId: habit.id,
        completedAt: DateTime(2026, 4, 2, 8),
        createdAt: now,
        modifiedAt: now,
      );

      expect(
        isHabitDueToday(
          habit: habit,
          todayCompletions: const [],
          allCompletions: [completion],
          now: today,
        ),
        isTrue,
      );
    });
  });
}

class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({
    required List<Habit> habits,
    required List<HabitCompletion> allCompletions,
  }) : _habits = List.unmodifiable(habits),
       _allCompletions = List.unmodifiable(allCompletions);

  final List<Habit> _habits;
  final List<HabitCompletion> _allCompletions;

  @override
  Future<void> createCompletion(HabitCompletion completion) async =>
      throw UnimplementedError();

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<void> deleteCompletion(String id) async => throw UnimplementedError();

  @override
  Future<void> deleteHabit(String id) async => throw UnimplementedError();

  @override
  Future<List<HabitCompletion>> getAllCompletions() async => _allCompletions;

  @override
  Future<List<Habit>> getAllHabits() async => _habits;

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async {
    return _allCompletions.where((completion) {
      if (completion.habitId != habitId) return false;
      return since == null || !completion.completedAt.isBefore(since);
    }).toList();
  }

  @override
  Future<Habit?> getHabitById(String id) async {
    for (final habit in _habits) {
      if (habit.id == id) return habit;
    }
    return null;
  }

  @override
  Future<void> updateHabit(Habit habit) async => throw UnimplementedError();

  @override
  Stream<List<HabitCompletion>> watchAllCompletions() =>
      Stream.value(_allCompletions);

  @override
  Stream<List<Habit>> watchAllHabits() => Stream.value(_habits);

  @override
  Stream<List<Habit>> watchActiveHabits() =>
      Stream.value(_habits.where((habit) => habit.isActive).toList());

  @override
  Stream<Habit?> watchHabitById(String id) {
    for (final habit in _habits) {
      if (habit.id == id) return Stream.value(habit);
    }
    return Stream<Habit?>.value(null);
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return Stream.value(
      _allCompletions.where((completion) {
        return !completion.completedAt.isBefore(start) &&
            completion.completedAt.isBefore(end);
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
      _allCompletions.where((completion) {
        return !completion.completedAt.isBefore(rangeStart) &&
            completion.completedAt.isBefore(rangeEnd);
      }).toList(),
    );
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value(
        _allCompletions
            .where((completion) => completion.habitId == habitId)
            .toList(),
      );
}
