import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/headmate_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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
    ref.watch(currentFronterProvider); // keep provider warm for _save()
    final theme = Theme.of(context);

    return Column(
      children: [
        PrismSheetTopBar(
          title: context.l10n.habitsCompleteHabit,
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
              // ── Completed At ──────────────────────────────
              PrismDateTimePills(
                label: context.l10n.habitsCompletedAt,
                dateTime: _completedAt,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                onChanged: (dt) => setState(() => _completedAt = dt),
              ),

              const SizedBox(height: 24),

              // ── Member Picker ──────────────────────────────
              HeadmatePicker(
                label: context.l10n.habitsCompletedBy,
                selectedMemberId: _completedByMemberId,
                includeUnknown: true,
                onSelected: (v) => setState(() => _completedByMemberId = v),
              ),

              const SizedBox(height: 24),

              // ── Rating ─────────────────────────────────────
              PrismSectionHeader(title: context.l10n.habitsSectionRating),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final starValue = i + 1;
                  return Semantics(
                    label: context.l10n.habitsRateNStars(i + 1),
                    child: PrismIconButton(
                      icon: _rating != null && starValue <= _rating!
                          ? AppIcons.star
                          : AppIcons.starBorder,
                      color: Colors.amber,
                      tooltip: context.l10n.habitsRateNStarsTooltip(i + 1),
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

              const SizedBox(height: 24),

              // ── Notes ──────────────────────────────────────
              PrismTextField(
                controller: _notesController,
                labelText: context.l10n.habitsNotesField,
                maxLines: 5,
                minLines: 3,
              ),
            ],
          ),
        ),
      ],
    );
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
}
