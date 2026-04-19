import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/features/habits/widgets/habit_chip.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// The "today" presentation for the habits list, owning both the mauve
/// Due container and the Complete section below it.
///
/// Splits today's habits into two visual regions:
///
/// * **Due** — incomplete habits for today, rendered as compact [HabitChip]s
///   inside a mauve-wash container with a centered `Today` header (no
///   progress counter — completed habits live in the Complete section
///   below and shouldn't be counted in a control the user can't see into).
///   When `due.isEmpty && complete.isNotEmpty`, the container enters a
///   "collapsed all-done" mode: a single compact mauve pill reading
///   `Today · all done`. The transition between full and collapsed is
///   animated via [AnimatedSize] + [AnimatedSwitcher].
///
/// * **Complete** — completed-today habits, rendered as dimmed compact
///   chips beneath a section pill header labelled "Complete". This section
///   is NOT inside the mauve wash; it renders as a plain list section.
///
/// The widget returns a [SliverMainAxisGroup] so the parent can drop it
/// directly into a `CustomScrollView`'s slivers list.
///
/// A single `_tapping` set debounces rapid taps across BOTH the Due chips
/// and the Complete chips. While a habit id is in the set, its leading
/// control is disabled via Semantics (`enabled: false`).
class TodayHabitsContainer extends ConsumerStatefulWidget {
  const TodayHabitsContainer({
    super.key,
    required this.due,
    required this.complete,
    required this.todayCompletions,
    required this.weeklyByHabit,
    required this.onTap,
    required this.onQuickComplete,
  });

  /// Habits that are due today and NOT yet completed.
  final List<Habit> due;

  /// Habits that were completed today. Ordered by the parent; this widget
  /// sorts by latest completion timestamp DESC internally.
  final List<Habit> complete;

  final List<HabitCompletion> todayCompletions;
  final Map<String, List<HabitCompletion>> weeklyByHabit;
  final void Function(Habit) onTap;
  final Future<void> Function(Habit) onQuickComplete;

  @override
  ConsumerState<TodayHabitsContainer> createState() =>
      _TodayHabitsContainerState();
}

class _TodayHabitsContainerState extends ConsumerState<TodayHabitsContainer> {
  /// Habit ids currently mid-completion. Used to debounce rapid double-taps
  /// so we don't open two complete sheets or enqueue two uncomplete calls
  /// for the same habit. While a habit id is in this set, its chip's
  /// `onQuickComplete` is passed as `null` so the leading control reports
  /// `enabled: false` via Semantics during in-flight submission.
  final Set<String> _tapping = <String>{};

  Future<void> _handleTap(Habit habit) async {
    if (_tapping.contains(habit.id)) return;
    setState(() => _tapping.add(habit.id));
    try {
      await widget.onQuickComplete(habit);
    } finally {
      if (mounted) {
        setState(() => _tapping.remove(habit.id));
      }
    }
  }

