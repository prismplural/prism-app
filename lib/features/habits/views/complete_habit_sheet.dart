import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
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
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

class CompleteHabitSheet extends ConsumerStatefulWidget {
  const CompleteHabitSheet({
    super.key,
    required this.habit,
    this.scrollController,
    this.existingCompletion,
    this.initialPastDefault = false,
  });

  final Habit habit;
  final ScrollController? scrollController;

  /// When non-null, the sheet opens in edit mode pre-populated with these
  /// values. Mutually exclusive with [initialPastDefault].
  final HabitCompletion? existingCompletion;

  /// When true (and [existingCompletion] is null), the date field pre-fills to
  /// now − 24 hours. Used by the "Log missed completion" flow.
  final bool initialPastDefault;

  @override
  ConsumerState<CompleteHabitSheet> createState() =>
      CompleteHabitSheetState();
}

// State class is public so tests can access @visibleForTesting members.
class CompleteHabitSheetState extends ConsumerState<CompleteHabitSheet> {
  late DateTime _completedAt;
  late DateTime _initialCompletedAt;
  String? _completedByMemberId;
  bool _completedByMemberWasEdited = false;
  final _notesController = TextEditingController();
  int? _rating;

  late String? _initialMemberId;
  late int? _initialRating;
  late String _initialNotes;

  bool get _isEditMode => widget.existingCompletion != null;

  bool get _isDirty {
    return _completedAt != _initialCompletedAt ||
        _completedByMemberId != _initialMemberId ||
        _rating != _initialRating ||
        _notesController.text != _initialNotes;
  }

  // ── @visibleForTesting accessors ─────────────────────────────────────────

  @visibleForTesting
  DateTime get completedAt => _completedAt;

  @visibleForTesting
  String? get completedByMemberId => _completedByMemberId;

  /// Test helper: directly mutate [_completedByMemberId] and mark as edited,
  /// as if the user picked a different member.
  @visibleForTesting
  void setCompletedByMemberIdForTest(String? memberId) {
    setState(() {
      _completedByMemberId = memberId;
      _completedByMemberWasEdited = true;
    });
  }

  /// Test helper: directly set [_completedAt], as if the user picked a
  /// different date/time via the pills.
  @visibleForTesting
  void setCompletedAtForTest(DateTime dt) {
    setState(() => _completedAt = dt);
  }

  @override
  void initState() {
    super.initState();

    assert(
      widget.existingCompletion == null || !widget.initialPastDefault,
      'existingCompletion and initialPastDefault are mutually exclusive',
    );

    if (_isEditMode) {
      // Edit mode: pre-populate from the existing completion.
      final existing = widget.existingCompletion!;
      _completedAt = existing.completedAt;
      _completedByMemberId = existing.completedByMemberId;
      _rating = existing.rating;
      _notesController.text = existing.notes ?? '';
    } else if (widget.initialPastDefault) {
      // Create-past mode: default to 24 h ago.
      _completedAt = DateTime.now().subtract(const Duration(hours: 24));
      // No fronter prefill for past-dated completions.
    } else {
      // Create-now mode (original behaviour).
      _completedAt = DateTime.now();
      // Pre-select immediately when the current fronter is already cached; the
      // build listener below fills it in later if the stream is still loading.
      _completedByMemberId = ref.read(currentFronterProvider).value?.id;
    }

    // Snapshot initial values AFTER applying the prefill.
    _initialCompletedAt = _completedAt;
    _initialMemberId = _completedByMemberId;
    _initialRating = _rating;
    _initialNotes = _notesController.text;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Async fronter prefill is only active in create-now mode.
    if (!_isEditMode) {
      ref.listen(currentFronterProvider, (_, next) {
        final currentFronter = next.value;
        if (_completedByMemberWasEdited ||
            _completedByMemberId != null ||
            currentFronter == null) {
          return;
        }
        setState(() {
          _completedByMemberId = currentFronter.id;
          _initialMemberId = currentFronter.id; // lockstep — prevents false-dirty
        });
      });
    }
    ref.watch(currentFronterProvider); // keep provider warm for _save()
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: _notesController,
      builder: (context, _) => UnsavedChangesGuard<void>(
        hasUnsavedChanges: _isDirty,
        child: Column(
          children: [
            PrismSheetTopBar(
              title: _isEditMode
                  ? l10n.habitsEditCompletion
                  : l10n.habitsCompleteHabit,
              trailing: PrismGlassIconButton(
                icon: AppIcons.check,
                tooltip: context.l10n.save,
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
                    onSelected: (v) => setState(() {
                      _completedByMemberWasEdited = true;
                      _completedByMemberId = v;
                    }),
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
                              _rating = _rating == starValue ? null : starValue;
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
        ),
      ),
    );
  }

  Future<void> _save() async {
    // Future-time guard: validate FIRST before any dispatch.
    if (_completedAt.isAfter(DateTime.now())) {
      PrismToast.error(
        context,
        message: context.l10n.habitsFutureCompletionError,
      );
      return;
    }

    // ── wasFronting policy ────────────────────────────────────────────────
    final bool wasFronting;
    if (_isEditMode) {
      final existing = widget.existingCompletion!;
      if (_completedByMemberId == existing.completedByMemberId &&
          _completedAt == existing.completedAt) {
        // Notes/rating-only edit: preserve the original wasFronting flag.
        wasFronting = existing.wasFronting;
      } else {
        // Member or timestamp changed — the original assertion no longer holds.
        wasFronting = false;
      }
    } else if (widget.initialPastDefault) {
      // Past-dated completions: the current-fronter assertion only makes sense
      // for "right now".
      wasFronting = false;
    } else {
      // Create-now: existing logic.
      final currentFronter = ref.read(currentFronterProvider).value;
      wasFronting = _completedByMemberId != null &&
          currentFronter != null &&
          _completedByMemberId == currentFronter.id;
    }

    final trimmedNotes = _notesController.text.trim();
    final notes = trimmedNotes.isEmpty ? null : trimmedNotes;

    if (_isEditMode) {
      final updated = widget.existingCompletion!.copyWith(
        completedAt: _completedAt,
        completedByMemberId: _completedByMemberId,
        notes: notes,
        rating: _rating,
        wasFronting: wasFronting,
      );
      await ref
          .read(habitNotifierProvider.notifier)
          .updateCompletion(updated);
    } else {
      await ref
          .read(habitNotifierProvider.notifier)
          .completeHabit(
            habitId: widget.habit.id,
            completedByMemberId: _completedByMemberId,
            notes: notes,
            rating: _rating,
            wasFronting: wasFronting,
            completedAt: _completedAt,
          );
    }

    if (mounted) Navigator.of(context).pop();
  }
}
