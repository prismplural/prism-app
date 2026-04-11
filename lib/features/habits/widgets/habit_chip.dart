import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';

/// A compact one-line habit chip used by the Today section split.
///
/// Layout: `[leading circle][12 gap][Expanded(title)][pills][8 gap][chevron]`.
/// There is no stacked subtitle row — the streak pill and optional weekly
/// progress pill sit inline next to the title. If neither is present, the
/// right side of the row contains only the chevron.
///
/// This widget is reused by:
///   • `TodayHabitsContainer`'s Due section (active chips on the mauve wash)
///   • The Complete section (dimmed chips rendered below the container)
///
/// [HabitRow] remains the canonical stacked row for Upcoming / Inactive
/// sections — do not replace it here.
class HabitChip extends StatelessWidget {
  const HabitChip({
    super.key,
    required this.habit,
    required this.todayCompletions,
    this.weeklyCompletions = const [],
    this.completed = false,
    this.onTap,
    this.onQuickComplete,
  });

  final Habit habit;
  final List<HabitCompletion> todayCompletions;
  final List<HabitCompletion> weeklyCompletions;

  /// Whether this chip should render in the completed state (filled circle
  /// with a check). When the container dims via `AnimatedOpacity`, the chip
  /// itself does not need to inspect completion state — the parent passes
  /// the correct value.
  final bool completed;

  /// Row-body tap (navigates to detail).
  final VoidCallback? onTap;

  /// Leading-circle tap (toggles completion). A `null` value reports the
  /// leading control as `enabled: false` via Semantics — used by parents
  /// to debounce rapid taps.
  final Future<void> Function()? onQuickComplete;

  bool get _isCompletedToday =>
      completed || todayCompletions.any((c) => c.habitId == habit.id);

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

  (int completed, int total)? _weeklyProgress() {
    if (habit.frequency != HabitFrequency.weekly) return null;
    if (habit.weeklyDays == null || habit.weeklyDays!.isEmpty) return null;

    final total = habit.weeklyDays!.length;
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
    final isCompleted = _isCompletedToday;
    final weeklyProgress = _weeklyProgress();
    final onSurface = theme.colorScheme.onSurface;

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
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          ),
        ),
      );
    }
    if (habit.currentStreak > 0) {
      if (pills.isNotEmpty) pills.add(const SizedBox(width: 6));
      pills.add(
        PrismPill(
          icon: AppIcons.localFireDepartment,
          label: '${habit.currentStreak}',
          color: Colors.orange.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        ),
      );
    }

    final chevron = Icon(
      AppIcons.chevronRightRounded,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
    );

    return Material(
      color: onSurface.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PrismTokens.radiusMedium),
        side: BorderSide(
          color: onSurface.withValues(alpha: 0.12),
          width: PrismTokens.hairlineBorderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PrismTokens.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              HabitLeadingCircle(
                habit: habit,
                color: color,
                completed: isCompleted,
                onQuickComplete: onQuickComplete,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onSurface.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (pills.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...pills,
              ],
              const SizedBox(width: 8),
              chevron,
            ],
          ),
        ),
      ),
    );
  }
}

/// The leading completion circle used by [HabitChip]. Extracted so the
/// tap-target logic is owned in one place. A `null` `onQuickComplete`
/// reports the control as `enabled: false` via Semantics — used by
/// parents to debounce rapid taps.
class HabitLeadingCircle extends StatelessWidget {
  const HabitLeadingCircle({
    super.key,
    required this.habit,
    required this.color,
    required this.completed,
    this.onQuickComplete,
  });

  final Habit habit;
  final Color color;
  final bool completed;
  final Future<void> Function()? onQuickComplete;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

    return Semantics(
      button: true,
      enabled: onQuickComplete != null,
      label:
          completed ? '${habit.name}, completed' : 'Complete ${habit.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onQuickComplete,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Tinted fill for incomplete, full fill when completed —
                // the AnimatedContainer animates the alpha smoothly.
                color: completed ? color : color.withValues(alpha: 0.15),
              ),
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: completed
                    ? Icon(
                        AppIcons.check,
                        key: const ValueKey('habit-chip-check'),
                        size: 18,
                        color: AppColors.warmWhite,
                      )
                    : habit.icon != null
                        ? Center(
                            key: ValueKey(
                                'habit-chip-icon-${habit.icon}'),
                            child: Text(
                              habit.icon!,
                              style: const TextStyle(fontSize: 18),
                            ),
                          )
                        : Icon(
                            AppIcons.circleOutlined,
                            key: const ValueKey('habit-chip-outline'),
                            size: 18,
                            color: color.withValues(alpha: 0.6),
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
