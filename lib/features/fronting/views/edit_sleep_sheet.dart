import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_editing_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/utils/sleep_quality_l10n.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';

/// Full-screen editor for an existing sleep session.
class EditSleepSheet extends ConsumerStatefulWidget {
  const EditSleepSheet({
    super.key,
    required this.session,
    required this.scrollController,
  });

  final FrontingSession session;
  final ScrollController scrollController;

  static Future<bool?> show(BuildContext context, FrontingSession session) {
    return PrismSheet.showFullScreen<bool>(
      context: context,
      builder: (context, scrollController) =>
          EditSleepSheet(session: session, scrollController: scrollController),
    );
  }

  @override
  ConsumerState<EditSleepSheet> createState() => _EditSleepSheetState();
}

class _EditSleepSheetState extends ConsumerState<EditSleepSheet> {
  late DateTime _startTime;
  DateTime? _endTime;
  late bool _isActive;
  late SleepQuality _quality;
  final _notesController = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

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
    _quality = session.quality ?? SleepQuality.unknown;
    _notesController.text = session.notes ?? '';
  }

  // Date/time editing is handled inline by PrismDateTimePills.

  Future<void> _save() async {
    final notes = _notesController.text.trim();
    final endTime = _isActive ? null : (_endTime ?? DateTime.now());

    if (endTime != null && !endTime.isAfter(_startTime)) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: context.l10n.frontingEndTimeMustBeAfterStart,
      );
      return;
    }

    final editGuard = ref.read(frontingEditGuardProvider);
    final resolutionService = ref.read(frontingEditResolutionServiceProvider);
    final changeExecutor = ref.read(frontingChangeExecutorProvider);
    final timingMode = ref.read(timingModeProvider);
    final repo = ref.read(frontingSessionRepositoryProvider);
    final mutationService = ref.read(frontingMutationServiceProvider);

    // Detect cross-type overlaps with fronting neighbors so sleep edits go
    // through the same trim flow as fronting edits. The timeline is one
    // continuous stream regardless of session type.
    final originalSnapshot = FrontingSanitizerService.toSnapshot(
      widget.session,
    );
    final editedSnapshot = FrontingSessionSnapshot(
      id: widget.session.id,
      memberId: widget.session.memberId,
      start: _startTime,
      end: endTime,
      notes: notes.isNotEmpty ? notes : null,
      sessionType: widget.session.sessionType,
    );
    final guardPatch = FrontingSessionPatch(
      start: _startTime != widget.session.startTime ? _startTime : null,
      end: endTime != widget.session.endTime ? endTime : null,
      clearEnd: _isActive && widget.session.endTime != null,
    );

    final allSessions = await repo.getAllSessions();
    if (!mounted) return;
    final nearbySnapshots = allSessions
        .map(FrontingSanitizerService.toSnapshot)
        .toList();

    final validation = editGuard.validateEdit(
      original: originalSnapshot,
      patch: guardPatch,
      nearbySessions: nearbySnapshots,
      timingMode: timingMode,
    );

    // Cross-member overlaps are valid in the per-member model (spec §3.3).
    final patch = UpdateFrontingSessionPatch(
      startTime: _startTime != widget.session.startTime
          ? FieldPatch.value(_startTime)
          : const FieldPatch.absent(),
      endTime: _isActive
          ? (widget.session.endTime != null
                ? const FieldPatch.value(null)
                : const FieldPatch.absent())
          : (_endTime != widget.session.endTime
                ? FieldPatch.value(endTime)
                : const FieldPatch.absent()),
      notes: notes != (widget.session.notes ?? '')
          ? FieldPatch.value(notes.isEmpty ? null : notes)
          : const FieldPatch.absent(),
    );

    setState(() => _saving = true);

    try {
      if (!patch.isEmpty) {
        await mutationService.updateSession(widget.session.id, patch);
      }
      if (_quality != (widget.session.quality ?? SleepQuality.unknown)) {
        await mutationService.updateSleepQuality(widget.session.id, _quality);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        PrismToast.error(
          context,
          message: context.l10n.frontingErrorSavingSleepSession(e),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    _initFromSession(widget.session);

    return Column(
      children: [
        PrismSheetTopBar(
          title: context.l10n.frontingEditSleepTitle,
          trailing: PrismGlassIconButton(
            icon: AppIcons.check,
            tooltip: context.l10n.save,
            onPressed: _saving ? null : _save,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            children: [
              PrismSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          AppIcons.bedtimeRounded,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.frontingEditSleepLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PrismSwitchRow(
                      title: context.l10n.frontingStillSleeping,
                      subtitle: context.l10n.frontingStillSleepingSubtitle,
                      value: _isActive,
                      onChanged: (value) {
                        setState(() {
                          _isActive = value;
                          if (value) {
                            _endTime = null;
                          } else {
                            _endTime ??= DateTime.now();
                          }
                        });
                      },
                    ),
                    const Divider(height: 24),
                    PrismDateTimePills(
                      label: context.l10n.frontingStart,
                      dateTime: _startTime,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      onChanged: (dt) => setState(() => _startTime = dt),
                    ),
                    if (!_isActive) ...[
                      const SizedBox(height: 16),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrismSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.frontingInfoQuality,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismSelect<SleepQuality>(
                      value: _quality,
                      labelText: context.l10n.frontingSleepQualityLabel,
                      enabled: !_saving,
                      items: SleepQuality.values
                          .map(
                            (quality) => PrismSelectItem(
                              value: quality,
                              label: quality == SleepQuality.unknown
                                  ? context.l10n.frontingInfoQualityUnrated
                                  : quality.localizedLabel(context.l10n),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _quality = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrismTextField(
                controller: _notesController,
                labelText: context.l10n.frontingNotes,
                hintText: context.l10n.frontingEditSleepNotesHint,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}
