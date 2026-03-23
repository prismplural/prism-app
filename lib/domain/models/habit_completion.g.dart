// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'habit_completion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_HabitCompletion _$HabitCompletionFromJson(Map<String, dynamic> json) =>
    _HabitCompletion(
      id: json['id'] as String,
      habitId: json['habitId'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      completedByMemberId: json['completedByMemberId'] as String?,
      notes: json['notes'] as String?,
      wasFronting: json['wasFronting'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    );

Map<String, dynamic> _$HabitCompletionToJson(_HabitCompletion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'habitId': instance.habitId,
      'completedAt': instance.completedAt.toIso8601String(),
      'completedByMemberId': instance.completedByMemberId,
      'notes': instance.notes,
      'wasFronting': instance.wasFronting,
      'rating': instance.rating,
      'createdAt': instance.createdAt.toIso8601String(),
      'modifiedAt': instance.modifiedAt.toIso8601String(),
    };
