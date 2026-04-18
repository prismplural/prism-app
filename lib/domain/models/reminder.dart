import 'package:freezed_annotation/freezed_annotation.dart';

part 'reminder.freezed.dart';
part 'reminder.g.dart';

enum ReminderTrigger {
  scheduled,
  onFrontChange;
}

enum ReminderFrequency {
  daily,
  weekly,
  interval;
}

@freezed
abstract class Reminder with _$Reminder {
  const factory Reminder({
    required String id,
    required String name,
    required String message,
    @Default(ReminderTrigger.scheduled) ReminderTrigger trigger,
    @Default(ReminderFrequency.daily) ReminderFrequency frequency,
    List<int>? weeklyDays,
    int? intervalDays,
    String? timeOfDay,
    int? delayHours,
    /// Optional target member ID. null = fires on any front change;
    /// non-null = fires only when the referenced member is in the current
    /// fronter set. Custom fronts are represented as tagged members, so the
    /// same column covers both SP timer type=0 (member) and type=1 (custom
    /// front).
    String? targetMemberId,
    @Default(true) bool isActive,
    required DateTime createdAt,
    required DateTime modifiedAt,
  }) = _Reminder;

  factory Reminder.fromJson(Map<String, dynamic> json) =>
      _$ReminderFromJson(json);
}
