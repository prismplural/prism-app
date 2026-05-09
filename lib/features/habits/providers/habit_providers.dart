import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/material.dart' show DateUtils;
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
final habitByIdProvider = StreamProvider.autoDispose.family<Habit?, String>((
  ref,
  id,
) {
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
final habitCompletionsProvider = StreamProvider.autoDispose
    .family<List<HabitCompletion>, String>((ref, habitId) {
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
final habitStatsProvider = FutureProvider.autoDispose
    .family<HabitStats, ({String habitId, StatisticsTimeframe timeframe})>((
      ref,
      params,
    ) async {
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

  Future<void> updateHabitFields({
    required String habitId,
    required Map<String, dynamic> changedFields,
  }) async {
    state = await AsyncValue.guard(() async {
      if (changedFields.isEmpty) return;
      final repo = ref.read(habitRepositoryProvider);
      final patch = Map<String, dynamic>.from(changedFields);
      patch['modified_at'] = DateTime.now().toUtc().toIso8601String();

      final affected = await repo.updateHabitFields(habitId, patch);
      if (affected != 1) return;

      final habit = await repo.getHabitById(habitId);
      if (habit == null) return;
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
      final now = DateTime.now();
      final affected = await repo.updateHabitFields(id, {
        'is_active': !habit.isActive,
        'modified_at': now.toUtc().toIso8601String(),
      });
      if (affected != 1) return;
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
      final habit = await repo.getHabitById(habitId);
      if (habit == null) return;

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
      final completionCreated = await repo.createCompletion(completion);
      if (completionCreated != 1) return;

      final completions = await repo.getCompletionsForHabit(habitId);
      final currentStreak = _calculateCurrentStreak(habit, completions);
      final isPastDated =
          completedAt != null && !DateUtils.isSameDay(completedAt, now);
      final bestAllTime = isPastDated
          ? _calculateBestStreakAllTime(habit, completions)
          : currentStreak;
      final bestStreak = bestAllTime > habit.bestStreak
          ? bestAllTime
          : habit.bestStreak;

      final updated = habit.copyWith(
        totalCompletions: habit.totalCompletions + 1,
        currentStreak: currentStreak,
        bestStreak: bestStreak,
        modifiedAt: now,
      );
      final affected = await repo.updateHabitFields(habitId, {
        'total_completions': updated.totalCompletions,
        'current_streak': updated.currentStreak,
        'best_streak': updated.bestStreak,
        'modified_at': updated.modifiedAt.toUtc().toIso8601String(),
      });
      if (affected != 1) {
        await repo.deleteCompletion(completion.id);
        return;
      }

      // Schedule/suppress this period's reminder. For past-dated completions,
      // recompute whether today is still incomplete so a missed-yesterday log
      // doesn't silence today's reminder. For today completions, always skip
      // (we just completed it). Fires before the listener's 500ms debounce so
      // a same-day notification scheduled minutes from now doesn't slip through.
      // Also clears any already-shown notification from notification center on
      // iOS/Android (FLN.cancel removes delivered as well as pending).
      final notifService = ref.read(habitNotificationServiceProvider);
      final skipCurrentPeriod = isPastDated
          ? isHabitCompletedForCurrentPeriod(
              habit: updated,
              todayCompletions: completions
                  .where((c) => DateUtils.isSameDay(c.completedAt, now))
                  .toList(),
              allCompletions: completions,
              now: now,
            )
          : true; // today-default: skip (we just completed it)
      await notifService.scheduleForHabit(
        updated,
        skipCurrentPeriod: skipCurrentPeriod,
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
      final affected = await repo.deleteCompletion(completionId);
      if (affected != 1) return;

      final habit = await repo.getHabitById(habitId);
      if (habit == null) return;

      final completions = await repo.getCompletionsForHabit(habitId);
      final currentStreak = _calculateCurrentStreak(habit, completions);
      // bestStreak is a ratchet: never decreases
      final bestStreak = currentStreak > habit.bestStreak
          ? currentStreak
          : habit.bestStreak;

      final updatedHabit = habit.copyWith(
        totalCompletions: (habit.totalCompletions - 1).clamp(
          0,
          double.maxFinite.toInt(),
        ),
        currentStreak: currentStreak,
        bestStreak: bestStreak,
        modifiedAt: DateTime.now(),
      );
      final updateAffected = await repo.updateHabitFields(habitId, {
        'total_completions': updatedHabit.totalCompletions,
        'current_streak': updatedHabit.currentStreak,
        'best_streak': updatedHabit.bestStreak,
        'modified_at': updatedHabit.modifiedAt.toUtc().toIso8601String(),
      });
      if (updateAffected != 1) return;

      // Reschedule notifications with a fresh skipCurrentPeriod check so the
      // reminder fires again if today is no longer completed. Previously this
      // relied on the 500ms debounced listener — the explicit call here keeps
      // the two paths (complete / uncomplete) symmetric.
      final notifService = ref.read(habitNotificationServiceProvider);
      final now = DateTime.now();
      final todayCompletions = completions
          .where((c) => DateUtils.isSameDay(c.completedAt, now))
          .toList();
      final skipCurrentPeriod = isHabitCompletedForCurrentPeriod(
        habit: updatedHabit,
        todayCompletions: todayCompletions,
        allCompletions: completions,
        now: now,
      );
      await notifService.scheduleForHabit(
        updatedHabit,
        skipCurrentPeriod: skipCurrentPeriod,
      );
    });
  }

  /// Apply a patch (keyed by sync wire-format field names) to a completion.
  /// The repo does a partial DAO write + emits a sync update with only these
  /// fields, so concurrent edits to other fields don't clobber. The notifier
  /// then re-reads the resulting completion to recompute streaks and
  /// reschedule notifications.
  ///
  /// `modified_at` is bumped here so the caller doesn't have to.
  Future<void> updateCompletion({
    required String completionId,
    required String habitId,
    required Map<String, dynamic> changedFields,
  }) async {
    state = await AsyncValue.guard(() async {
      if (changedFields.isEmpty) return;
      final repo = ref.read(habitRepositoryProvider);

      final patch = Map<String, dynamic>.from(changedFields);
      patch['modified_at'] = DateTime.now().toUtc().toIso8601String();

      final affected = await repo.updateCompletionFields(completionId, patch);
      if (affected != 1) return; // tombstoned/missing — silent no-op

      final habit = await repo.getHabitById(habitId);
      if (habit == null) return;
      final completions = await repo.getCompletionsForHabit(habitId);

      final currentStreak = _calculateCurrentStreak(habit, completions);
      final bestAllTime = _calculateBestStreakAllTime(habit, completions);
      final bestStreak = bestAllTime > habit.bestStreak
          ? bestAllTime
          : habit.bestStreak;

      final habitChanged =
          currentStreak != habit.currentStreak ||
          bestStreak != habit.bestStreak;
      final updatedHabit = habitChanged
          ? habit.copyWith(
              currentStreak: currentStreak,
              bestStreak: bestStreak,
              modifiedAt: DateTime.now(),
            )
          : habit;
      if (habitChanged) {
        final affected = await repo.updateHabitFields(habitId, {
          'current_streak': updatedHabit.currentStreak,
          'best_streak': updatedHabit.bestStreak,
          'modified_at': updatedHabit.modifiedAt.toUtc().toIso8601String(),
        });
        if (affected != 1) return;
      }

      final notifService = ref.read(habitNotificationServiceProvider);
      final now = DateTime.now();
      final todayCompletions = completions
          .where((c) => DateUtils.isSameDay(c.completedAt, now))
          .toList();
      final skipCurrentPeriod = isHabitCompletedForCurrentPeriod(
        habit: updatedHabit,
        todayCompletions: todayCompletions,
        allCompletions: completions,
        now: now,
      );
      await notifService.scheduleForHabit(
        updatedHabit,
        skipCurrentPeriod: skipCurrentPeriod,
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
  int _calculateDailyStreak(
    List<HabitCompletion> completions, {
    DateTime? today,
  }) {
    final completionDays = <int>{};
    for (final c in completions) {
      completionDays.add(_localDayOrdinal(c.completedAt));
    }

    var checkDay = _localDayOrdinal(today ?? DateTime.now());

    // If today is not completed, start from yesterday
    if (!completionDays.contains(checkDay)) {
      checkDay--;
    }

    int streak = 0;
    while (completionDays.contains(checkDay)) {
      streak++;
      checkDay--;
    }
    return streak;
  }

  @visibleForTesting
  int calculateDailyStreakForTest(
    List<HabitCompletion> completions,
    DateTime today,
  ) => _calculateDailyStreak(completions, today: today);

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

  // ── All-time best streak helpers ────────────────────────────────────

  /// Returns the longest contiguous streak found anywhere in the completion
  /// history. Used by [updateCompletion] and by [completeHabit] when
  /// `completedAt` is in the past — fixes the gap where the old
  /// `max(currentStreak, bestStreak)` ratchet missed historical streaks
  /// (e.g., logging a missed completion that fills a 30-day past run).
  ///
  /// Anchoring NOTE: this differs from [_calculateCurrentStreak]. Current
  /// streak is "from today backwards"; all-time best is "longest contiguous
  /// run anywhere in history." For interval frequency, windows here are
  /// anchored to the FIRST completion (so historical edits update the
  /// streak), not to today.
  int _calculateBestStreakAllTime(
    Habit habit,
    List<HabitCompletion> completions,
  ) {
    if (completions.isEmpty) return 0;
    return switch (habit.frequency) {
      HabitFrequency.daily ||
      HabitFrequency.custom => _bestDailyStreakAllTime(completions),
      HabitFrequency.weekly => _bestWeeklyStreakAllTime(habit, completions),
      HabitFrequency.interval => _bestIntervalStreakAllTime(habit, completions),
    };
  }

  /// Build sorted unique day-keys, walk forward, run++ when next day is
  /// exactly prev+1, reset to 1 on any larger gap, max-track.
  int _bestDailyStreakAllTime(List<HabitCompletion> completions) {
    if (completions.isEmpty) return 0;
    final days = <int>{};
    for (final c in completions) {
      days.add(_localDayOrdinal(c.completedAt));
    }
    final sorted = days.toList()..sort();
    var run = 1;
    var best = 1;
    for (var i = 1; i < sorted.length; i++) {
      final delta = sorted[i] - sorted[i - 1];
      if (delta == 1) {
        run++;
        if (run > best) best = run;
      } else {
        run = 1;
      }
    }
    return best;
  }

  int _localDayOrdinal(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Walk weeks chronologically from the earliest completion-bearing week
  /// to the latest. For each intermediate week (including weeks with no
  /// completions), check if `requiredDays.every(weekHasDay)`; if yes,
  /// increment run; if no, reset run to 0; track max.
  int _bestWeeklyStreakAllTime(Habit habit, List<HabitCompletion> completions) {
    final requiredDays = habit.weeklyDays;
    if (requiredDays == null || requiredDays.isEmpty) return 0;
    if (completions.isEmpty) return 0;

    // Group: weekKey -> set of weekday indices completed
    // (0=Sun convention matching _calculateWeeklyStreak's `c.completedAt.weekday % 7`)
    final completionsByWeek = <int, Set<int>>{};
    for (final c in completions) {
      final weekKey = _weekNumber(c.completedAt);
      completionsByWeek
          .putIfAbsent(weekKey, () => <int>{})
          .add(c.completedAt.weekday % 7);
    }
    final weekKeys = completionsByWeek.keys.toList()..sort();
    if (weekKeys.isEmpty) return 0;
    final firstWeek = weekKeys.first;
    final lastWeek = weekKeys.last;

    var run = 0;
    var best = 0;
    for (var w = firstWeek; w <= lastWeek; w++) {
      final dayset = completionsByWeek[w] ?? const <int>{};
      if (requiredDays.every(dayset.contains)) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  /// Anchor windows to the EARLIEST completion (so historical edits update
  /// the streak). Iterate forward; increment run on satisfied windows,
  /// reset on unsatisfied; track max.
  int _bestIntervalStreakAllTime(
    Habit habit,
    List<HabitCompletion> completions,
  ) {
    final intervalDays = habit.intervalDays;
    if (intervalDays == null || intervalDays <= 0) return 0;
    if (completions.isEmpty) return 0;

    final completionDates =
        completions
            .map(
              (c) => DateTime(
                c.completedAt.year,
                c.completedAt.month,
                c.completedAt.day,
              ),
            )
            .toSet()
            .toList()
          ..sort();
    if (completionDates.isEmpty) return 0;

    // Anchor at the earliest completion's day.
    var windowStart = completionDates.first;
    final lastDate = completionDates.last;
    var run = 0;
    var best = 0;

    while (!windowStart.isAfter(lastDate)) {
      final windowEnd = windowStart.add(Duration(days: intervalDays - 1));
      final hasInRange = completionDates.any(
        (d) => !d.isBefore(windowStart) && !d.isAfter(windowEnd),
      );
      if (hasInRange) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
      windowStart = windowEnd.add(const Duration(days: 1));
    }
    return best;
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

/// Watches all active habits + completions and reschedules notifications
/// on any change, including sync-driven updates from other devices. Each
/// reschedule respects per-habit current-period completion state so a
/// reminder doesn't fire for a habit that's already done for today (or
/// the current weekly/interval window). Mirrors the
/// [reminderSchedulerListenerProvider] pattern with a 500ms debounce to
/// batch rapid consecutive changes (e.g., bulk sync).
final habitNotificationListenerProvider = Provider<void>((ref) {
  final service = ref.watch(habitNotificationServiceProvider);
  Timer? debounceTimer;
  ref.onDispose(() => debounceTimer?.cancel());

  void scheduleReschedule() {
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 500), () {
      final habits = ref.read(habitsProvider).value;
      if (habits == null) return;
      final todayCompletions =
          ref.read(todayCompletionsProvider).value ?? const [];
      final allCompletions = ref.read(allCompletionsProvider).value ?? const [];
      final now = DateTime.now();
      service
          .rescheduleAll(
            habits,
            skipCurrentPeriodFor: (habit) => isHabitCompletedForCurrentPeriod(
              habit: habit,
              todayCompletions: todayCompletions,
              allCompletions: allCompletions,
              now: now,
            ),
          )
          .catchError((e) {
            debugPrint('Habit notification reschedule failed (non-fatal): $e');
          });
    });
  }

  ref.listen(
    habitsProvider,
    (_, _) => scheduleReschedule(),
    fireImmediately: true,
  );
  ref.listen(todayCompletionsProvider, (_, _) => scheduleReschedule());
  ref.listen(allCompletionsProvider, (_, _) => scheduleReschedule());
});
