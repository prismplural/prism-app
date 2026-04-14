import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/add_edit_habit_sheet.dart';
import 'package:prism_plurality/features/habits/views/complete_habit_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/glass_surface.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class HabitDetailScreen extends ConsumerStatefulWidget {
  const HabitDetailScreen({super.key, required this.habitId});
  final String habitId;

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  StatisticsTimeframe _timeframe = StatisticsTimeframe.month;

  Color _habitColor(BuildContext context, Habit habit) {
    if (habit.colorHex != null && habit.colorHex!.isNotEmpty) {
      final hex = habit.colorHex!.replaceFirst('#', '');
      final value = int.tryParse(hex, radix: 16);
      if (value != null) {
        return Color(0xFF000000 | value);
      }
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final habitAsync = ref.watch(habitByIdProvider(widget.habitId));
    final completionsAsync =
        ref.watch(habitCompletionsProvider(widget.habitId));
    final statsAsync = ref.watch(habitStatsProvider(
        (habitId: widget.habitId, timeframe: _timeframe)));
    final membersAsync = ref.watch(allMembersProvider);
    final today = ref.watch(currentDateProvider);

    final completions = completionsAsync.value ?? [];
    final isCompletedToday = completions.any(
        (c) => DateUtils.isSameDay(c.completedAt, today));

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        trailing: habitAsync.value != null
            ? PrismPopupMenu<String>(
                items: [
                  PrismMenuItem(
                      value: 'edit', label: context.l10n.edit, icon: AppIcons.edit),
                  PrismMenuItem(
                    value: 'toggle',
                    label: habitAsync.value!.isActive
                        ? context.l10n.deactivate
                        : context.l10n.activate,
                    icon: habitAsync.value!.isActive
                        ? AppIcons.visibilityOff
                        : AppIcons.visibility,
                  ),
                  PrismMenuItem(
                      value: 'delete',
                      label: context.l10n.delete,
                      icon: AppIcons.deleteOutline,
                      destructive: true),
                ],
                onSelected: (value) async {
                  switch (value) {
                    case 'edit':
                      _showEditSheet(context, habitAsync.value!);
                    case 'toggle':
                      await ref
                          .read(habitNotifierProvider.notifier)
                          .toggleActive(widget.habitId);
                    case 'delete':
                      await _confirmDelete(context);
                  }
                },
                tooltip: context.l10n.habitsDetailMoreOptions,
              )
            : null,
      ),
      bodyPadding: EdgeInsets.zero,
      body: habitAsync.when(
        loading: () => const PrismLoadingState(),
        error: (_, _) => Center(child: Text(context.l10n.error)),
        data: (habit) {
          if (habit == null) {
            return const Center(child: Text('Habit not found'));
          }
          final habitColor = _habitColor(context, habit);
          final members = membersAsync.value ?? [];

          final navBarInset = NavBarInset.of(context);
          // Reserve room at the bottom of the scroll view for the floating
          // Complete pill: navBarInset + 16 (pill bottom offset) + ~52 pill
          // height + 16 breathing room.
          final bottomReserve = navBarInset + 84;

          final scrollView = SingleChildScrollView(
            physics: const _OverflowAwareBouncingPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.only(bottom: bottomReserve),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ─────────────────────────────────────
                _HabitHeader(habit: habit, habitColor: habitColor),

                // ── Timeframe Picker ───────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: PrismSegmentedControl<StatisticsTimeframe>(
                    segments: StatisticsTimeframe.values
                        .map((t) => PrismSegment(
                              value: t,
                              label: t.label,
                            ))
                        .toList(),
                    selected: _timeframe,
                    onChanged: (value) =>
                        setState(() => _timeframe = value),
                  ),
                ),

                // ── Stats Row ──────────────────────────────────
                statsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: PrismLoadingState(),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.l10n.error),
                  ),
                  data: (stats) => _StatsRow(
                    stats: stats,
                    habitColor: habitColor,
                  ),
                ),

                // ── Recent Completions ─────────────────────────
                PrismSectionHeader(
                  title: context.l10n.habitsDetailSectionRecentCompletions,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                ),
                completionsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.l10n.error),
                  ),
                  data: (completions) {
                    if (completions.isEmpty) {
                      return EmptyState(
                        icon: Icon(AppIcons.checkCircleOutline),
                        title: context.l10n.habitsDetailNoCompletions,
                        subtitle: context.l10n.habitsDetailNoCompletionsSubtitle,
                      );
                    }
                    // Plain Column — no nested scroll view, no
                    // lazy building. 20 items max.
                    return Column(
                      children: [
                        for (final c in completions.take(20))
                          _CompletionTile(
                            completion: c,
                            members: members,
                            today: today,
                            onDismissed: () => ref
                                .read(habitNotifierProvider.notifier)
                                .uncompleteHabit(
                                  habitId: widget.habitId,
                                  completionId: c.id,
                                ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );

          return Stack(
            children: [
              scrollView,
              Positioned(
                left: 16,
                right: 16,
                bottom: navBarInset + 16,
                child: Center(
                  child: _FloatingCompleteButton(
                    habit: habit,
                    habitColor: habitColor,
                    isCompletedToday: isCompletedToday,
                    onPressed: () => _showCompleteSheet(context, habit),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, Habit habit) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => AddEditHabitSheet(
        existingHabit: habit,
        scrollController: scrollController,
      ),
    );
  }

  void _showCompleteSheet(BuildContext context, Habit habit) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, sc) =>
          CompleteHabitSheet(habit: habit, scrollController: sc),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.habitsDetailDeleteTitle,
      message: context.l10n.habitsDetailDeleteMessage,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (confirmed && context.mounted) {
      await ref
          .read(habitNotifierProvider.notifier)
          .deleteHabit(widget.habitId);
      if (context.mounted) context.pop();
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Header — emoji + name + frequency + description
// ─────────────────────────────────────────────────────────────

class _HabitHeader extends StatelessWidget {
  const _HabitHeader({required this.habit, required this.habitColor});
  final Habit habit;
  final Color habitColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frequencyText =
        habit.frequency == HabitFrequency.interval && habit.intervalDays != null
            ? context.l10n.habitsDetailFrequencyEveryNDays(habit.intervalDays!)
            : habit.frequency.label;

    final semanticsLabel = [
      'Habit: ${habit.name}',
      frequencyText,
      if (habit.description != null && habit.description!.isNotEmpty)
        habit.description!,
    ].join(', ');

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            TintedGlassSurface.circle(
              size: 48,
              tint: habitColor,
              child: Center(
                child: habit.icon != null
                    ? Text(habit.icon!, style: const TextStyle(fontSize: 24))
                    : Icon(AppIcons.checkCircleOutline,
                        size: 24, color: habitColor),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.name,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    frequencyText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (habit.description != null &&
                      habit.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(habit.description!,
                          style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stats — primary stats + optional streak pills
// ─────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.habitColor});
  final HabitStats stats;
  final Color habitColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showStreaks =
        stats.currentStreak > 0 || stats.bestStreak > stats.currentStreak;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: context.l10n.habitsStatsSemanticsLabel(
                  stats.totalCompletions,
                  stats.completionRate.toStringAsFixed(0),
                ),
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.habitsStatCompletions,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${stats.totalCompletions}',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.habitsStatCompletionRate,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${stats.completionRate.toStringAsFixed(0)}%',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (showStreaks) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (stats.currentStreak > 0)
                      PrismPill(
                        icon: AppIcons.localFireDepartment,
                        label: context.l10n.habitsStatCurrentStreak(stats.currentStreak),
                        color: Colors.orange.shade700,
                      ),
                    if (stats.bestStreak > stats.currentStreak)
                      PrismPill(
                        icon: AppIcons.emojiEvents,
                        label: context.l10n.habitsStatBestStreak(stats.bestStreak),
                        color: Colors.amber.shade700,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Completion tile — shows who completed it
// ─────────────────────────────────────────────────────────────

class _CompletionTile extends StatelessWidget {
  const _CompletionTile({
    required this.completion,
    required this.members,
    required this.today,
    required this.onDismissed,
  });

  final HabitCompletion completion;
  final List<Member> members;
  final DateTime today;
  final VoidCallback onDismissed;

  Member? _findMember() {
    if (completion.completedByMemberId == null) return null;
    return members.firstWhereOrNull((m) => m.id == completion.completedByMemberId);
  }

  @override
  Widget build(BuildContext context) {
    final member = _findMember();

    return Dismissible(
      key: ValueKey(completion.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(AppIcons.delete, color: AppColors.warmWhite),
      ),
      onDismissed: (_) => onDismissed(),
      child: PrismListRow(
        leading: member != null
            ? MemberAvatar(
                emoji: member.emoji,
                memberName: member.name,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                avatarImageData: member.avatarImageData,
                size: 36,
              )
            : Icon(AppIcons.checkCircle, color: Colors.green),
        title: Text(_formatDate(context, completion.completedAt)),
        subtitle: Text(
          [
            if (member != null) member.name,
            if (completion.notes != null) completion.notes!,
          ].join(' — '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: completion.rating != null
            ? Semantics(
                label: context.l10n.habitsCompletionRatedNStars(completion.rating!),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < completion.rating!
                          ? AppIcons.star
                          : AppIcons.starBorder,
                      size: 14,
                      color: Colors.amber,
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) {
      return context.l10n.habitsCompletionTileToday(_timeString(date));
    } else if (dateDay == today.subtract(const Duration(days: 1))) {
      return context.l10n.habitsCompletionTileYesterday(_timeString(date));
    }
    return '${date.month}/${date.day}/${date.year} ${_timeString(date)}';
  }

  String _timeString(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
  }
}

// ─────────────────────────────────────────────────────────────
// Scroll physics — bouncy iOS feel when content actually overflows,
// and a hard refusal to scroll when the page fits in the viewport.
// ─────────────────────────────────────────────────────────────

/// Delegates to [BouncingScrollPhysics] for the native iOS feel when content
/// actually overflows, but refuses user scroll offsets when there is nothing
/// to scroll to. The net effect: no bounce when the page fits, normal iOS
/// bounce behavior when completions push the content past the viewport.
class _OverflowAwareBouncingPhysics extends ScrollPhysics {
  const _OverflowAwareBouncingPhysics({super.parent});

  @override
  _OverflowAwareBouncingPhysics applyTo(ScrollPhysics? ancestor) {
    return _OverflowAwareBouncingPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return position.maxScrollExtent > 0.0;
  }
}

// ─────────────────────────────────────────────────────────────
// Floating Complete button — pill-shaped glass surface that
// floats above the scroll view. Content scrolls under it with
// real backdrop blur via GlassSurface.
// ─────────────────────────────────────────────────────────────

class _FloatingCompleteButton extends ConsumerWidget {
  const _FloatingCompleteButton({
    required this.habit,
    required this.habitColor,
    required this.isCompletedToday,
    required this.onPressed,
  });

  final Habit habit;
  final Color habitColor;
  final bool isCompletedToday;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enabled = !isCompletedToday && habit.isActive;
    // Tint with the habit color when the button is the active CTA; drop
    // the tint once the habit is already complete for the period so the
    // pill reads as inert glass.
    final tint = isCompletedToday ? null : habitColor;

    final pillRadius = BorderRadius.circular(PrismTokens.radiusPill);

    return Semantics(
      button: true,
      enabled: enabled,
      label: isCompletedToday
          ? context.l10n.habitsAlreadyCompleted
          : context.l10n.habitsCompleteButtonLabel,
      child: GlassSurface(
        borderRadius: pillRadius,
        tint: tint,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: pillRadius,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCompletedToday ? AppIcons.checkCircle : AppIcons.check,
                    size: 18,
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCompletedToday ? context.l10n.habitsCompleted : context.l10n.habitsComplete,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
