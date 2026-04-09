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
}
