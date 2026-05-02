import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/features/habits/utils/habit_due.dart';

void main() {
  group('isHabitDueToday', () {
    group('interval frequency', () {
      test('empty completions list returns true (regression guard)', () {
        // If the `isEmpty` check before `reduce()` were removed,
        // this would throw a StateError on the empty iterable.
        final now = DateTime(2026, 4, 8, 10);
        final habit = Habit(
          id: 'habit-interval',
          name: 'Water plants',
          createdAt: now.subtract(const Duration(days: 30)),
          modifiedAt: now,
          frequency: HabitFrequency.interval,
          intervalDays: 3,
        );

        final result = isHabitDueToday(
          habit: habit,
          todayCompletions: const [],
          allCompletions: const [],
          now: now,
        );

        expect(result, isTrue);
      });

      test('null intervalDays returns true', () {
        final now = DateTime(2026, 4, 8, 10);
        final habit = Habit(
          id: 'habit-null-interval',
          name: 'Flexible habit',
          createdAt: now.subtract(const Duration(days: 30)),
          modifiedAt: now,
          frequency: HabitFrequency.interval,
          intervalDays: null,
        );

        final completion = HabitCompletion(
          id: 'c-1',
          habitId: habit.id,
          completedAt: now.subtract(const Duration(hours: 1)),
          createdAt: now,
          modifiedAt: now,
        );

        final result = isHabitDueToday(
          habit: habit,
          todayCompletions: [completion],
          allCompletions: [completion],
          now: now,
        );

        expect(result, isTrue);
      });

      test(
        'empty completions with unrelated habit completions still returns true',
        () {
          final now = DateTime(2026, 4, 8, 10);
          final habit = Habit(
            id: 'habit-a',
            name: 'Habit A',
            createdAt: now.subtract(const Duration(days: 30)),
            modifiedAt: now,
            frequency: HabitFrequency.interval,
            intervalDays: 2,
          );

          // Completions exist but for a different habit
          final unrelatedCompletion = HabitCompletion(
            id: 'c-other',
            habitId: 'habit-b',
            completedAt: now.subtract(const Duration(hours: 1)),
            createdAt: now,
            modifiedAt: now,
          );

          final result = isHabitDueToday(
            habit: habit,
            todayCompletions: const [],
            allCompletions: [unrelatedCompletion],
            now: now,
          );

          expect(result, isTrue);
        },
      );
    });
  });

  group('isHabitCompletedForCurrentPeriod', () {
    final now = DateTime(2026, 5, 1, 14, 0); // Friday

    Habit buildHabit({
      required HabitFrequency frequency,
      List<int>? weeklyDays,
      int? intervalDays,
    }) =>
        Habit(
          id: 'h',
          name: 'h',
          createdAt: now.subtract(const Duration(days: 30)),
          modifiedAt: now,
          frequency: frequency,
          weeklyDays: weeklyDays,
          intervalDays: intervalDays,
        );

    HabitCompletion completionAt(DateTime when) => HabitCompletion(
          id: 'c-${when.millisecondsSinceEpoch}',
          habitId: 'h',
          completedAt: when,
          createdAt: when,
          modifiedAt: when,
        );

    test('daily — completed today returns true', () {
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(frequency: HabitFrequency.daily),
        todayCompletions: [completionAt(now.subtract(const Duration(hours: 2)))],
        allCompletions: const [],
        now: now,
      );
      expect(result, isTrue);
    });

    test('daily — no completion today returns false', () {
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(frequency: HabitFrequency.daily),
        todayCompletions: const [],
        allCompletions: const [],
        now: now,
      );
      expect(result, isFalse);
    });

    test('weekly — completed today on a target weekday returns true', () {
      // Friday is weekday index 5 (Dart 5 % 7 = 5).
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(
          frequency: HabitFrequency.weekly,
          weeklyDays: [1, 3, 5],
        ),
        todayCompletions: [completionAt(now)],
        allCompletions: const [],
        now: now,
      );
      expect(result, isTrue);
    });

    test('weekly — completed today on a non-target weekday returns false', () {
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(
          frequency: HabitFrequency.weekly,
          weeklyDays: [1, 3], // Mon, Wed only — Friday isn't a target
        ),
        todayCompletions: [completionAt(now)],
        allCompletions: const [],
        now: now,
      );
      expect(result, isFalse);
    });

    test('interval — completion within window returns true', () {
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(frequency: HabitFrequency.interval, intervalDays: 3),
        todayCompletions: const [],
        allCompletions: [completionAt(now.subtract(const Duration(days: 1)))],
        now: now,
      );
      expect(result, isTrue);
    });

    test('interval — completion outside window returns false', () {
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(frequency: HabitFrequency.interval, intervalDays: 3),
        todayCompletions: const [],
        allCompletions: [completionAt(now.subtract(const Duration(days: 5)))],
        now: now,
      );
      expect(result, isFalse);
    });

    test('interval — no completions returns false', () {
      final result = isHabitCompletedForCurrentPeriod(
        habit: buildHabit(frequency: HabitFrequency.interval, intervalDays: 3),
        todayCompletions: const [],
        allCompletions: const [],
        now: now,
      );
      expect(result, isFalse);
    });
  });
}