  /// Returns the `complete` list sorted by latest completion DESC. The
  /// parent passes habits in arbitrary order; we collapse duplicate rows
  /// defensively.
  List<Habit> _sortedComplete() {
    if (widget.complete.isEmpty) return const [];
    final latestByHabit = <String, DateTime>{};
    for (final c in widget.todayCompletions) {
      final existing = latestByHabit[c.habitId];
      if (existing == null || c.completedAt.isAfter(existing)) {
        latestByHabit[c.habitId] = c.completedAt;
      }
    }
    final sorted = List<Habit>.of(widget.complete);
    sorted.sort((a, b) {
      final ad = latestByHabit[a.id];
      final bd = latestByHabit[b.id];
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final effectsMode = VisualEffectsModeX.of(context, ref);
    final isAccessible = effectsMode == VisualEffectsMode.accessible;
    final completedOpacity = isAccessible ? 0.65 : 0.45;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final sortedComplete = _sortedComplete();
    final hasDue = widget.due.isNotEmpty;
    final hasComplete = sortedComplete.isNotEmpty;

    // Nothing to render.
    if (!hasDue && !hasComplete) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _DueContainer(
          key: const Key('today-due-container'),
          due: widget.due,
          allDoneMode: !hasDue && hasComplete,
          todayCompletions: widget.todayCompletions,
          weeklyByHabit: widget.weeklyByHabit,
          reduceMotion: reduceMotion,
          tappingHabits: _tapping,
          onTap: widget.onTap,
          onLeadingTap: _handleTap,
        ),
      ),
    ];

    if (hasComplete) {
      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _SectionPillHeader(title: context.l10n.habitsSectionComplete),
            ),
            SliverList.builder(
              itemCount: sortedComplete.length,
              itemBuilder: (context, index) {
                final habit = sortedComplete[index];
                final isBusy = _tapping.contains(habit.id);
                return Padding(
                  key: ValueKey('today-complete-${habit.id}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  child: AnimatedOpacity(
                    opacity: completedOpacity,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    child: HabitChip(
                      habit: habit,
                      todayCompletions: widget.todayCompletions,
                      weeklyCompletions:
                          widget.weeklyByHabit[habit.id] ?? const [],
                      completed: true,
                      onTap: () => widget.onTap(habit),
                      onQuickComplete:
                          isBusy ? null : () => _handleTap(habit),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }

    return SliverMainAxisGroup(slivers: slivers);
  }
}

/// The mauve-wash Due container. When [allDoneMode] is true, it renders a
/// single compact pill ("Today · all done") instead of the full header +
/// chips layout. The size change is animated via [AnimatedSize] and the
/// content cross-fades via [AnimatedSwitcher].
class _DueContainer extends ConsumerWidget {
  const _DueContainer({
    super.key,
    required this.due,
    required this.allDoneMode,
    required this.todayCompletions,
    required this.weeklyByHabit,
    required this.reduceMotion,
    required this.tappingHabits,
    required this.onTap,
    required this.onLeadingTap,
  });

  final List<Habit> due;
  final bool allDoneMode;
  final List<HabitCompletion> todayCompletions;
  final Map<String, List<HabitCompletion>> weeklyByHabit;
  final bool reduceMotion;
  final Set<String> tappingHabits;
  final void Function(Habit) onTap;
  final Future<void> Function(Habit) onLeadingTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final effectsMode = VisualEffectsModeX.of(context, ref);
    final isAccessible = effectsMode == VisualEffectsMode.accessible;
    final isDark = theme.brightness == Brightness.dark;

    // Container fill + border alpha values per mode/theme.
    final fillAlpha = isAccessible
        ? (isDark ? 0.18 : 0.14)
        : (isDark ? 0.12 : 0.08);
    final borderAlpha = isAccessible ? 0.24 : 0.16;
    final primary = theme.colorScheme.primary;

    final semanticsLabel =
        allDoneMode ? context.l10n.habitsTodayAllDoneSemantics : context.l10n.habitsTodaySemantics;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Semantics(
        container: true,
        label: semanticsLabel,
        child: Container(
          decoration: BoxDecoration(
            color: primary.withValues(alpha: fillAlpha),
            borderRadius: BorderRadius.circular(PrismTokens.radiusLarge),
            border: Border.all(
              color: primary.withValues(alpha: borderAlpha),
              width: PrismTokens.hairlineBorderWidth,
            ),
          ),
          child: AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: allDoneMode
                  ? const _CollapsedAllDone(
                      key: ValueKey('today-due-collapsed'),
                    )
                  : _FullDueContent(
                      key: const ValueKey('today-due-full'),
                      due: due,
                      todayCompletions: todayCompletions,
                      weeklyByHabit: weeklyByHabit,
                      tappingHabits: tappingHabits,
                      onTap: onTap,
                      onLeadingTap: onLeadingTap,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full mode: centered `Today` title (no progress counter) + list of due
/// chips.
class _FullDueContent extends StatelessWidget {
  const _FullDueContent({
    super.key,
    required this.due,
    required this.todayCompletions,
    required this.weeklyByHabit,
    required this.tappingHabits,
    required this.onTap,
    required this.onLeadingTap,
  });

  final List<Habit> due;
  final List<HabitCompletion> todayCompletions;
  final Map<String, List<HabitCompletion>> weeklyByHabit;
  final Set<String> tappingHabits;
  final void Function(Habit) onTap;
  final Future<void> Function(Habit) onLeadingTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
    );

    final rows = <Widget>[];
    for (var i = 0; i < due.length; i++) {
      final habit = due[i];
      final isBusy = tappingHabits.contains(habit.id);
      rows.add(
        KeyedSubtree(
          key: ValueKey('today-due-${habit.id}'),
          child: HabitChip(
            habit: habit,
            todayCompletions: todayCompletions,
            weeklyCompletions: weeklyByHabit[habit.id] ?? const [],
            completed: false,
            onTap: () => onTap(habit),
            onQuickComplete:
                isBusy ? null : () => onLeadingTap(habit),
          ),
        ),
      );
      if (i < due.length - 1) {
        rows.add(const SizedBox(height: 10));
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  context.l10n.habitsTodayHeader,
                  style: headerStyle,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        ],
      ),
    );
  }
}

/// Collapsed mode: a single compact row reading `Today · all done`. This
/// is the celebration moment when every due habit is complete; the middot
/// and "all done" copy are kept because the full-state header is gone in
/// this mode.
class _CollapsedAllDone extends StatelessWidget {
  const _CollapsedAllDone({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final headerStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: onSurface.withValues(alpha: 0.9),
    );
    final progressStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: onSurface.withValues(alpha: 0.75),
    );
    final dotStyle = theme.textTheme.titleMedium?.copyWith(
      color: onSurface.withValues(alpha: 0.4),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Flexible(
            child: Text(
              context.l10n.habitsTodayHeader,
              style: headerStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          Text('·', style: dotStyle),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.l10n.habitsTodayAllDone,
              style: progressStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared pill header styled like the existing `_HabitSection` headers —
/// tinted glass pill with a short title.
class _SectionPillHeader extends StatelessWidget {
  const _SectionPillHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: UnconstrainedBox(
        child: TintedGlassSurface(
          borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(999)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
