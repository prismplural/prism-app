import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/habits/services/habit_notification_service.dart';
import 'package:prism_plurality/features/habits/utils/habit_due.dart';

/// Provides today's date (year, month, day only — no time component).
///
/// Automatically invalidates itself at midnight via a timer so that all
/// date-dependent providers (todayCompletionsProvider, weeklyCompletionsProvider,
/// dueHabitsCountProvider) re-evaluate with the new calendar day.
///
/// NOTE: For app lifecycle resume, the AppShell (which has WidgetsBindingObserver)
/// should call `ref.invalidate(currentDateProvider)` in its `didChangeAppLifecycleState`
/// when the state is `AppLifecycleState.resumed`. This handles the case where the
/// device was asleep across midnight.
final currentDateProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Schedule invalidation at midnight.
  final tomorrow = today.add(const Duration(days: 1));
  final durationUntilMidnight = tomorrow.difference(now);
  final timer = Timer(durationUntilMidnight, () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  return today;
});

/// Watches all active habits.
final habitsProvider = StreamProvider<List<Habit>>((ref) {
  final repo = ref.watch(habitRepositoryProvider);
  return repo.watchActiveHabits();
});

/// Watches a single habit by ID.
final habitByIdProvider = StreamProvider.autoDispose.family<Habit?, String>((ref, id) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(seconds: 30), link.close);
  });
  ref.onResume(() => timer?.cancel());
  final repo = ref.watch(habitRepositoryProvider);
  return repo.watchHabitById(id);
});

/// Watches completions for a specific habit.
final habitCompletionsProvider =
    StreamProvider.autoDispose.family<List<HabitCompletion>, String>((ref, habitId) {
      final repo = ref.watch(habitRepositoryProvider);
      return repo.watchCompletionsForHabit(habitId);
    });

/// Watches completions for today's date.
/// Depends on [currentDateProvider] so it re-evaluates at midnight and on
/// app resume.
final todayCompletionsProvider = StreamProvider<List<HabitCompletion>>((ref) {
  final today = ref.watch(currentDateProvider);
  final repo = ref.watch(habitRepositoryProvider);
  return repo.watchCompletionsForDate(today);
});

/// Watches all completions across all habits.
final allCompletionsProvider = StreamProvider<List<HabitCompletion>>((ref) {
  final repo = ref.watch(habitRepositoryProvider);
  return repo.watchAllCompletions();
});

/// Watches completions for the current week (Monday–Sunday).
/// Depends on [currentDateProvider] so it re-evaluates at midnight and on
/// app resume.
final weeklyCompletionsProvider = StreamProvider<List<HabitCompletion>>((ref) {
  final today = ref.watch(currentDateProvider);
  final repo = ref.watch(habitRepositoryProvider);
  // Monday = 1 in Dart's weekday
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final sunday = monday.add(const Duration(days: 6));
  return repo.watchCompletionsForDateRange(monday, sunday);
});

/// Count of habits that are due today but not yet completed.
final dueHabitsCountProvider = Provider<int>((ref) {
  final habits = ref.watch(habitsProvider).value ?? [];
  final todayCompletions = ref.watch(todayCompletionsProvider).value ?? [];
  final allCompletions = ref.watch(allCompletionsProvider).value ?? [];
  final completedIds = todayCompletions.map((c) => c.habitId).toSet();
  final now = ref.watch(currentDateProvider);

  int count = 0;
  for (final habit in habits) {
    if (!habit.isActive || completedIds.contains(habit.id)) continue;
    final isDue = isHabitDueToday(
      habit: habit,
      todayCompletions: todayCompletions,
      allCompletions: allCompletions,
      now: now,
    );
    if (isDue) count++;
  }
  return count;
});

/// Stats for a habit over a given timeframe.
final habitStatsProvider =
    FutureProvider.autoDispose.family<
      HabitStats,
      ({String habitId, StatisticsTimeframe timeframe})
    >((ref, params) async {
      final repo = ref.watch(habitRepositoryProvider);
      final habit = await repo.getHabitById(params.habitId);
      if (habit == null) {
        return const HabitStats(
          totalCompletions: 0,
          expectedCompletions: 0,
          completionRate: 0,
          currentStreak: 0,
          bestStreak: 0,
        );
      }

      final since = params.timeframe.startDate;
      final completions = await repo.getCompletionsForHabit(
        params.habitId,
        since: since,
      );

      // Calculate expected completions
      final now = DateTime.now();
      final daysSince = now.difference(since).inDays;
      final expectedCompletions = switch (habit.frequency) {
        HabitFrequency.daily => daysSince,
        HabitFrequency.weekly =>
          habit.weeklyDays != null
              ? (daysSince ~/ 7) * habit.weeklyDays!.length
              : daysSince ~/ 7,
        HabitFrequency.interval =>
          habit.intervalDays != null && habit.intervalDays! > 0
              ? daysSince ~/ habit.intervalDays!
              : daysSince,
        HabitFrequency.custom => daysSince,
      };

      final rate = expectedCompletions > 0
          ? (completions.length / expectedCompletions * 100)
                .clamp(0, 100)
                .toDouble()
          : 0.0;

      // Average rating
      final rated = completions.where((c) => c.rating != null).toList();
      final avgRating = rated.isNotEmpty
          ? rated.map((c) => c.rating!).reduce((a, b) => a + b) / rated.length
          : null;

      // Completions by member
      final byMember = <String, int>{};
      for (final c in completions) {
        final key = c.completedByMemberId ?? 'unknown';
        byMember[key] = (byMember[key] ?? 0) + 1;
      }

      return HabitStats(
        totalCompletions: completions.length,
        expectedCompletions: expectedCompletions.clamp(
          0,
          double.maxFinite.toInt(),
        ),
        completionRate: rate,
        currentStreak: habit.currentStreak,
        bestStreak: habit.bestStreak,
        averageRating: avgRating,
        completionsByMember: byMember,
      );
    });

