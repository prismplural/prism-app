import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_sanitization_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/views/edit_sleep_sheet.dart';
import 'package:prism_plurality/features/fronting/ui/gap_resolution_dialog.dart';
import 'package:prism_plurality/features/fronting/ui/overlap_resolution_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/member_search_groups.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';

/// Full-screen editor for an existing fronting session.
class EditFrontSessionScreen extends ConsumerStatefulWidget {
  const EditFrontSessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<EditFrontSessionScreen> createState() =>
      _EditFrontSessionScreenState();
}

class _EditFrontSessionScreenState
    extends ConsumerState<EditFrontSessionScreen> {
  late DateTime _startTime;
  DateTime? _endTime;
  bool _isActive = false;
  String? _memberId;
  // Co-fronter editing removed — each session is one member's continuous
  // presence. Co-fronting is emergent from overlapping sessions.
  // TODO(§2.5): Phase 3 — add period-level co-front management from detail.
  FrontConfidence? _confidence;
  final _notesController = TextEditingController();
  bool _saving = false;
  bool _loaded = false;
  bool _redirectedToSleepEdit = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _initFromSession(FrontingSession session) {
    if (_loaded) return;
    _loaded = true;
    _startTime = session.startTime;
    _endTime = session.endTime;
    _isActive = session.isActive;
    _memberId = session.memberId;
    _confidence = session.confidence;
    _notesController.text = session.notes ?? '';
  }

  // Date/time editing is handled inline by PrismDateTimePills.

  /// Opens [MemberSearchSheet] in single-select mode for the fronter.
  ///
  /// Includes an "Unknown" special row so the user can clear the fronter.
  Future<void> _openFronterPicker(
    List<Member> members,
    String termPlural,
    List<MemberSearchGroup> groups,
  ) async {
    final result = await MemberSearchSheet.showSingle(
      context,
      members: members,
      termPlural: termPlural,
      groups: groups,
      specialRows: [
        MemberSearchSpecialRow(
          rowKey: '__unknown__',
          title: context.l10n.unknown,
          leading: Icon(AppIcons.helpOutline),
          result: const MemberSearchResultUnknown(),
        ),
      ],
    );
    if (!mounted) return;
    switch (result) {
      case MemberSearchResultSelected(:final memberId):
        setState(() => _memberId = memberId);
      case MemberSearchResultUnknown():
        setState(() => _memberId = null);
      case MemberSearchResultDismissed():
      case MemberSearchResultCleared():
        break;
    }
  }

  Future<void> _save() async {
    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);
    final timingMode = ref.read(timingModeProvider);
    final repo = ref.read(frontingSessionRepositoryProvider);

    // 1. Get the original session directly from repository
    final original = await repo.getSessionById(widget.sessionId);
    if (original == null || !mounted) return;

    final end = _isActive ? null : _endTime;
    final trimmedNotes = _notesController.text.trim();

    // 2. Validate basic time range — hard errors block save
    final timeErrors = editGuard.validateTimeRange(_startTime, end);
    if (timeErrors.isNotEmpty) {
      if (!mounted) return;
      final message = timeErrors.map((e) => e.summary).join('\n');
      PrismToast.error(context, message: message);
      return;
    }

    // 3. Short duration warning (< 1 minute)
    if (end != null &&
        end.difference(_startTime) < const Duration(minutes: 1)) {
      if (!mounted) return;
      final proceed = await PrismDialog.confirm(
        context: context,
        title: context.l10n.frontingShortSessionTitle,
        message: context.l10n.frontingShortSessionMessage,
        confirmLabel: context.l10n.save,
      );
      if (!proceed || !mounted) return;
    }

    // 4. Build snapshot and patch for the edit guard
    final originalSnapshot = FrontingSanitizerService.toSnapshot(original);
    final patch = FrontingSessionPatch(
      start: _startTime != original.startTime ? _startTime : null,
      end: end != original.endTime ? end : null,
      clearEnd: _isActive && original.endTime != null,
      memberId: _memberId != original.memberId ? _memberId : null,
      clearMemberId: _memberId == null && original.memberId != null,
      // coFronterIds omitted — each session is one member's continuous
      // presence; co-fronting is emergent overlap, not a field.
      notes: trimmedNotes.isNotEmpty ? trimmedNotes : null,
      confidenceIndex: _confidence?.index,
    );

    // 5. Load nearby sessions directly from repository (not stream provider,
    // which may not be loaded yet)
    final allSessions = await repo.getAllSessions();
    final nearbySnapshots = allSessions
        .map(FrontingSanitizerService.toSnapshot)
        .toList();

    // 6. Build the proposed snapshot (post-edit state) for overlap resolution
    final proposedSnapshot = FrontingSessionSnapshot(
      id: original.id,
      memberId: _memberId,
      start: _startTime,
      end: end,
      notes: trimmedNotes.isNotEmpty ? trimmedNotes : null,
      confidenceIndex: _confidence?.index,
    );

    // 7. Run edit validation
    final validation = editGuard.validateEdit(
      original: originalSnapshot,
      patch: patch,
      nearbySessions: nearbySnapshots,
      timingMode: timingMode,
    );

    final allChanges = <FrontingSessionChange>[];

    // 7. Handle overlaps
    if (validation.overlappingSessions.isNotEmpty && mounted) {
      // Check if any trim would delete a session
      var wouldDelete = false;
      for (final overlap in validation.overlappingSessions) {
        final trimResult = resolutionService.computeTrimChanges(
          originalSnapshot,
          overlap,
        );
        if (trimResult.wouldDeleteConflicting) {
          wouldDelete = true;
          break;
        }
      }

      final resolution = await showOverlapResolutionDialog(
        context,
        overlapCount: validation.overlappingSessions.length,
        wouldDeleteConflicting: wouldDelete,
        // canCoFront: always true in per-member model — overlaps are expected,
        // and the "co-front" option is now just keeping both sessions.
      );
      if (resolution == null || resolution == OverlapResolution.cancel) return;
      if (!mounted) return;

      final overlapChanges = resolutionService.resolveAllOverlaps(
        edited: proposedSnapshot,
        overlaps: validation.overlappingSessions,
        resolution: resolution,
      );
      allChanges.addAll(overlapChanges);
    }

    // 8. Handle gaps
    if (validation.gapsCreated.isNotEmpty && mounted) {
      final gapResolution = await showGapResolutionDialog(
        context,
        gaps: validation.gapsCreated,
      );
      if (gapResolution == null || gapResolution == GapResolution.cancel) {
        return;
      }
      if (!mounted) return;

      if (gapResolution == GapResolution.fillWithUnknown) {
        final gapChanges = resolutionService.computeGapFillChanges(
          validation.gapsCreated,
        );
        allChanges.addAll(gapChanges);
      }
    }

    // 9. Handle duplicates
    if (validation.duplicates.isNotEmpty && mounted) {
      final proceed = await PrismDialog.confirm(
        context: context,
        title: context.l10n.frontingDuplicateSessionTitle,
        message: context.l10n.frontingDuplicateSessionMessage(
          validation.duplicates.length,
        ),
        confirmLabel: context.l10n.frontingSaveAnyway,
      );
      if (!proceed || !mounted) return;
    }

    // 10. Add the primary update change
    allChanges.insert(
      0,
      UpdateSessionChange(sessionId: widget.sessionId, patch: patch),
    );

    // 11. Execute all changes
    setState(() => _saving = true);

    try {
      final result = await changeExecutor.execute(allChanges);
      result.when(
        success: (_) {
          invalidateFrontingProviders(ref);
          // Fire-and-forget rescan to update the issue banner
          triggerPostEditRescan(
            ref,
            sessionStart: _startTime,
            sessionEnd: _endTime,
          );
          if (mounted) Navigator.of(context).pop(true);
        },
        failure: (error) {
          if (mounted) {
            PrismToast.error(
              context,
              message: context.l10n.frontingErrorSavingSession(error),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSavingSession(e),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final termPlural = watchTerminology(context, ref).plural;
    final sessionAsync = ref.watch(sessionByIdProvider(widget.sessionId));
    final membersAsync = ref.watch(activeMembersProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.frontingEditSessionTitle,
        showBackButton: true,
        trailing: PrismGlassIconButton(
          icon: AppIcons.check,
          onPressed: _saving ? null : _save,
          semanticLabel: context.l10n.frontingSaveSession,
        ),
      ),
      bodyPadding: EdgeInsets.zero,
      body: sessionAsync.when(
        loading: () => const PrismLoadingState(),
        error: (_, _) => Center(child: Text(context.l10n.error)),
        data: (session) {
          if (session == null) {
            return Center(child: Text(context.l10n.frontingSessionNotFound));
          }

          if (session.isSleep) {
            if (!_redirectedToSleepEdit) {
              _redirectedToSleepEdit = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                final navigator = Navigator.of(context);
                await EditSleepSheet.show(context, session);
                if (mounted && navigator.canPop()) {
                  navigator.pop();
                }
              });
            }
            return const PrismLoadingState();
          }

          _initFromSession(session);

          final navBarInset = NavBarInset.of(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + navBarInset),
            children: [
              // Start time
              PrismDateTimePills(
                label: context.l10n.frontingStart,
                dateTime: _startTime,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                onChanged: (dt) => setState(() => _startTime = dt),
              ),
              const SizedBox(height: 16),

              // End time / Still active toggle
              PrismSwitchRow(
                title: context.l10n.frontingStillActive,
                value: _isActive,
                onChanged: (v) => setState(() {
                  _isActive = v;
                  if (v) _endTime = null;
                }),
              ),
              if (!_isActive) ...[
                const SizedBox(height: 8),
                PrismDateTimePills(
                  label: context.l10n.frontingEnd,
                  dateTime: _endTime,
                  firstDate: _startTime,
                  lastDate: DateTime.now(),
                  placeholder: 'Tap to set',
                  onChanged: (dt) => setState(() {
                    _endTime = dt;
                    _isActive = false;
                  }),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),

              // Member picker
              Text(
                context.l10n.frontingFronter,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              membersAsync.when(
                loading: () => const PrismLoadingState(),
                error: (_, _) => Text(context.l10n.error),
                data: (members) {
                  final selected = members.firstWhereOrNull(
                    (m) => m.id == _memberId,
                  );
                  final searchGroups = watchMemberSearchGroups(ref, members);
                  return _FronterPickerRow(
                    selectedMember: selected,
                    onPickerOpen: () =>
                        _openFronterPicker(members, termPlural, searchGroups),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Confidence picker
              Text(
                context.l10n.frontingConfidenceLevel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _ConfidenceEditor(
                selected: _confidence,
                onSelect: (c) => setState(() => _confidence = c),
              ),
              const SizedBox(height: 24),

              // Notes
              PrismTextField(
                controller: _notesController,
                labelText: context.l10n.frontingNotes,
                hintText: context.l10n.frontingNotesHintEdit,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

/// Displays the currently selected fronter (or "Unknown") and provides a
/// search icon to open the [MemberSearchSheet] for single-select.
class _FronterPickerRow extends StatelessWidget {
  const _FronterPickerRow({
    required this.selectedMember,
    required this.onPickerOpen,
  });

  final Member? selectedMember;
  final VoidCallback onPickerOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = selectedMember;
    return InkWell(
      onTap: onPickerOpen,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (member != null) ...[
              MemberAvatar(
                memberName: member.name,
                emoji: member.emoji,
                avatarImageData: member.avatarImageData,
                customColorEnabled: member.customColorEnabled,
                customColorHex: member.customColorHex,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(member.name, style: theme.textTheme.bodyLarge),
              ),
            ] else ...[
              Icon(
                AppIcons.helpOutline,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.unknown,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            IconButton(
              icon: Icon(AppIcons.search),
              tooltip: context.l10n.search,
              onPressed: onPickerOpen,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceEditor extends StatelessWidget {
  const _ConfidenceEditor({required this.selected, required this.onSelect});

  final FrontConfidence? selected;
  final ValueChanged<FrontConfidence?> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      FrontConfidence.unsure: l10n.frontingConfidenceUnsure,
      FrontConfidence.strong: l10n.frontingConfidenceStrong,
      FrontConfidence.certain: l10n.frontingConfidenceCertain,
    };
    return PrismSegmentedControl<FrontConfidence>(
      segments: FrontConfidence.values.map((c) {
        return PrismSegment(value: c, label: labels[c]!);
      }).toList(),
      selected: selected ?? FrontConfidence.unsure,
      onChanged: onSelect,
    );
  }
}
