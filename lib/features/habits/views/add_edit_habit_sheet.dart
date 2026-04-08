import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
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
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

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
            title: _isEditing ? 'Edit Habit' : 'New Habit',
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
                const PrismSectionHeader(
                  title: 'BASIC INFO',
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PrismEmojiPicker(
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrismTextField(
                        controller: _nameController,
                        labelText: 'Name',
                        hintText: 'e.g., Morning meditation',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PrismTextField(
                  controller: _descriptionController,
                  labelText: 'Description (optional)',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _ColorPicker(
                  selectedHex: _colorHex,
                  onChanged: (hex) => setState(() => _colorHex = hex),
                ),

                const SizedBox(height: 24),

                // ── Schedule ───────────────────────────────────
                const PrismSectionHeader(
                  title: 'SCHEDULE',
                  padding: EdgeInsets.only(top: 8, bottom: 8),
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
                  _WeekdayPicker(
                    selected: _weeklyDays,
                    onChanged: (days) => setState(() => _weeklyDays = days),
                  ),
                if (_frequency == HabitFrequency.interval)
                  Row(
                    children: [
                      const Text('Every '),
                      PrismIconButton(
                        icon: AppIcons.remove,
                        onPressed: () => setState(() => _intervalDays--),
                        enabled: _intervalDays > 1,
                        tooltip: 'Decrease interval',
                      ),
                      Text(
                        '$_intervalDays',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      PrismIconButton(
                        icon: AppIcons.add,
                        onPressed: () => setState(() => _intervalDays++),
                        tooltip: 'Increase interval',
                      ),
                      const Text(' days'),
                    ],
                  ),

                const SizedBox(height: 24),

                // ── Notifications ──────────────────────────────
                const PrismSectionHeader(
                  title: 'NOTIFICATIONS',
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                PrismSwitchRow(
                  title: 'Enable Reminders',
                  value: _notificationsEnabled,
                  onChanged: (v) => setState(() => _notificationsEnabled = v),
                ),
                if (_notificationsEnabled) ...[
                  PrismListRow(
                    title: const Text('Reminder Time'),
                    trailing: Text(_reminderTime ?? 'Not set'),
                    onTap: _pickTime,
                  ),
                  PrismTextField(
                    controller: _notificationMessageController,
                    labelText: 'Custom message (optional)',
                  ),
                ],

                const SizedBox(height: 24),

                // ── Assignment ─────────────────────────────────
                const PrismSectionHeader(
                  title: 'ASSIGNMENT',
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                ),
                const SizedBox(height: 8),
                membersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error: $e'),
                  data: (members) => PrismSelect<String?>(
                    value: _assignedMemberId,
                    labelText: 'Assigned Member',
                    items: [
                      const PrismSelectItem<String?>(
                        value: null,
                        label: 'Anyone',
                      ),
                      ...members.map(
                        (m) => PrismSelectItem<String?>(
                          value: m.id,
                          label: m.name,
                          leading: MemberAvatar(
                            avatarImageData: m.avatarImageData,
                            emoji: m.emoji,
                            customColorEnabled: m.customColorEnabled,
                            customColorHex: m.customColorHex,
                            size: 28,
                          ),
                          fieldLeading: MemberAvatar(
                            avatarImageData: m.avatarImageData,
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
                if (_assignedMemberId != null)
                  PrismSwitchRow(
                    title: 'Only notify when fronting',
                    value: _onlyNotifyWhenFronting,
                    onChanged: (v) =>
                        setState(() => _onlyNotifyWhenFronting = v),
                  ),

                const SizedBox(height: 24),

                // ── Privacy ────────────────────────────────────
                PrismSwitchRow(
                  title: 'Private',
                  subtitle: 'Hide from shared views',
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

  Future<void> _pickTime() async {
    final initial =
        _parseTime(_reminderTime) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showPrismTimePicker(
      context: context,
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

    if (mounted) context.pop();
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (i) {
        final isSelected = selected.contains(i);
        return PrismChip(
          label: _days[i],
          selected: isSelected,
          onTap: () {
            final newSet = Set<int>.from(selected);
            if (isSelected) {
              newSet.remove(i);
            } else {
              newSet.add(i);
            }
            onChanged(newSet);
          },
        );
      }),
    );
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
          label: 'Color #$hex${isSelected ? ", selected" : ""}',
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(isSelected ? null : hex),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Color(0xFF000000 | int.parse(hex, radix: 16)),
                shape: BoxShape.circle,
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
