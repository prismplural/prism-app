import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';


/// A single habit row with completion circle, name, frequency, streak,
/// weekly progress pill, and optional "Task Due" banner.
class HabitRow extends StatefulWidget {
  const HabitRow({
    super.key,
    required this.habit,
    required this.todayCompletions,
    this.weeklyCompletions = const [],
    this.isDueToday = false,
    this.isCompletedToday = false,
    this.onTap,
    this.onQuickComplete,
  });

  final Habit habit;
  final List<HabitCompletion> todayCompletions;
  final List<HabitCompletion> weeklyCompletions;
  final bool isDueToday;
  final bool isCompletedToday;
  final VoidCallback? onTap;
  final VoidCallback? onQuickComplete;

  @override
  State<HabitRow> createState() => _HabitRowState();
}

class _HabitRowState extends State<HabitRow> {
  bool _isCompleting = false;

  bool get _isCompletedToday =>
      widget.isCompletedToday ||
      widget.todayCompletions.any((c) => c.habitId == widget.habit.id);

  Color _habitColor(BuildContext context) {
    if (widget.habit.colorHex != null && widget.habit.colorHex!.isNotEmpty) {
      final hex = widget.habit.colorHex!.replaceFirst('#', '');
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        return Color(0xFF000000 | value);
      }
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// For weekly-frequency habits, calculate completed/total days this week.
  (int completed, int total)? _weeklyProgress() {
    final habit = widget.habit;
    if (habit.frequency != HabitFrequency.weekly) return null;
    if (habit.weeklyDays == null || habit.weeklyDays!.isEmpty) return null;

    final total = habit.weeklyDays!.length;
    // weeklyCompletions is already filtered to this habit by the parent.
    final completedDays = <int>{};
    for (final c in widget.weeklyCompletions) {
      completedDays.add(c.completedAt.weekday % 7); // 0=Sun
    }
    final completed =
        habit.weeklyDays!.where(completedDays.contains).length;
    return (completed, total);
  }

  bool get _showBanner =>
      widget.isDueToday && !_isCompletedToday;

  @override
  void didUpdateWidget(HabitRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset loading state when completion status changes (stream rebuild).
    if (_isCompleting && widget.isCompletedToday != oldWidget.isCompletedToday) {
      _isCompleting = false;
    }
  }

  void _handleQuickComplete() {
    if (_isCompleting || widget.onQuickComplete == null) return;
    setState(() => _isCompleting = true);
    widget.onQuickComplete!();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _habitColor(context);
    final completed = _isCompletedToday;
    final weeklyProgress = _weeklyProgress();

    final row = PrismListRow(
      leading: Semantics(
        button: true,
        label: completed
            ? '${widget.habit.name}, completed'
            : 'Complete ${widget.habit.name}',
        child: GestureDetector(
          onTap: widget.onQuickComplete,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                      border: Border.all(color: color, width: 2.5),
                    ),
                    child: widget.habit.icon != null
                        ? Center(
                            child: Text(
                              widget.habit.icon!,
                              style: const TextStyle(fontSize: 20),
                            ),
                          )
                        : Icon(Icons.circle_outlined,
                            size: 20, color: color.withValues(alpha: 0.4)),
                  ),
                ),
                if (completed)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      title: Text(widget.habit.name),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrismPill(
            icon: Icons.calendar_today,
            label: widget.habit.frequency == HabitFrequency.interval &&
                    widget.habit.intervalDays != null
                ? 'Every ${widget.habit.intervalDays} days'
                : widget.habit.frequency.label,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          ),
          if (completed) ...[
            const SizedBox(width: 8),
            const PrismPill(
              icon: Icons.check_circle,
              label: 'Complete',
              color: Colors.green,
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            ),
          ],
          if (weeklyProgress != null) ...[
            const SizedBox(width: 8),
            Semantics(
              label:
                  '${weeklyProgress.$1} of ${weeklyProgress.$2} days completed this week',
              child: PrismPill(
                icon: Icons.check,
                label: '${weeklyProgress.$1}/${weeklyProgress.$2}',
                color: color,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              ),
            ),
          ],
          if (widget.habit.currentStreak > 0) ...[
            const SizedBox(width: 8),
            PrismPill(
              icon: Icons.local_fire_department,
              label: '${widget.habit.currentStreak}',
              color: Colors.orange.shade700,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            ),
          ],
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );

    if (!_showBanner) return row;

    // Task Due banner with tinted background to stand out from the card.
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          TintedGlassSurface(
            borderWidth: 0,
            tint: color,
            borderRadius: BorderRadius.zero,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text(
                  'Task Due',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                PrismButton(
                  tone: PrismButtonTone.filled,
                  density: PrismControlDensity.compact,
                  label: 'Complete',
                  icon: Icons.check,
                  isLoading: _isCompleting,
                  semanticLabel: 'Complete ${widget.habit.name}',
                  onPressed: _handleQuickComplete,
                ),
              ],
            ),
          ),
        ],
    );
  }
}
