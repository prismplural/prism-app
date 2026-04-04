import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

class CompleteHabitSheet extends ConsumerStatefulWidget {
  const CompleteHabitSheet({super.key, required this.habit, this.scrollController});
  final Habit habit;
  final ScrollController? scrollController;

  @override
  ConsumerState<CompleteHabitSheet> createState() =>
      _CompleteHabitSheetState();
}

class _CompleteHabitSheetState extends ConsumerState<CompleteHabitSheet> {
  late DateTime _completedAt;
  String? _completedByMemberId;
  final _notesController = TextEditingController();
  int? _rating;

  @override
  void initState() {
    super.initState();
    _completedAt = DateTime.now();
    // Pre-select the current fronter if already loaded. The fronting provider
    // is always streaming (home tab is mounted), so this sync read reliably
    // picks up the cached value without waiting for an async rebuild.
    _completedByMemberId = ref.read(currentFronterProvider).value?.id;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(allMembersProvider);
    ref.watch(currentFronterProvider); // keep provider warm for _save()
    final theme = Theme.of(context);

    return Column(
      children: [
        PrismSheetTopBar(
          title: 'Complete Habit',
          trailing: PrismGlassIconButton(
            icon: AppIcons.check,
            size: PrismTokens.topBarActionSize,
            tint: theme.colorScheme.primary,
            accentIcon: true,
            onPressed: _save,
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // ── Date/Time ──────────────────────────────────
              PrismListRow(
                leading: Icon(AppIcons.accessTime),
                title: const Text('Completed At'),
                subtitle: Text(_formatDateTime(_completedAt)),
                showChevron: true,
                onTap: _pickDateTime,
              ),

              const SizedBox(height: 16),

              // ── Member Picker ──────────────────────────────
              membersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (members) => PrismSurface(
                  tone: PrismSurfaceTone.subtle,
                  padding: EdgeInsets.zero,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _completedByMemberId,
                    decoration: const InputDecoration(
                      labelText: 'Completed By',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Unknown')),
                      ...members.map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name),
                          )),
                    ],
                    onChanged: (v) => setState(() => _completedByMemberId = v),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Notes ──────────────────────────────────────
              PrismTextField(
                controller: _notesController,
                labelText: 'Notes (optional)',
                maxLines: 3,
              ),

              const SizedBox(height: 16),

              // ── Rating ─────────────────────────────────────
              const PrismSectionHeader(title: 'RATING'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starValue = i + 1;
                  return Semantics(
                    label: 'Rate ${i + 1} out of 5 stars',
                    child: PrismIconButton(
                      icon: _rating != null && starValue <= _rating!
                          ? AppIcons.star
                          : AppIcons.starBorder,
                      color: Colors.amber,
                      tooltip: 'Rate ${i + 1} stars',
                      onPressed: () {
                        setState(() {
                          _rating =
                              _rating == starValue ? null : starValue;
                        });
                      },
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showPrismDatePicker(
      context: context,
      initialDate: _completedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showPrismTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_completedAt),
    );
    if (time == null || !mounted) return;

    setState(() {
      _completedAt = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final currentFronter = ref.read(currentFronterProvider).value;
    final wasFronting =
        _completedByMemberId != null &&
        currentFronter != null &&
        _completedByMemberId == currentFronter.id;

    await ref.read(habitNotifierProvider.notifier).completeHabit(
          habitId: widget.habit.id,
          completedByMemberId: _completedByMemberId,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          rating: _rating,
          wasFronting: wasFronting,
          completedAt: _completedAt,
        );

    if (mounted) Navigator.of(context).pop();
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.month}/${dt.day}/${dt.year} '
        '${hour == 0 ? 12 : hour}:${dt.minute.toString().padLeft(2, '0')} $period';
  }
}
