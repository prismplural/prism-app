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

/// Whether [habit] has been completed for the period that is currently
/// active. Used to suppress same-period reminder notifications once the
/// user has logged a completion.
///
/// Period semantics:
/// - daily / custom → today
/// - weekly → today, but only when today's weekday is one of the configured
///   target days (off-target weekdays return false since no reminder fires)
/// - interval → the rolling `intervalDays` window since the last completion
bool isHabitCompletedForCurrentPeriod({
  required Habit habit,
  required Iterable<HabitCompletion> todayCompletions,
  required Iterable<HabitCompletion> allCompletions,
  required DateTime now,
}) {
  switch (habit.frequency) {
    case HabitFrequency.daily:
    case HabitFrequency.custom:
      return todayCompletions.any((c) => c.habitId == habit.id);
    case HabitFrequency.weekly:
      final todayIdx = now.weekday % 7;
      final isTodayTarget = habit.weeklyDays?.contains(todayIdx) ?? false;
      if (!isTodayTarget) return false;
      return todayCompletions.any((c) => c.habitId == habit.id);
    case HabitFrequency.interval:
      final intervalDays = habit.intervalDays;
      if (intervalDays == null || intervalDays <= 0) return false;
      final habitCompletions =
          allCompletions.where((c) => c.habitId == habit.id);
      if (habitCompletions.isEmpty) return false;
      final last = habitCompletions.reduce(
        (a, b) => a.completedAt.isAfter(b.completedAt) ? a : b,
      );
      final today = DateTime(now.year, now.month, now.day);
      final lastDay = DateTime(
        last.completedAt.year,
        last.completedAt.month,
        last.completedAt.day,
      );
      return today.difference(lastDay).inDays < intervalDays;
  }
}
