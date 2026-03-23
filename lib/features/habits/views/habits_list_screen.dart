import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/widgets/habit_row.dart';
import 'package:prism_plurality/features/habits/views/add_edit_habit_sheet.dart';
import 'package:prism_plurality/features/habits/views/complete_habit_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

class HabitsListScreen extends ConsumerWidget {
  const HabitsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final todayAsync = ref.watch(todayCompletionsProvider);
    final weeklyAsync = ref.watch(weeklyCompletionsProvider);

    return Scaffold(
      body: habitsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (habits) {
          final completions = todayAsync.value ?? <HabitCompletion>[];
          final weeklyCompletions = weeklyAsync.value ?? <HabitCompletion>[];
          final completedHabitIds =
              completions.map((c) => c.habitId).toSet();
          // Pre-index weekly completions by habitId for O(1) lookup in rows.
          final weeklyByHabit = <String, List<HabitCompletion>>{};
          for (final c in weeklyCompletions) {
            (weeklyByHabit[c.habitId] ??= []).add(c);
          }

          final today = <Habit>[];
          final upcoming = <Habit>[];
          final inactive = <Habit>[];

          for (final habit in habits) {
            if (!habit.isActive) {
              inactive.add(habit);
            } else if (_isDueToday(habit, completions)) {
              today.add(habit);
            } else {
              upcoming.add(habit);
            }
          }

          return CustomScrollView(
            physics: habits.isEmpty
                ? const NeverScrollableScrollPhysics()
                : null,
            slivers: [
              SliverPinnedTopBar(
                child: PrismTopBar(
                  title: 'Habits',
                  trailing: PrismTopBarAction(
                    icon: Icons.add,
                    tooltip: 'Create habit',
                    onPressed: () => _showAddHabit(context),
                  ),
                ),
              ),
              if (habits.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No habits yet',
                    subtitle:
                        'Create habits to track daily routines, self-care, or anything your system wants to keep up with.',
                    actionLabel: 'Create Habit',
                    actionIcon: Icons.add,
                    onAction: () => _showAddHabit(context),
                  ),
                )
              else ...[
                if (today.isNotEmpty)
                  _HabitSection(
                    title: 'Today',
                    habits: today,
                    completions: completions,
                    completedHabitIds: completedHabitIds,
                    weeklyByHabit: weeklyByHabit,
                    isDueSection: true,
                    onTap: (h) => context.go(AppRoutePaths.habit(h.id)),
                    onQuickComplete: (h) => _showCompleteSheet(context, ref, h),
                  ),
                if (upcoming.isNotEmpty)
                  _HabitSection(
                    title: 'Upcoming',
                    habits: upcoming,
                    completions: completions,
                    completedHabitIds: completedHabitIds,
                    weeklyByHabit: weeklyByHabit,
                    onTap: (h) => context.go(AppRoutePaths.habit(h.id)),
                    onQuickComplete: (h) => _showCompleteSheet(context, ref, h),
                  ),
                if (inactive.isNotEmpty)
                  _HabitSection(
                    title: 'Inactive',
                    habits: inactive,
                    completions: completions,
                    completedHabitIds: completedHabitIds,
                    weeklyByHabit: weeklyByHabit,
                    onTap: (h) => context.go(AppRoutePaths.habit(h.id)),
                    onQuickComplete: (h) => _showCompleteSheet(context, ref, h),
                  ),
              ],
              SliverPadding(
                padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isDueToday(Habit habit, List<HabitCompletion> completions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final completedToday = completions.any((c) => c.habitId == habit.id);

    switch (habit.frequency) {
      case HabitFrequency.daily:
        return true;
      case HabitFrequency.weekly:
        if (habit.weeklyDays == null) return false;
        final todayWeekday = now.weekday % 7; // 0=Sun
        return habit.weeklyDays!.contains(todayWeekday);
      case HabitFrequency.interval:
        if (habit.intervalDays == null) return true;
        final habitCompletions = completions
            .where((c) => c.habitId == habit.id)
            .toList();
        if (habitCompletions.isEmpty) return true;
        final lastCompletion = habitCompletions.reduce(
          (a, b) => a.completedAt.isAfter(b.completedAt) ? a : b,
        );
        final daysSince = todayStart
            .difference(
              DateTime(
                lastCompletion.completedAt.year,
                lastCompletion.completedAt.month,
                lastCompletion.completedAt.day,
              ),
            )
            .inDays;
        return daysSince >= habit.intervalDays!;
      case HabitFrequency.custom:
        return !completedToday;
    }
  }

  void _showAddHabit(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddEditHabitSheet(
        scrollController: scrollController,
      ),
    );
  }

  void _showCompleteSheet(BuildContext context, WidgetRef ref, Habit habit) {
    final completions = ref.read(todayCompletionsProvider).value ?? [];
    final alreadyCompleted = completions.any((c) => c.habitId == habit.id);

    if (alreadyCompleted) {
      // Uncomplete: find the completion and remove it
      final completion = completions.firstWhere((c) => c.habitId == habit.id);
      ref
          .read(habitNotifierProvider.notifier)
          .uncompleteHabit(habitId: habit.id, completionId: completion.id);
      return;
    }

    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) => CompleteHabitSheet(habit: habit, scrollController: sc),
    );
  }
}

class _HabitSection extends StatelessWidget {
  const _HabitSection({
    required this.title,
    required this.habits,
    required this.completions,
    required this.completedHabitIds,
    required this.weeklyByHabit,
    required this.onTap,
    required this.onQuickComplete,
    this.isDueSection = false,
  });

  final String title;
  final List<Habit> habits;
  final List<HabitCompletion> completions;
  final Set<String> completedHabitIds;
  final Map<String, List<HabitCompletion>> weeklyByHabit;
  final bool isDueSection;
  final void Function(Habit) onTap;
  final void Function(Habit) onQuickComplete;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: UnconstrainedBox(
              child: TintedGlassSurface(
                borderRadius: BorderRadius.circular(999),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: habits.length,
          itemBuilder: (context, index) {
            final habit = habits[index];
            final isCompleted = completedHabitIds.contains(habit.id);
            final showsBanner =
                isDueSection && !isCompleted;
            return PrismSectionCard(
              margin: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              padding: showsBanner
                  ? const EdgeInsets.only(top: 6)
                  : const EdgeInsets.symmetric(vertical: 6),
              tone: isCompleted
                  ? PrismSurfaceTone.subtle
                  : PrismSurfaceTone.strong,
              onTap: () => onTap(habit),
              child: HabitRow(
                habit: habit,
                todayCompletions: completions,
                weeklyCompletions:
                    weeklyByHabit[habit.id] ?? const [],
                isDueToday: isDueSection,
                isCompletedToday:
                    completedHabitIds.contains(habit.id),
                onQuickComplete: () => onQuickComplete(habit),
              ),
            );
          },
        ),
      ],
    );
  }
}
