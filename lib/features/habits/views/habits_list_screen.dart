import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/utils/habit_due.dart';
import 'package:prism_plurality/features/habits/widgets/habit_row.dart';
import 'package:prism_plurality/features/habits/widgets/today_habits_container.dart';
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
import 'package:prism_plurality/shared/theme/app_icons.dart';

class HabitsListScreen extends ConsumerWidget {
  const HabitsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final todayAsync = ref.watch(todayCompletionsProvider);
    final allCompletionsAsync = ref.watch(allCompletionsProvider);
    final weeklyAsync = ref.watch(weeklyCompletionsProvider);

    return Scaffold(
      body: habitsAsync.when(
        skipLoadingOnReload: true,
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (habits) {
          final todayCompletions = todayAsync.value ?? <HabitCompletion>[];
          final allCompletions =
              allCompletionsAsync.value ?? <HabitCompletion>[];
          final weeklyCompletions = weeklyAsync.value ?? <HabitCompletion>[];
          final completedHabitIds = todayCompletions
              .map((c) => c.habitId)
              .toSet();
          // Pre-index weekly completions by habitId for O(1) lookup in rows.
          final weeklyByHabit = <String, List<HabitCompletion>>{};
          for (final c in weeklyCompletions) {
            (weeklyByHabit[c.habitId] ??= []).add(c);
          }

          final due = <Habit>[];
          final complete = <Habit>[];
          final upcoming = <Habit>[];
          final inactive = <Habit>[];

          final now = ref.watch(currentDateProvider);
          for (final habit in habits) {
            if (!habit.isActive) {
              inactive.add(habit);
              continue;
            }
            final isDue = isHabitDueToday(
              habit: habit,
              todayCompletions: todayCompletions,
              allCompletions: allCompletions,
              now: now,
            );
            final completedToday = completedHabitIds.contains(habit.id);
            // Completed always wins — a completed-and-still-due habit lives
            // in the Complete section, not Due.
            if (completedToday) {
              complete.add(habit);
            } else if (isDue) {
              due.add(habit);
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
                    icon: AppIcons.add,
                    tooltip: 'Create habit',
                    onPressed: () => _showAddHabit(context),
                  ),
                ),
              ),
              if (habits.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icon(AppIcons.checkCircleOutline),
                    title: 'No habits yet',
                    subtitle:
                        'Create habits to track daily routines, self-care, or anything your system wants to keep up with.',
                    actionLabel: 'Create Habit',
                    actionIcon: AppIcons.add,
                    onAction: () => _showAddHabit(context),
                  ),
                )
              else ...[
                if (due.isNotEmpty || complete.isNotEmpty)
                  TodayHabitsContainer(
                    due: due,
                    complete: complete,
                    todayCompletions: todayCompletions,
                    weeklyByHabit: weeklyByHabit,
                    onTap: (h) => context.go(AppRoutePaths.habit(h.id)),
                    onQuickComplete: (h) =>
                        _showCompleteSheet(context, ref, h),
                  ),
                if (upcoming.isNotEmpty)
                  _HabitSection(
                    title: 'Upcoming',
                    habits: upcoming,
                    completions: todayCompletions,
                    completedHabitIds: completedHabitIds,
                    weeklyByHabit: weeklyByHabit,
                    onTap: (h) => context.go(AppRoutePaths.habit(h.id)),
                    onQuickComplete: (h) => _showCompleteSheet(context, ref, h),
                  ),
                if (inactive.isNotEmpty)
                  _HabitSection(
                    title: 'Inactive',
                    habits: inactive,
                    completions: todayCompletions,
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

  void _showAddHabit(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          AddEditHabitSheet(scrollController: scrollController),
    );
  }

  Future<void> _showCompleteSheet(
    BuildContext context,
    WidgetRef ref,
    Habit habit,
  ) async {
    final completions = ref.read(todayCompletionsProvider).value ?? [];
    final alreadyCompleted = completions.any((c) => c.habitId == habit.id);

    if (alreadyCompleted) {
      // Uncomplete: remove ALL completion rows for this habit on the current
      // day. In normal use there is at most one, but duplicates are possible
      // from rapid taps, sync merges, or imports — clearing them all keeps
      // the habit from appearing to re-complete itself on the next stream
      // emission. Await so the TodayHabitsContainer's rapid-tap debounce can
      // gate duplicate calls end-to-end.
      final habitCompletions =
          completions.where((c) => c.habitId == habit.id).toList();
      for (final completion in habitCompletions) {
        await ref
            .read(habitNotifierProvider.notifier)
            .uncompleteHabit(habitId: habit.id, completionId: completion.id);
      }
      return;
    }

    await PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) =>
          CompleteHabitSheet(habit: habit, scrollController: sc),
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
  });

  final String title;
  final List<Habit> habits;
  final List<HabitCompletion> completions;
  final Set<String> completedHabitIds;
  final Map<String, List<HabitCompletion>> weeklyByHabit;
  final void Function(Habit) onTap;
  final Future<void> Function(Habit) onQuickComplete;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
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
            return PrismSectionCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              tone: isCompleted
                  ? PrismSurfaceTone.subtle
                  : PrismSurfaceTone.strong,
              onTap: () => onTap(habit),
              child: HabitRow(
                habit: habit,
                todayCompletions: completions,
                weeklyCompletions: weeklyByHabit[habit.id] ?? const [],
                isCompletedToday: isCompleted,
                onQuickComplete: () => onQuickComplete(habit),
              ),
            );
          },
        ),
      ],
    );
  }
}
