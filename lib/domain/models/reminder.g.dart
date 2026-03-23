// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reminder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Reminder _$ReminderFromJson(Map<String, dynamic> json) => _Reminder(
  id: json['id'] as String,
  name: json['name'] as String,
  message: json['message'] as String,
  trigger:
      $enumDecodeNullable(_$ReminderTriggerEnumMap, json['trigger']) ??
      ReminderTrigger.scheduled,
  intervalDays: (json['intervalDays'] as num?)?.toInt(),
  timeOfDay: json['timeOfDay'] as String?,
  delayHours: (json['delayHours'] as num?)?.toInt(),
  isActive: json['isActive'] as bool? ?? true,
  createdAt: DateTime.parse(json['createdAt'] as String),
  modifiedAt: DateTime.parse(json['modifiedAt'] as String),
);

Map<String, dynamic> _$ReminderToJson(_Reminder instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'message': instance.message,
  'trigger': _$ReminderTriggerEnumMap[instance.trigger]!,
  'intervalDays': instance.intervalDays,
  'timeOfDay': instance.timeOfDay,
  'delayHours': instance.delayHours,
  'isActive': instance.isActive,
  'createdAt': instance.createdAt.toIso8601String(),
  'modifiedAt': instance.modifiedAt.toIso8601String(),
};

const _$ReminderTriggerEnumMap = {
  ReminderTrigger.scheduled: 'scheduled',
  ReminderTrigger.onFrontChange: 'onFrontChange',
};
