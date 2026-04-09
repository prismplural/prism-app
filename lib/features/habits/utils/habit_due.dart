import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';

bool isHabitDueToday({
  required Habit habit,
  required Iterable<HabitCompletion> todayCompletions,
  required Iterable<HabitCompletion> allCompletions,
  required DateTime now,
}) {
  final completedToday = todayCompletions.any((c) => c.habitId == habit.id);

  return switch (habit.frequency) {
    HabitFrequency.daily => true,
    HabitFrequency.weekly =>
      habit.weeklyDays?.contains(now.weekday % 7) ?? false,
    HabitFrequency.interval => _isIntervalDue(habit, allCompletions, now),
    HabitFrequency.custom => !completedToday,
  };
}

bool _isIntervalDue(
  Habit habit,
  Iterable<HabitCompletion> allCompletions,
  DateTime now,
) {
  if (habit.intervalDays == null) return true;

  final habitCompletions = allCompletions.where((c) => c.habitId == habit.id);
  if (habitCompletions.isEmpty) return true; // no completions = due
  final lastCompletion = habitCompletions.reduce(
    (a, b) => a.completedAt.isAfter(b.completedAt) ? a : b,
  );

  final todayStart = DateTime(now.year, now.month, now.day);
  final lastDay = DateTime(
    lastCompletion.completedAt.year,
    lastCompletion.completedAt.month,
    lastCompletion.completedAt.day,
  );
  return todayStart.difference(lastDay).inDays >= habit.intervalDays!;
}
