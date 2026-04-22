import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_emoji_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_picker_text_field_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';
import 'package:prism_plurality/shared/widgets/weekday_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

class AddEditHabitSheet extends ConsumerStatefulWidget {
  const AddEditHabitSheet({
    super.key,
    this.existingHabit,
    required this.scrollController,
  });
  final Habit? existingHabit;
  final ScrollController scrollController;

  @override
  ConsumerState<AddEditHabitSheet> createState() => _AddEditHabitSheetState();
}

class _AddEditHabitSheetState extends ConsumerState<AddEditHabitSheet> {
  static const _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _iconController;
  late final TextEditingController _notificationMessageController;

  late HabitFrequency _frequency;
  late Set<int> _weeklyDays;
  late int _intervalDays;
  String? _colorHex;
  bool _notificationsEnabled = false;
  String? _reminderTime;
  String? _assignedMemberId;
  bool _onlyNotifyWhenFronting = false;
  bool _isPrivate = false;

  // Track initial notification state for save toast.
  bool _wasNotificationsEnabled = false;
  String? _initialReminderTime;

  bool get _isEditing => widget.existingHabit != null;

  @override
  void initState() {
    super.initState();
    final habit = widget.existingHabit;
    _nameController = TextEditingController(text: habit?.name ?? '');
    _descriptionController = TextEditingController(
      text: habit?.description ?? '',
    );
    _iconController = TextEditingController(text: habit?.icon ?? '');
    _notificationMessageController = TextEditingController(
      text: habit?.notificationMessage ?? '',
    );

    _frequency = habit?.frequency ?? HabitFrequency.daily;
    _weeklyDays = (habit?.weeklyDays ?? []).toSet();
    _intervalDays = habit?.intervalDays ?? 2;
    _colorHex = habit?.colorHex;
    _notificationsEnabled = habit?.notificationsEnabled ?? false;
    _reminderTime = habit?.reminderTime;
    _assignedMemberId = habit?.assignedMemberId;
    _wasNotificationsEnabled = _notificationsEnabled;
    _initialReminderTime = _reminderTime;
    _onlyNotifyWhenFronting = habit?.onlyNotifyWhenFronting ?? false;
    _isPrivate = habit?.isPrivate ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _iconController.dispose();
    _notificationMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(allMembersProvider);

    final canSave = _nameController.text.trim().isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          PrismSheetTopBar(
            title: _isEditing
                ? context.l10n.habitsEditHabit
                : context.l10n.habitsNewHabit,
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
                // ── Basic Info ─────────────────────────────────
                PrismSectionHeader(
                  title: context.l10n.habitsSectionBasicInfo,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                PrismPickerTextFieldRow(
                  pickerLabel: context.l10n.onboardingAddMemberFieldEmoji,
                  picker: PrismEmojiPicker(
                    emoji: _iconController.text.trim().isNotEmpty
                        ? _iconController.text.trim()
                        : null,
                    onSelected: (emoji) {
                      setState(() {
                        _iconController.text = emoji;
                      });
                    },
                    size: 48,
                  ),
                  field: PrismTextField(
                    controller: _nameController,
                    labelText: context.l10n.habitsFieldName,
                    hintText: context.l10n.habitsFieldNameHint,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                PrismTextField(
                  controller: _descriptionController,
                  labelText: context.l10n.habitsFieldDescription,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _ColorPicker(
                  selectedHex: _colorHex,
                  onChanged: (hex) => setState(() => _colorHex = hex),
                ),

                const SizedBox(height: 24),

                // ── Schedule ───────────────────────────────────
                PrismSectionHeader(
                  title: context.l10n.habitsSectionSchedule,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                PrismSegmentedControl<HabitFrequency>(
                  segments: HabitFrequency.values
                      .map((f) => PrismSegment(value: f, label: f.label))
                      .toList(),
                  selected: _frequency,
                  onChanged: (value) => setState(() => _frequency = value),
                ),
                const SizedBox(height: 12),
                if (_frequency == HabitFrequency.weekly)
                  WeekdayPicker(
                    selected: _weeklyDays,
                    onChanged: (days) => setState(() => _weeklyDays = days),
                  ),
                if (_frequency == HabitFrequency.interval)
                  Row(
                    children: [
                      Text(context.l10n.habitsIntervalEvery),
                      PrismIconButton(
                        icon: AppIcons.remove,
                        onPressed: () => setState(() => _intervalDays--),
                        enabled: _intervalDays > 1,
                        tooltip: context.l10n.habitsIntervalDecrease,
                      ),
                      Text(
                        '$_intervalDays',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      PrismIconButton(
                        icon: AppIcons.add,
                        onPressed: () => setState(() => _intervalDays++),
                        tooltip: context.l10n.habitsIntervalIncrease,
                      ),
                      Text(context.l10n.habitsIntervalDays),
                    ],
                  ),

                const SizedBox(height: 24),

                // ── Notifications ──────────────────────────────
                PrismSectionHeader(
                  title: context.l10n.habitsSectionNotifications,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                PrismSwitchRow(
                  title: context.l10n.habitsEnableReminders,
                  value: _notificationsEnabled,
                  onChanged: (v) => setState(() {
                    _notificationsEnabled = v;
                    // Pre-populate 9:00 AM when enabling notifications for the first time.
                    if (v && _reminderTime == null) {
                      _reminderTime = '09:00';
                    }
                  }),
                ),
                if (_notificationsEnabled) ...[
                  Builder(
                    builder: (anchorContext) => PrismListRow(
                      title: Text(context.l10n.habitsReminderTime),
                      trailing: Text(_formatReminderTime(context)),
                      onTap: () => _pickTime(anchorContext),
                    ),
                  ),
                  PrismTextField(
                    controller: _notificationMessageController,
                    labelText: context.l10n.habitsCustomMessageField,
                  ),
                ],

                const SizedBox(height: 24),

                // ── Assignment ─────────────────────────────────
                PrismSectionHeader(
                  title: context.l10n.habitsSectionAssignment,
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                membersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (members) => PrismSelect<String?>(
                    value: _assignedMemberId,
                    labelText: context.l10n.habitsAssignedMember,
                    items: [
                      PrismSelectItem<String?>(
                        value: null,
                        label: context.l10n.habitsAssignedMemberAnyone,
                      ),
                      ...members.map(
                        (m) => PrismSelectItem<String?>(
                          value: m.id,
                          label: m.name,
                          leading: MemberAvatar(
                            avatarImageData: m.avatarImageData,
                            memberName: m.name,
                            emoji: m.emoji,
                            customColorEnabled: m.customColorEnabled,
                            customColorHex: m.customColorHex,
                            size: 28,
                          ),
                          fieldLeading: MemberAvatar(
                            avatarImageData: m.avatarImageData,
                            memberName: m.name,
                            emoji: m.emoji,
                            customColorEnabled: m.customColorEnabled,
                            customColorHex: m.customColorHex,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _assignedMemberId = v),
                  ),
                ),
                if (_assignedMemberId != null) ...[
                  PrismSwitchRow(
                    title: context.l10n.habitsOnlyNotifyWhenFronting,
                    value: _onlyNotifyWhenFronting,
                    onChanged: (v) =>
                        setState(() => _onlyNotifyWhenFronting = v),
                  ),
                  if (_onlyNotifyWhenFronting)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        context.l10n.habitsOnlyFrontingCaveat,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 24),

                // ── Privacy ────────────────────────────────────
                PrismSwitchRow(
                  title: context.l10n.habitsPrivate,
                  subtitle: context.l10n.habitsPrivateSubtitle,
                  value: _isPrivate,
                  onChanged: (v) => setState(() => _isPrivate = v),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns a locale-formatted time string (e.g. "9:00 AM") from the stored
  /// HH:mm [_reminderTime]. Falls back to "Not set" if no time is stored.
  String _formatReminderTime(BuildContext context) {
    final parsed = _parseTime(_reminderTime);
    if (parsed == null) return context.l10n.habitsReminderTimeNotSet;
    return parsed.format(context);
  }

  Future<void> _pickTime(BuildContext anchorContext) async {
    final initial =
        _parseTime(_reminderTime) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showPrismTimePicker(
      context: context,
      anchorContext: anchorContext,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        _reminderTime =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  TimeOfDay? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final notifier = ref.read(habitNotifierProvider.notifier);

    final habit = Habit(
      id: widget.existingHabit?.id ?? _uuid.v4(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      icon: _iconController.text.trim().isEmpty
          ? null
          : _iconController.text.trim(),
      colorHex: _colorHex,
      isActive: widget.existingHabit?.isActive ?? true,
      createdAt: widget.existingHabit?.createdAt ?? now,
      modifiedAt: now,
      frequency: _frequency,
      weeklyDays: _frequency == HabitFrequency.weekly
          ? (_weeklyDays.toList()..sort())
          : null,
      intervalDays: _frequency == HabitFrequency.interval
          ? _intervalDays
          : null,
      reminderTime: _notificationsEnabled ? _reminderTime : null,
      notificationsEnabled: _notificationsEnabled,
      notificationMessage: _notificationMessageController.text.trim().isEmpty
          ? null
          : _notificationMessageController.text.trim(),
      assignedMemberId: _assignedMemberId,
      onlyNotifyWhenFronting: _onlyNotifyWhenFronting,
      isPrivate: _isPrivate,
      currentStreak: widget.existingHabit?.currentStreak ?? 0,
      bestStreak: widget.existingHabit?.bestStreak ?? 0,
      totalCompletions: widget.existingHabit?.totalCompletions ?? 0,
    );

    if (_isEditing) {
      await notifier.updateHabit(habit);
    } else {
      await notifier.createHabit(habit);
    }

    if (mounted) {
      // Show toast when reminders are first enabled or the time changes.
      if (_notificationsEnabled &&
          (!_wasNotificationsEnabled ||
              _reminderTime != _initialReminderTime)) {
        PrismToast.success(
          context,
          message: context.l10n.habitsReminderSetFor(
            _formatReminderTime(context),
          ),
        );
      }
      context.pop();
    }
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selectedHex, required this.onChanged});

  final String? selectedHex;
  final ValueChanged<String?> onChanged;

  static const _colors = [
    'FF6B6B',
    '4ECDC4',
    '45B7D1',
    'FFA07A',
    '98D8C8',
    'F7DC6F',
    'BB8FCE',
    '85C1E9',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _colors.map((hex) {
        final isSelected = selectedHex == hex;
        return Semantics(
          label: context.l10n.habitsColorSemantics(
            hex,
            isSelected ? context.l10n.habitsColorSelected : '',
          ),
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(isSelected ? null : hex),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Color(0xFF000000 | int.parse(hex, radix: 16)),
                shape: PrismShapes.of(context).avatarShape(),
                borderRadius: PrismShapes.of(context).avatarBorderRadius(),
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : null,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