/// Notifier for habit CRUD and completion actions.
class HabitNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createHabit(Habit habit) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(habitRepositoryProvider);
      await repo.createHabit(habit);
      // Schedule notifications if enabled.
      final notifService = ref.read(habitNotificationServiceProvider);
      await notifService.scheduleForHabit(habit);
    });
  }

  Future<void> updateHabit(Habit habit) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(habitRepositoryProvider);
      await repo.updateHabit(habit);
      // Reschedule notifications.
      final notifService = ref.read(habitNotificationServiceProvider);
      await notifService.scheduleForHabit(habit);
    });
  }

  Future<void> deleteHabit(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(habitRepositoryProvider);
      // Cancel notifications before deleting.
      final notifService = ref.read(habitNotificationServiceProvider);
      await notifService.cancelForHabit(id);
      await repo.deleteHabit(id);
    });
  }

  Future<void> toggleActive(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(habitRepositoryProvider);
      final habit = await repo.getHabitById(id);
      if (habit == null) return;
      // Cancel notifications when deactivating; listener handles rescheduling on reactivate.
      // habit.isActive is the CURRENT value — true means it's about to become inactive.
      if (habit.isActive) {
        final notifService = ref.read(habitNotificationServiceProvider);
        await notifService.cancelForHabit(id);
      }
      await repo.updateHabit(
        habit.copyWith(isActive: !habit.isActive, modifiedAt: DateTime.now()),
      );
    });
  }

  /// Complete a habit and recalculate streaks.
  Future<void> completeHabit({
    required String habitId,
    String? completedByMemberId,
    String? notes,
    int? rating,
    bool wasFronting = false,
    DateTime? completedAt,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(habitRepositoryProvider);
      final now = DateTime.now();

      final completion = HabitCompletion(
        id: _uuid.v4(),
        habitId: habitId,
        completedAt: completedAt ?? now,
        completedByMemberId: completedByMemberId,
        notes: notes,
        wasFronting: wasFronting,
        rating: rating,
        createdAt: now,
        modifiedAt: now,
      );
      await repo.createCompletion(completion);

      // Update habit stats
      final habit = await repo.getHabitById(habitId);
      if (habit == null) return;

      final completions = await repo.getCompletionsForHabit(habitId);
      final currentStreak = _calculateCurrentStreak(habit, completions);
      final bestStreak = currentStreak > habit.bestStreak
          ? currentStreak
          : habit.bestStreak;

      await repo.updateHabit(
        habit.copyWith(
          totalCompletions: habit.totalCompletions + 1,
          currentStreak: currentStreak,
          bestStreak: bestStreak,
          modifiedAt: now,
        ),
      );
    });
  }

  /// Remove a completion and recalculate streaks.
  Future<void> uncompleteHabit({
    required String habitId,
    required String completionId,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(habitRepositoryProvider);
      await repo.deleteCompletion(completionId);

      final habit = await repo.getHabitById(habitId);
      if (habit == null) return;

      final completions = await repo.getCompletionsForHabit(habitId);
      final currentStreak = _calculateCurrentStreak(habit, completions);
      // bestStreak is a ratchet: never decreases
      final bestStreak = currentStreak > habit.bestStreak
          ? currentStreak
          : habit.bestStreak;

      await repo.updateHabit(
        habit.copyWith(
          totalCompletions: (habit.totalCompletions - 1).clamp(
            0,
            double.maxFinite.toInt(),
          ),
          currentStreak: currentStreak,
          bestStreak: bestStreak,
          modifiedAt: DateTime.now(),
        ),
      );
    });
  }

  // ── Streak Calculation ───────────────────────────────────────────

  int _calculateCurrentStreak(Habit habit, List<HabitCompletion> completions) {
    if (completions.isEmpty) return 0;

    return switch (habit.frequency) {
      HabitFrequency.daily ||
      HabitFrequency.custom => _calculateDailyStreak(completions),
      HabitFrequency.weekly => _calculateWeeklyStreak(habit, completions),
      HabitFrequency.interval => _calculateIntervalStreak(habit, completions),
    };
  }

  /// Daily/custom: count consecutive days backward from today with >=1
  /// completion. If today has no completion, start from yesterday.
  int _calculateDailyStreak(List<HabitCompletion> completions) {
    final completionDays = <DateTime>{};
    for (final c in completions) {
      completionDays.add(
        DateTime(c.completedAt.year, c.completedAt.month, c.completedAt.day),
      );
    }

    final today = DateTime.now();
    var checkDate = DateTime(today.year, today.month, today.day);

    // If today is not completed, start from yesterday
    if (!completionDays.contains(checkDate)) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    int streak = 0;
    while (completionDays.contains(checkDate)) {
      streak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Weekly: count consecutive weeks where ALL required weeklyDays have
  /// completions.
  int _calculateWeeklyStreak(Habit habit, List<HabitCompletion> completions) {
    final requiredDays = habit.weeklyDays;
    if (requiredDays == null || requiredDays.isEmpty) return 0;

    // Group completions by week (ISO week starting Monday)
    final completionsByWeek = <int, Set<int>>{};
    for (final c in completions) {
      final weekKey = _weekNumber(c.completedAt);
      completionsByWeek
          .putIfAbsent(weekKey, () => <int>{})
          .add(c.completedAt.weekday % 7); // 0=Sun
    }

    final today = DateTime.now();
    var currentWeek = _weekNumber(today);

    // Check if current week is complete; if not, start from previous week
    final currentWeekDays = completionsByWeek[currentWeek] ?? {};
    if (!requiredDays.every(currentWeekDays.contains)) {
      currentWeek--;
    }

    int streak = 0;
    while (true) {
      final weekDays = completionsByWeek[currentWeek] ?? {};
      if (requiredDays.every(weekDays.contains)) {
        streak++;
        currentWeek--;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Interval: count consecutive interval periods backward with >=1
  /// completion.
  int _calculateIntervalStreak(Habit habit, List<HabitCompletion> completions) {
    final intervalDays = habit.intervalDays;
    if (intervalDays == null || intervalDays <= 0) return 0;

    final completionDates = completions
        .map(
          (c) => DateTime(
            c.completedAt.year,
            c.completedAt.month,
            c.completedAt.day,
          ),
        )
        .toSet();

    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    // Find the most recent period end
    var periodEnd = today;
    var periodStart = periodEnd.subtract(Duration(days: intervalDays - 1));

    // Check if current period has a completion; if not, move back one period
    bool hasCompletionInRange(DateTime start, DateTime end) {
      return completionDates.any(
        (d) =>
            (d.isAtSameMomentAs(start) || d.isAfter(start)) &&
            (d.isAtSameMomentAs(end) || d.isBefore(end)),
      );
    }

    if (!hasCompletionInRange(periodStart, periodEnd)) {
      periodEnd = periodStart.subtract(const Duration(days: 1));
      periodStart = periodEnd.subtract(Duration(days: intervalDays - 1));
    }

    int streak = 0;
    while (hasCompletionInRange(periodStart, periodEnd)) {
      streak++;
      periodEnd = periodStart.subtract(const Duration(days: 1));
      periodStart = periodEnd.subtract(Duration(days: intervalDays - 1));
    }
    return streak;
  }

  /// Returns an integer representing the ISO week number * year
  /// (unique key per week).
  int _weekNumber(DateTime date) {
    // Simple approach: days since epoch / 7, offset to align with weeks
    final epoch = DateTime(1970, 1, 5); // Monday
    return date.difference(epoch).inDays ~/ 7;
  }
}

final habitNotifierProvider = AsyncNotifierProvider<HabitNotifier, void>(
  HabitNotifier.new,
);

/// Watches all active habits and reschedules notifications on any change,
/// including sync-driven updates from other devices. Mirrors the
/// [reminderSchedulerListenerProvider] pattern with a 500ms debounce to
/// batch rapid consecutive changes (e.g., bulk sync).
final habitNotificationListenerProvider = Provider<void>((ref) {
  final service = ref.watch(habitNotificationServiceProvider);
  Timer? debounceTimer;
  ref.onDispose(() => debounceTimer?.cancel());

  ref.listen(
    habitsProvider,
    (previous, next) {
      final habits = next.value;
      if (habits != null) {
        debounceTimer?.cancel();
        debounceTimer = Timer(const Duration(milliseconds: 500), () {
          service.rescheduleAll(habits).catchError((e) {
            debugPrint('Habit notification reschedule failed (non-fatal): $e');
          });
        });
      }
    },
    fireImmediately: true,
  );
});
