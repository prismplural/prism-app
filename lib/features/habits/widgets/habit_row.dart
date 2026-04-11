import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';

/// A single habit row with completion circle, name, optional weekly
/// progress pill, and optional streak pill.
///
/// The "due today" visual state is owned by the containing
/// `TodayHabitsContainer` — this row no longer shows a per-row "Task Due"
/// banner, frequency pill, or "Complete" status pill. Instead, the leading
/// circle is a tinted tap target that fills with the habit's color + a
/// white check when the habit is completed today, and the container dims
/// the whole chip via `AnimatedOpacity`.
class HabitRow extends StatelessWidget {
  const HabitRow({
    super.key,
    required this.habit,
    required this.todayCompletions,
    this.weeklyCompletions = const [],
    this.isCompletedToday = false,
    this.onTap,
    this.onQuickComplete,
  });

  final Habit habit;
  final List<HabitCompletion> todayCompletions;
  final List<HabitCompletion> weeklyCompletions;
  final bool isCompletedToday;
  final VoidCallback? onTap;
  final Future<void> Function()? onQuickComplete;

  bool get _isCompletedToday =>
      isCompletedToday || todayCompletions.any((c) => c.habitId == habit.id);

  Color _habitColor(BuildContext context) {
    if (habit.colorHex != null && habit.colorHex!.isNotEmpty) {
      final hex = habit.colorHex!.replaceFirst('#', '');
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        return Color(0xFF000000 | value);
      }
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// For weekly-frequency habits, calculate completed/total days this week.
  (int completed, int total)? _weeklyProgress() {
    if (habit.frequency != HabitFrequency.weekly) return null;
    if (habit.weeklyDays == null || habit.weeklyDays!.isEmpty) return null;

    final total = habit.weeklyDays!.length;
    // weeklyCompletions is already filtered to this habit by the parent.
    final completedDays = <int>{};
    for (final c in weeklyCompletions) {
      completedDays.add(c.completedAt.weekday % 7); // 0=Sun
    }
    final completed = habit.weeklyDays!.where(completedDays.contains).length;
    return (completed, total);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _habitColor(context);
    final completed = _isCompletedToday;
    final weeklyProgress = _weeklyProgress();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final circleDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

    // Build the subtitle pill list. Frequency is no longer shown — only
    // weekly progress (if weekly-frequency) and streak (if > 0). If
    // neither is present, the subtitle is null and the title vertically
    // centers within the row.
    final pills = <Widget>[];
    if (weeklyProgress != null) {
      pills.add(
        Semantics(
          label:
              '${weeklyProgress.$1} of ${weeklyProgress.$2} days completed this week',
          child: PrismPill(
            icon: AppIcons.check,
            label: '${weeklyProgress.$1}/${weeklyProgress.$2}',
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          ),
        ),
      );
    }
    if (habit.currentStreak > 0) {
      if (pills.isNotEmpty) pills.add(const SizedBox(width: 8));
      pills.add(
        PrismPill(
          icon: AppIcons.localFireDepartment,
          label: '${habit.currentStreak}',
          color: Colors.orange.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        ),
      );
    }
    final Widget? subtitle = pills.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: pills);

    return PrismListRow(
      onTap: onTap,
      leading: Semantics(
        button: true,
        enabled: onQuickComplete != null,
        label: completed
            ? '${habit.name}, completed'
            : 'Complete ${habit.name}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onQuickComplete,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: circleDuration,
                curve: Curves.easeOut,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Tinted fill for incomplete ("tap to finish" affordance),
                  // full fill for completed. No border in either state —
                  // the 240ms AnimatedContainer smoothly animates the
                  // alpha from 0.15 tint to full color.
                  color: completed ? color : color.withValues(alpha: 0.15),
                ),
                child: AnimatedSwitcher(
                  duration: circleDuration,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                  ),
                  child: completed
                      ? Icon(
                          AppIcons.check,
                          key: const ValueKey('habit-row-check'),
                          size: 22,
                          color: AppColors.warmWhite,
                        )
                      : habit.icon != null
                          ? Center(
                              key: ValueKey('habit-row-icon-${habit.icon}'),
                              child: Text(
                                habit.icon!,
                                style: const TextStyle(fontSize: 20),
                              ),
                            )
                          : Icon(
                              AppIcons.circleOutlined,
                              key: const ValueKey('habit-row-outline'),
                              size: 20,
                              color: color.withValues(alpha: 0.6),
                            ),
                ),
              ),
            ),
          ),
        ),
      ),
      title: Text(habit.name),
      subtitle: subtitle,
      trailing: Icon(
        AppIcons.chevronRightRounded,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}
