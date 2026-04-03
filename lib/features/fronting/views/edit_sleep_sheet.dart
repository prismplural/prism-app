import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

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
      builder: (context, scrollController) => EditSleepSheet(
        session: session,
        scrollController: scrollController,
      ),
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

  Future<void> _pickStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _startTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickEndTime() async {
    final initial = _endTime ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _startTime,
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    setState(() {
      _endTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _isActive = false;
    });
  }

  Future<void> _save() async {
    final notes = _notesController.text.trim();
    final endTime = _isActive ? null : (_endTime ?? DateTime.now());

    if (endTime != null && !endTime.isAfter(_startTime)) {
      if (!mounted) return;
      PrismToast.error(
        context,
        message: 'End time must be after start time.',
      );
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(AppIcons.playArrowRounded),
                        title: const Text('Start Time'),
                        subtitle: Text(_formatDateTime(_startTime)),
                        trailing: Icon(AppIcons.edit),
                        onTap: _pickStartTime,
                      ),
                      if (!_isActive) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(AppIcons.stopRounded),
                          title: const Text('End Time'),
                          subtitle: Text(
                            _endTime != null
                                ? _formatDateTime(_endTime!)
                                : 'Tap to set',
                          ),
                          trailing: Icon(AppIcons.edit),
                          onTap: _pickEndTime,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                      DropdownButtonFormField<SleepQuality>(
                        initialValue: _quality,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Sleep quality',
                        ),
                        items: SleepQuality.values
                            .map(
                              (quality) => DropdownMenuItem(
                                value: quality,
                                child: Text(
                                  quality == SleepQuality.unknown
                                      ? 'Unrated'
                                      : quality.label,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _quality = value);
                              },
                      ),
                    ],
                  ),
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

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[dt.month - 1];
    return '$month ${dt.day}, $hour:$minute $period';
  }
}
