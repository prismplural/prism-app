import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

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
  List<String> _coFronterIds = [];
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
    _coFronterIds = List.from(session.coFronterIds);
    _confidence = session.confidence;
    _notesController.text = session.notes ?? '';
  }

  // Date/time editing is handled inline by PrismDateTimePills.

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
    if (end != null && end.difference(_startTime) < const Duration(minutes: 1)) {
      if (!mounted) return;
      final proceed = await PrismDialog.confirm(
        context: context,
        title: 'Short Session',
        message: 'This session is less than a minute long. Save anyway?',
        confirmLabel: 'Save',
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
      coFronterIds: _coFronterIds,
      notes: trimmedNotes.isNotEmpty ? trimmedNotes : null,
      confidenceIndex: _confidence?.index,
    );

    // 5. Load nearby sessions directly from repository (not stream provider,
    // which may not be loaded yet)
    final allSessions = await repo.getAllSessions();
    final nearbySnapshots =
        allSessions.map(FrontingSanitizerService.toSnapshot).toList();

    // 6. Build the proposed snapshot (post-edit state) for overlap resolution
    final proposedSnapshot = FrontingSessionSnapshot(
      id: original.id,
      memberId: _memberId,
      start: _startTime,
      end: end,
      coFronterIds: _coFronterIds,
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
        final trimResult =
            resolutionService.computeTrimChanges(originalSnapshot, overlap);
        if (trimResult.wouldDeleteConflicting) {
          wouldDelete = true;
          break;
        }
      }

      final resolution = await showOverlapResolutionDialog(
        context,
        overlapCount: validation.overlappingSessions.length,
        wouldDeleteConflicting: wouldDelete,
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
        final gapChanges =
            resolutionService.computeGapFillChanges(validation.gapsCreated);
        allChanges.addAll(gapChanges);
      }
    }

    // 9. Handle duplicates
    if (validation.duplicates.isNotEmpty && mounted) {
      final proceed = await PrismDialog.confirm(
        context: context,
        title: 'Duplicate Session',
        message: 'This session appears to be a duplicate of '
            '${validation.duplicates.length} other '
            '${validation.duplicates.length == 1 ? 'session' : 'sessions'}. '
            'Save anyway?',
        confirmLabel: 'Save anyway',
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
          // Fire-and-forget rescan to update the issue banner
          triggerPostEditRescan(ref, sessionStart: _startTime, sessionEnd: _endTime);
          if (mounted) Navigator.of(context).pop(true);
        },
        failure: (error) {
          if (mounted) {
            PrismToast.error(context, message: 'Error saving session: $error');
          }
        },
      );
    } catch (e) {
      if (mounted) {
        PrismToast.error(context, message: 'Error saving session: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionAsync = ref.watch(sessionByIdProvider(widget.sessionId));
    final membersAsync = ref.watch(activeMembersProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Edit Session',
        showBackButton: true,
        trailing: PrismButton(
          label: 'Save',
          tone: PrismButtonTone.subtle,
          onPressed: _save,
          enabled: !_saving,
          isLoading: _saving,
        ),
      ),
      bodyPadding: EdgeInsets.zero,
      body: sessionAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('Session not found'));
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
                label: 'Start',
                dateTime: _startTime,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                onChanged: (dt) => setState(() => _startTime = dt),
              ),
              const SizedBox(height: 16),

              // End time / Still active toggle
              PrismSwitchRow(
                title: 'Still Active',
                value: _isActive,
                onChanged: (v) => setState(() {
                  _isActive = v;
                  if (v) _endTime = null;
                }),
              ),
              if (!_isActive) ...[
                const SizedBox(height: 8),
                PrismDateTimePills(
                  label: 'End',
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
                'Fronter',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              membersAsync.when(
                loading: () => const PrismLoadingState(),
                error: (e, _) => Text('Error: $e'),
                data: (members) => _MemberSelector(
                  members: members,
                  selectedId: _memberId,
                  onSelect: (id) => setState(() => _memberId = id),
                ),
              ),
              const SizedBox(height: 24),

              // Co-fronter editor
              Text(
                'Co-Fronters',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              membersAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (members) {
                  final available = members
                      .where((m) => m.id != _memberId)
                      .toList();
                  return Column(
                    children: available.map((m) {
                      return PrismListRow(
                        leading: MemberAvatar(
                          avatarImageData: m.avatarImageData,
                          emoji: m.emoji,
                          customColorEnabled: m.customColorEnabled,
                          customColorHex: m.customColorHex,
                          size: 36,
                        ),
                        title: Text(m.name),
                        trailing: Checkbox(
                          value: _coFronterIds.contains(m.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _coFronterIds.add(m.id);
                              } else {
                                _coFronterIds.remove(m.id);
                              }
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            if (_coFronterIds.contains(m.id)) {
                              _coFronterIds.remove(m.id);
                            } else {
                              _coFronterIds.add(m.id);
                            }
                          });
                        },
                        padding: EdgeInsets.zero,
                        dense: true,
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Confidence picker
              Text(
                'Confidence Level',
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
                labelText: 'Notes',
                hintText: 'Optional notes...',
                alignLabelWithHint: true,
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

class _MemberSelector extends StatelessWidget {
  const _MemberSelector({
    required this.members,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Member> members;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PrismChip(
          label: 'Unknown',
          selected: selectedId == null,
          onTap: () => onSelect(null),
          avatar: Icon(AppIcons.helpOutline, size: 16),
        ),
        ...members.map((m) => PrismChip(
          label: m.name,
          selected: m.id == selectedId,
          onTap: () => onSelect(m.id),
          avatar: Text(m.emoji, style: const TextStyle(fontSize: 15)),
        )),
      ],
    );
  }
}

class _ConfidenceEditor extends StatelessWidget {
  const _ConfidenceEditor({required this.selected, required this.onSelect});

  final FrontConfidence? selected;
  final ValueChanged<FrontConfidence?> onSelect;

  static const _labels = {
    FrontConfidence.unsure: 'Unsure',
    FrontConfidence.strong: 'Strong',
    FrontConfidence.certain: 'Certain',
  };

  @override
  Widget build(BuildContext context) {
    return PrismSegmentedControl<FrontConfidence>(
      segments: FrontConfidence.values.map((c) {
        return PrismSegment(
          value: c,
          label: _labels[c]!,
        );
      }).toList(),
      selected: selected ?? FrontConfidence.unsure,
      onChanged: onSelect,
    );
  }
}
