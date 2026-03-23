// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Habit _$HabitFromJson(Map<String, dynamic> json) => _Habit(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  icon: json['icon'] as String?,
  colorHex: json['colorHex'] as String?,
  isActive: json['isActive'] as bool? ?? true,
  createdAt: DateTime.parse(json['createdAt'] as String),
  modifiedAt: DateTime.parse(json['modifiedAt'] as String),
  frequency:
      $enumDecodeNullable(_$HabitFrequencyEnumMap, json['frequency']) ??
      HabitFrequency.daily,
  weeklyDays: (json['weeklyDays'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  intervalDays: (json['intervalDays'] as num?)?.toInt(),
  reminderTime: json['reminderTime'] as String?,
  notificationsEnabled: json['notificationsEnabled'] as bool? ?? false,
  notificationMessage: json['notificationMessage'] as String?,
  assignedMemberId: json['assignedMemberId'] as String?,
  onlyNotifyWhenFronting: json['onlyNotifyWhenFronting'] as bool? ?? false,
  isPrivate: json['isPrivate'] as bool? ?? false,
  currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
  bestStreak: (json['bestStreak'] as num?)?.toInt() ?? 0,
  totalCompletions: (json['totalCompletions'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$HabitToJson(_Habit instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'icon': instance.icon,
  'colorHex': instance.colorHex,
  'isActive': instance.isActive,
  'createdAt': instance.createdAt.toIso8601String(),
  'modifiedAt': instance.modifiedAt.toIso8601String(),
  'frequency': _$HabitFrequencyEnumMap[instance.frequency]!,
  'weeklyDays': instance.weeklyDays,
  'intervalDays': instance.intervalDays,
  'reminderTime': instance.reminderTime,
  'notificationsEnabled': instance.notificationsEnabled,
  'notificationMessage': instance.notificationMessage,
  'assignedMemberId': instance.assignedMemberId,
  'onlyNotifyWhenFronting': instance.onlyNotifyWhenFronting,
  'isPrivate': instance.isPrivate,
  'currentStreak': instance.currentStreak,
  'bestStreak': instance.bestStreak,
  'totalCompletions': instance.totalCompletions,
};

const _$HabitFrequencyEnumMap = {
  HabitFrequency.daily: 'daily',
  HabitFrequency.weekly: 'weekly',
  HabitFrequency.interval: 'interval',
  HabitFrequency.custom: 'custom',
};
