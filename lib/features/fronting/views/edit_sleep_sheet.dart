import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
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
      PrismToast.error(context, message: 'End time must be after start time.');
      return;
    }

    final mutationService = ref.read(frontingMutationServiceProvider);
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
        PrismToast.error(context, message: 'Error saving sleep session: $e');
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
          title: 'Edit Sleep',
          trailing: PrismGlassIconButton(
            icon: AppIcons.check,
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
                          'Sleep session',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PrismSwitchRow(
                      title: 'Still Sleeping',
                      subtitle: 'Leave the session open-ended',
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
                      label: 'Start',
                      dateTime: _startTime,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      onChanged: (dt) => setState(() => _startTime = dt),
                    ),
                    if (!_isActive) ...[
                      const SizedBox(height: 16),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PrismSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quality',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrismSelect<SleepQuality>(
                      value: _quality,
                      labelText: 'Sleep quality',
                      enabled: !_saving,
                      items: SleepQuality.values
                          .map(
                            (quality) => PrismSelectItem(
                              value: quality,
                              label: quality == SleepQuality.unknown
                                  ? 'Unrated'
                                  : quality.label,
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
                labelText: 'Notes',
                hintText: 'Optional notes about this sleep...',
                alignLabelWithHint: true,
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
