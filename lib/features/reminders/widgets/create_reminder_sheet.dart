import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
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
    final timeOfDay = r?.timeOfDay;
    if (timeOfDay != null) {
      final parts = timeOfDay.split(':');
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
            title: _isEditing ? context.l10n.remindersEditTitle : context.l10n.remindersNewTitle,
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
                  labelText: context.l10n.remindersNameLabel,
                  autofocus: !_isEditing,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                PrismTextField(
                  controller: _messageController,
                  labelText: context.l10n.remindersMessageLabel,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Trigger type
                Text(context.l10n.remindersTriggerLabel, style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                PrismSegmentedControl<ReminderTrigger>(
                  segments: [
                    PrismSegment(
                      value: ReminderTrigger.scheduled,
                      label: context.l10n.remindersScheduled,
                    ),
                    PrismSegment(
                      value: ReminderTrigger.onFrontChange,
                      label: context.l10n.remindersTriggerFrontChange,
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
                    label: context.l10n.remindersRepeatEveryLabel,
                    child: PrismSelect<int>.compact(
                      value: _intervalDays ?? 1,
                      menuWidth: 180,
                      items: [
                        PrismSelectItem(value: 1, label: context.l10n.remindersIntervalDays(1)),
                        PrismSelectItem(value: 2, label: context.l10n.remindersIntervalDays(2)),
                        PrismSelectItem(value: 3, label: context.l10n.remindersIntervalDays(3)),
                        PrismSelectItem(value: 7, label: context.l10n.remindersIntervalDays(7)),
                        PrismSelectItem(value: 14, label: context.l10n.remindersIntervalDays(14)),
                        PrismSelectItem(value: 30, label: context.l10n.remindersIntervalDays(30)),
                      ],
                      onChanged: (v) => setState(() => _intervalDays = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Time picker
                  _LabeledRow(
                    label: context.l10n.remindersTimeLabel,
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
                    label: context.l10n.remindersDelayLabel,
                    child: PrismSelect<int>.compact(
                      value: _delayHours ?? 0,
                      menuWidth: 180,
                      items: [
                        PrismSelectItem(value: 0, label: context.l10n.remindersImmediately),
                        PrismSelectItem(value: 1, label: context.l10n.remindersDelayHours(1)),
                        PrismSelectItem(value: 2, label: context.l10n.remindersDelayHours(2)),
                        PrismSelectItem(value: 4, label: context.l10n.remindersDelayHours(4)),
                        PrismSelectItem(value: 8, label: context.l10n.remindersDelayHours(8)),
                        PrismSelectItem(value: 12, label: context.l10n.remindersDelayHours(12)),
                      ],
                      onChanged: (v) => setState(() => _delayHours = v),
                    ),
                  ),
                ],

                if (_isEditing) ...[
                  const SizedBox(height: 24),
                  PrismButton(
                    label: context.l10n.delete,
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
