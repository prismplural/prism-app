// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sleep_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SleepSession _$SleepSessionFromJson(Map<String, dynamic> json) =>
    _SleepSession(
      id: json['id'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      quality:
          $enumDecodeNullable(_$SleepQualityEnumMap, json['quality']) ??
          SleepQuality.unknown,
      notes: json['notes'] as String?,
      isHealthKitImport: json['isHealthKitImport'] as bool? ?? false,
    );

Map<String, dynamic> _$SleepSessionToJson(_SleepSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'quality': _$SleepQualityEnumMap[instance.quality]!,
      'notes': instance.notes,
      'isHealthKitImport': instance.isHealthKitImport,
    };

const _$SleepQualityEnumMap = {
  SleepQuality.unknown: 'unknown',
  SleepQuality.veryPoor: 'veryPoor',
  SleepQuality.poor: 'poor',
  SleepQuality.fair: 'fair',
  SleepQuality.good: 'good',
  SleepQuality.excellent: 'excellent',
};
