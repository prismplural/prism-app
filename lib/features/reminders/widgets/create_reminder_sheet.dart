import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/features/reminders/providers/reminders_providers.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/headmate_picker.dart';
import 'package:prism_plurality/shared/widgets/info_banner.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';
import 'package:prism_plurality/shared/widgets/weekday_picker.dart';

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
  late ReminderFrequency _frequency;
  late Set<int> _weeklyDays;
  int? _intervalDays;
  TimeOfDay? _timeOfDay;
  int? _delayHours;
  String? _targetMemberId;

  bool get _isEditing => widget.editing != null;
  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      !(_trigger == ReminderTrigger.scheduled &&
          _frequency == ReminderFrequency.weekly &&
          _weeklyDays.isEmpty);

  @override
  void initState() {
    super.initState();
    final r = widget.editing;
    _nameController = TextEditingController(text: r?.name ?? '');
    _messageController = TextEditingController(text: r?.message ?? '');
    _trigger = r?.trigger ?? ReminderTrigger.scheduled;
    _frequency = r?.frequency ?? ReminderFrequency.daily;
    _weeklyDays = r?.weeklyDays?.toSet() ?? <int>{};
    // Interval dropdown now starts at 2 (1 is represented by the Daily
    // frequency). If editing a reminder that arrived here with intervalDays=1
    // under the interval frequency, bump it up to a valid option.
    final editingInterval = r?.intervalDays;
    _intervalDays = (_frequency == ReminderFrequency.interval &&
            (editingInterval == null || editingInterval < 2))
        ? 2
        : (editingInterval ?? 2);
    _delayHours = r?.delayHours ?? 0;
    _targetMemberId = r?.targetMemberId;
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
                  // Schedule section: frequency + frequency-specific fields.
                  Text(context.l10n.remindersScheduleLabel, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  PrismSegmentedControl<ReminderFrequency>(
                    segments: [
                      PrismSegment(
                        value: ReminderFrequency.daily,
                        label: context.l10n.remindersSubtitleDaily,
                      ),
                      PrismSegment(
                        value: ReminderFrequency.weekly,
                        label: context.l10n.remindersFrequencyWeekly,
                      ),
                      PrismSegment(
                        value: ReminderFrequency.interval,
                        label: context.l10n.remindersFrequencyInterval,
                      ),
                    ],
                    selected: _frequency,
                    onChanged: (value) => setState(() {
                      _frequency = value;
                      // Keep interval dropdown on a valid option when
                      // switching into the interval frequency.
                      if (value == ReminderFrequency.interval &&
                          (_intervalDays == null || _intervalDays! < 2)) {
                        _intervalDays = 2;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (_frequency == ReminderFrequency.weekly) ...[
                    WeekdayPicker(
                      selected: _weeklyDays,
                      onChanged: (days) =>
                          setState(() => _weeklyDays = days),
                    ),
                    if (_weeklyDays.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.remindersWeeklyEmptyHelper,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ] else if (_frequency == ReminderFrequency.interval) ...[
                    _LabeledRow(
                      label: context.l10n.remindersRepeatEveryLabel,
                      child: PrismSelect<int>.compact(
                        value: _intervalDays ?? 2,
                        menuWidth: 180,
                        items: [
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
                  ],
                  // Time picker (all scheduled frequencies have a time).
                  _LabeledRow(
                    label: context.l10n.remindersTimeLabel,
                    child: Builder(
                      builder: (anchorContext) => PrismButton(
                        label: _timeOfDay?.format(context) ?? '9:00 AM',
                        tone: PrismButtonTone.subtle,
                        onPressed: () async {
                          final picked = await showPrismTimePicker(
                            context: context,
                            anchorContext: anchorContext,
                            initialTime: _timeOfDay ??
                                const TimeOfDay(hour: 9, minute: 0),
                          );
                          if (picked != null) {
                            setState(() => _timeOfDay = picked);
                          }
                        },
                      ),
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
                  const SizedBox(height: 16),

                  // Optional member target. null = any front change (current
                  // behavior). Non-null narrows firing to switches where this
                  // member is in the current fronter set.
                  Text(
                    context.l10n.remindersTargetLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  HeadmatePicker(
                    selectedMemberId: _targetMemberId,
                    includeUnknown: true,
                    label: context.l10n.remindersTargetAny,
                    onSelected: (id) => setState(() => _targetMemberId = id),
                  ),
                  if (_targetMemberId != null) ...[
                    const SizedBox(height: 12),
                    // Honesty disclosure: Prism's relay is zero-knowledge, so
                    // member-targeted reminders can't be push-delivered — they
                    // only fire when THIS device observes the switch.
                    InfoBanner(
                      icon: AppIcons.infoOutlineRounded,
                      iconColor: theme.colorScheme.primary,
                      title: context.l10n.remindersTargetLabel,
                      message: context.l10n.remindersTargetDisclosure,
                    ),
                  ],
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

    final isScheduled = _trigger == ReminderTrigger.scheduled;
    final frequency = isScheduled ? _frequency : ReminderFrequency.daily;
    final weeklyDays =
        isScheduled && _frequency == ReminderFrequency.weekly
            ? (_weeklyDays.toList()..sort())
            : null;
    final intervalDays =
        isScheduled && _frequency == ReminderFrequency.interval
            ? _intervalDays
            : null;

    final targetMemberId =
        _trigger == ReminderTrigger.onFrontChange ? _targetMemberId : null;

    if (_isEditing) {
      notifier.updateReminder(
        widget.editing!.copyWith(
          name: name,
          message: message,
          trigger: _trigger,
          frequency: frequency,
          weeklyDays: weeklyDays,
          intervalDays: intervalDays,
          timeOfDay: isScheduled ? timeStr : null,
          delayHours: _trigger == ReminderTrigger.onFrontChange
              ? _delayHours
              : null,
          targetMemberId: targetMemberId,
        ),
      );
    } else {
      notifier.createReminder(
        name: name,
        message: message,
        trigger: _trigger,
        frequency: frequency,
        weeklyDays: weeklyDays,
        intervalDays: intervalDays,
        timeOfDay: isScheduled ? timeStr : null,
        delayHours: _trigger == ReminderTrigger.onFrontChange
            ? _delayHours
            : null,
        targetMemberId: targetMemberId,
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
