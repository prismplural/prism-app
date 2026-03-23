import 'package:freezed_annotation/freezed_annotation.dart';

part 'reminder.freezed.dart';
part 'reminder.g.dart';

enum ReminderTrigger {
  scheduled,
  onFrontChange;
}

@freezed
abstract class Reminder with _$Reminder {
  const factory Reminder({
    required String id,
    required String name,
    required String message,
    @Default(ReminderTrigger.scheduled) ReminderTrigger trigger,
    int? intervalDays,
    String? timeOfDay,
    int? delayHours,
    @Default(true) bool isActive,
    required DateTime createdAt,
    required DateTime modifiedAt,
  }) = _Reminder;

  factory Reminder.fromJson(Map<String, dynamic> json) =>
      _$ReminderFromJson(json);
}
