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
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_pill.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

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

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: habitAsync.value?.name ?? 'Habit',
        showBackButton: true,
        trailing: habitAsync.value != null
            ? PrismPopupMenu<String>(
                items: [
                  const PrismMenuItem(
                      value: 'edit', label: 'Edit', icon: Icons.edit),
                  PrismMenuItem(
                    value: 'toggle',
                    label: habitAsync.value!.isActive
                        ? 'Deactivate'
                        : 'Activate',
                    icon: habitAsync.value!.isActive
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  const PrismMenuItem(
                      value: 'delete',
                      label: 'Delete',
                      icon: Icons.delete_outline,
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
                tooltip: 'More options',
              )
            : null,
      ),
      bodyPadding: EdgeInsets.zero,
      // ── Floating Complete Button ──────────────────────────
      bottomBar: habitAsync.value != null
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: PrismButton(
                  tone: PrismButtonTone.filled,
                  label: 'Complete',
                  icon: Icons.check,
                  semanticLabel: 'Complete habit',
                  onPressed: () =>
                      _showCompleteSheet(context, habitAsync.value!),
                ),
              ),
            )
          : null,
      body: habitAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (habit) {
          if (habit == null) {
            return const Center(child: Text('Habit not found'));
          }
          final habitColor = _habitColor(context, habit);
          final members = membersAsync.value ?? [];

          final navBarInset = NavBarInset.of(context);
          return ListView(
            padding: EdgeInsets.only(bottom: navBarInset + 16),
            children: [
              // ── Header ─────────────────────────────────────
              _HabitHeader(habit: habit),

              // ── Timeframe Picker ───────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SegmentedButton<StatisticsTimeframe>(
                  segments: StatisticsTimeframe.values
                      .map((t) => ButtonSegment(
                            value: t,
                            label: Text(t.label),
                          ))
                      .toList(),
                  selected: {_timeframe},
                  onSelectionChanged: (v) =>
                      setState(() => _timeframe = v.first),
                ),
              ),

              // ── Stats Row ──────────────────────────────────
              statsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: PrismLoadingState(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading stats: $e'),
                ),
                data: (stats) => _StatsRow(
                  stats: stats,
                  habitColor: habitColor,
                ),
              ),

              const SizedBox(height: 8),

              // ── Recent Completions ─────────────────────────
              const PrismSectionHeader(title: 'RECENT COMPLETIONS'),
              completionsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $e'),
                ),
                data: (completions) {
                  if (completions.isEmpty) {
                    return const EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'No completions yet',
                      subtitle:
                          'Complete this habit to start tracking progress.',
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: completions.length.clamp(0, 20),
                    itemBuilder: (context, index) {
                      final c = completions[index];
                      return _CompletionTile(
                        completion: c,
                        members: members,
                        onDismissed: () => ref
                            .read(habitNotifierProvider.notifier)
                            .uncompleteHabit(
                              habitId: widget.habitId,
                              completionId: c.id,
                            ),
                      );
                    },
                  );
                },
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
      title: 'Delete Habit',
      message:
          'This will permanently delete this habit and all its completions. This action cannot be undone.',
      confirmLabel: 'Delete',
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
// Header — emoji + frequency + description (no duplicate name)
// ─────────────────────────────────────────────────────────────

class _HabitHeader extends StatelessWidget {
  const _HabitHeader({required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frequencyText =
        habit.frequency == HabitFrequency.interval && habit.intervalDays != null
            ? 'Every ${habit.intervalDays} days'
            : habit.frequency.label;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (habit.icon != null)
            Text(habit.icon!, style: const TextStyle(fontSize: 40))
          else
            Icon(Icons.check_circle_outline,
                size: 40, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(frequencyText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Stats — horizontal pill row
// ─────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats, required this.habitColor});
  final HabitStats stats;
  final Color habitColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PrismPill(
            icon: Icons.check_circle,
            label: '${stats.totalCompletions} done',
            color: habitColor,
          ),
          PrismPill(
            icon: Icons.percent,
            label: '${stats.completionRate.toStringAsFixed(0)}%',
            color: habitColor,
          ),
          if (stats.currentStreak > 0)
            PrismPill(
              icon: Icons.local_fire_department,
              label: '${stats.currentStreak} streak',
              color: Colors.orange.shade700,
            ),
          if (stats.bestStreak > stats.currentStreak)
            PrismPill(
              icon: Icons.emoji_events,
              label: '${stats.bestStreak} best',
              color: Colors.amber.shade700,
            ),
        ],
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
    required this.onDismissed,
  });

  final HabitCompletion completion;
  final List<Member> members;
  final VoidCallback onDismissed;

  Member? _findMember() {
    if (completion.completedByMemberId == null) return null;
    try {
      return members.firstWhere((m) => m.id == completion.completedByMemberId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = _findMember();

    return Dismissible(
      key: ValueKey(completion.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: AppColors.warmWhite),
      ),
      onDismissed: (_) => onDismissed(),
      child: PrismListRow(
        leading: member != null
            ? MemberAvatar(
                emoji: member.emoji,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                avatarImageData: member.avatarImageData,
                size: 36,
              )
            : const Icon(Icons.check_circle, color: Colors.green),
        title: Text(_formatDate(completion.completedAt)),
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
                label: 'Rated ${completion.rating} out of 5 stars',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < completion.rating!
                          ? Icons.star
                          : Icons.star_border,
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) {
      return 'Today ${_timeString(date)}';
    } else if (dateDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${_timeString(date)}';
    }
    return '${date.month}/${date.day}/${date.year} ${_timeString(date)}';
  }

  String _timeString(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $period';
  }
}
