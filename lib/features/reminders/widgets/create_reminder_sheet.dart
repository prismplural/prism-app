import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

class CreateReminderSheet extends ConsumerStatefulWidget {
  const CreateReminderSheet({super.key, this.editing, this.scrollController});

  final Reminder? editing;
  final ScrollController? scrollController;

  @override
  ConsumerState<CreateReminderSheet> createState() =>
      _CreateReminderSheetState();
}

class _CreateReminderSheetState extends ConsumerState<CreateReminderSheet> {
  late TextEditingController _nameController;
  late TextEditingController _messageController;
  late ReminderTrigger _trigger;
  int? _intervalDays;
  TimeOfDay? _timeOfDay;
  int? _delayHours;

  bool get _isEditing => widget.editing != null;
  bool get _canSave => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    _nameController = TextEditingController(text: r?.name ?? '');
    _messageController = TextEditingController(text: r?.message ?? '');
    _trigger = r?.trigger ?? ReminderTrigger.scheduled;
    _intervalDays = r?.intervalDays ?? 1;
    _delayHours = r?.delayHours ?? 0;
    if (r?.timeOfDay != null) {
      final parts = r!.timeOfDay!.split(':');
      if (parts.length == 2) {
        _timeOfDay = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    _timeOfDay ??= const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _canSave;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: _isEditing ? 'Edit Reminder' : 'New Reminder',
            trailing: PrismGlassIconButton(
              icon: AppIcons.check,
              size: PrismTokens.topBarActionSize,
              tint: canSave ? theme.colorScheme.primary : null,
              accentIcon: canSave,
              onPressed: canSave ? _save : null,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              children: [
                PrismTextField(
                  controller: _nameController,
                  labelText: 'Reminder name',
                  autofocus: !_isEditing,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                PrismTextField(
                  controller: _messageController,
                  labelText: 'Notification message',
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Trigger type
                Text('Trigger', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                PrismSegmentedControl<ReminderTrigger>(
                  segments: [
                    const PrismSegment(
                      value: ReminderTrigger.scheduled,
                      label: 'Scheduled',
                    ),
                    const PrismSegment(
                      value: ReminderTrigger.onFrontChange,
                      label: 'Front Change',
                    ),
                  ],
                  selected: _trigger,
                  onChanged: (value) => setState(() => _trigger = value),
                ),
                const SizedBox(height: 16),

                // Conditional fields
                if (_trigger == ReminderTrigger.scheduled) ...[
                  // Interval picker
                  _LabeledRow(
                    label: 'Repeat every',
                    child: PrismSelect<int>.compact(
                      value: _intervalDays ?? 1,
                      menuWidth: 180,
                      items: const [
                        PrismSelectItem(value: 1, label: '1 day'),
                        PrismSelectItem(value: 2, label: '2 days'),
                        PrismSelectItem(value: 3, label: '3 days'),
                        PrismSelectItem(value: 7, label: '7 days'),
                        PrismSelectItem(value: 14, label: '14 days'),
                        PrismSelectItem(value: 30, label: '30 days'),
                      ],
                      onChanged: (v) => setState(() => _intervalDays = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Time picker
                  _LabeledRow(
                    label: 'Time',
                    child: PrismButton(
                      label: _timeOfDay?.format(context) ?? '9:00 AM',
                      tone: PrismButtonTone.subtle,
                      onPressed: () async {
                        final picked = await showPrismTimePicker(
                          context: context,
                          initialTime:
                              _timeOfDay ?? const TimeOfDay(hour: 9, minute: 0),
                        );
                        if (picked != null) {
                          setState(() => _timeOfDay = picked);
                        }
                      },
                    ),
                  ),
                ] else ...[
                  // Delay picker for front change
                  _LabeledRow(
                    label: 'Delay after front change',
                    child: PrismSelect<int>.compact(
                      value: _delayHours ?? 0,
                      menuWidth: 180,
                      items: const [
                        PrismSelectItem(value: 0, label: 'Immediately'),
                        PrismSelectItem(value: 1, label: '1 hour'),
                        PrismSelectItem(value: 2, label: '2 hours'),
                        PrismSelectItem(value: 4, label: '4 hours'),
                        PrismSelectItem(value: 8, label: '8 hours'),
                        PrismSelectItem(value: 12, label: '12 hours'),
                      ],
                      onChanged: (v) => setState(() => _delayHours = v),
                    ),
                  ),
                ],

                if (_isEditing) ...[
                  const SizedBox(height: 24),
                  PrismButton(
                    label: 'Delete',
                    tone: PrismButtonTone.destructive,
                    onPressed: () {
                      ref
                          .read(remindersNotifierProvider.notifier)
                          .deleteReminder(widget.editing!.id);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final message = _messageController.text.trim();
    if (name.isEmpty || message.isEmpty) return;

    final notifier = ref.read(remindersNotifierProvider.notifier);
    final timeStr = _timeOfDay != null
        ? '${_timeOfDay!.hour.toString().padLeft(2, '0')}:'
              '${_timeOfDay!.minute.toString().padLeft(2, '0')}'
        : null;

    if (_isEditing) {
      notifier.updateReminder(
        widget.editing!.copyWith(
          name: name,
          message: message,
          trigger: _trigger,
          intervalDays: _trigger == ReminderTrigger.scheduled
              ? _intervalDays
              : null,
          timeOfDay: _trigger == ReminderTrigger.scheduled ? timeStr : null,
          delayHours: _trigger == ReminderTrigger.onFrontChange
              ? _delayHours
              : null,
        ),
      );
    } else {
      notifier.createReminder(
        name: name,
        message: message,
        trigger: _trigger,
        intervalDays: _trigger == ReminderTrigger.scheduled
            ? _intervalDays
            : null,
        timeOfDay: _trigger == ReminderTrigger.scheduled ? timeStr : null,
        delayHours: _trigger == ReminderTrigger.onFrontChange
            ? _delayHours
            : null,
      );
    }
    Navigator.of(context).pop();
  }
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        child,
      ],
    );
  }
}
