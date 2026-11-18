import 'package:flutter/material.dart';
import 'habit_icon_metrics.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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
    final borderRadius = BorderRadius.circular(
      PrismShapes.of(context).radius(PrismTokens.radiusMedium),
    );

    final pills = <Widget>[];
    if (weeklyProgress != null) {
      pills.add(
        Semantics(
          label: context.l10n.habitsWeeklyProgressSemantics(
            weeklyProgress.$1,
            weeklyProgress.$2,
          ),
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
      // Pills only: the 6dp gap belongs to whichever container lays them out (the inline
      // row interleaves it, the stacked wrap owns it as `spacing`), so it can never be
      // counted twice.
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
    // The chip's own 12dp side padding plus the 8dp gap before the chevron.
    const chipPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Material(
      color: onSurface.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: onSurface.withValues(alpha: 0.12),
          width: PrismTokens.hairlineBorderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(
          padding: chipPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Fit from what the chip really renders. The glyph target, the gaps and
              // the chevron are non-shrinkable and the title already ellipsises, so the
              // pills keep today's inline position while they fit beside those pieces and
              // move to their own end-aligned line only when they cannot - at the maximum
              // composed scale a family glyph plus a progress and a multi-digit streak pill
              // overflowed the row by 168/199px.
              final fixed =
                  _chipLeadingExtent(context, habit.icon) +
                  12 + // gap after the leading target
                  8 + // gap before the pills
                  8 + // gap before the chevron
                  24; // chevron
              final pillsWidth = _chipPillsWidth(
                context,
                theme: theme,
                weeklyProgress: weeklyProgress,
                streak: habit.currentStreak,
                pillPadding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
              );
              final fitsInline =
                  pills.isEmpty || fixed + pillsWidth <= constraints.maxWidth;

              final title = Text(
                habit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: onSurface.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              );

              if (fitsInline) {
                // Unchanged default geometry: title ellipsises, pills inline.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    HabitLeadingCircle(
                      habit: habit,
                      color: color,
                      completed: isCompleted,
                      onQuickComplete: onQuickComplete,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: title),
                    if (pills.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      for (var i = 0; i < pills.length; i++) ...[
                        if (i > 0) const SizedBox(width: _chipPillGap),
                        pills[i],
                      ],
                    ],
                    const SizedBox(width: 8),
                    chevron,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      HabitLeadingCircle(
                        habit: habit,
                        color: color,
                        completed: isCompleted,
                        onQuickComplete: onQuickComplete,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      chevron,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: _chipPillGap,
                    runSpacing: 2,
                    children: pills,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Gap between the chip's metadata pills.
///
/// Used by both containers - the inline row interleaves a `SizedBox` of this width and the
/// stacked `Wrap` owns it as `spacing` - so the visual gap is identical in both layouts.
const double _chipPillGap = 6;

/// Width of one side of a pill's border.
///
/// `PrismPill` draws `Border.all(...)`, whose `BorderSide` width defaults to 1, so a pill
/// is two pixels wider and taller than its content. The chip's fit budget has to include
/// those two pixels per pill; no appearance changes.
const double _pillBorderSide = 1;

/// Extent of the chip's leading completion target for [icon].
///
/// Shared by [HabitLeadingCircle] (which paints it) and [HabitChip] (which decides
/// whether the metadata still fits beside it), so the two can never drift. The
/// glyph keeps its requested size; only the circle grows around it.
double _chipLeadingExtent(BuildContext context, String? icon) =>
    habitIconExtent(context, icon, fontSize: 18, minimum: 36) + 8;

/// Width of the metadata pills [HabitChip] may place beside the title.
double _chipPillsWidth(
  BuildContext context, {
  required ThemeData theme,
  required (int completed, int total)? weeklyProgress,
  required int streak,
  required EdgeInsets pillPadding,
}) {
  // Exactly the style `PrismPill` paints its label with: labelMedium, w700, height 1.
  final labelStyle = theme.textTheme.labelMedium?.copyWith(
    fontWeight: FontWeight.w700,
    height: 1,
  );
  var width = 0.0;
  var count = 0;
  if (weeklyProgress != null) {
    width += _chipPillWidth(
      context,
      '${weeklyProgress.$1}/${weeklyProgress.$2}',
      labelStyle,
      pillPadding,
    );
    count++;
  }
  if (streak > 0) {
    if (count > 0) width += _chipPillGap;
    width += _chipPillWidth(context, '$streak', labelStyle, pillPadding);
  }
  return width;
}

/// Width one pill occupies: its label as `PrismPill` paints it, plus the 14dp icon,
/// the 6dp icon gap and the pill's own horizontal padding.
///
/// [style] is the style handed to the pill's `Text`; [prismTextStyleForMeasurement]
/// applies the ambient merge and the bold-text flag exactly as `Text` does, and the
/// painter receives the inherited locale and height behaviour, so the measured pill and
/// the painted pill resolve the same face.
double _chipPillWidth(
  BuildContext context,
  String label,
  TextStyle? style,
  EdgeInsets padding,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  // 14dp icon + 6dp gap + the pill's own horizontal padding + both border sides.
  final width =
      painter.width + 14 + 6 + padding.horizontal + (_pillBorderSide * 2);
  painter.dispose();
  return width;
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
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final shapes = PrismShapes.of(context);
    // One measurement drives both the circle and the target (see
    // [_chipLeadingExtent]), so HabitChip's fit decision and this paint agree.
    final targetExtent = _chipLeadingExtent(context, habit.icon);
    final circleExtent = targetExtent - 8;

    return Semantics(
      button: true,
      enabled: onQuickComplete != null,
      label: completed
          ? context.l10n.habitsChipCompletedSemantics(habit.name)
          : context.l10n.habitsChipCompleteSemantics(habit.name),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onQuickComplete,
        child: SizedBox(
          width: targetExtent,
          height: targetExtent,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              width: circleExtent,
              height: circleExtent,
              decoration: BoxDecoration(
                shape: shapes.avatarShape(),
                borderRadius: shapes.avatarBorderRadius(),
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
                        key: ValueKey('habit-chip-icon-${habit.icon}'),
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
