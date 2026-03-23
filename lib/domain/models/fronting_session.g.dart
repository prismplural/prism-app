// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fronting_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FrontingSession _$FrontingSessionFromJson(Map<String, dynamic> json) =>
    _FrontingSession(
      id: json['id'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] == null
          ? null
          : DateTime.parse(json['endTime'] as String),
      memberId: json['memberId'] as String?,
      coFronterIds:
          (json['coFronterIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      notes: json['notes'] as String?,
      confidence: $enumDecodeNullable(
        _$FrontConfidenceEnumMap,
        json['confidence'],
      ),
      pluralkitUuid: json['pluralkitUuid'] as String?,
    );

Map<String, dynamic> _$FrontingSessionToJson(_FrontingSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startTime': instance.startTime.toIso8601String(),
      'endTime': instance.endTime?.toIso8601String(),
      'memberId': instance.memberId,
      'coFronterIds': instance.coFronterIds,
      'notes': instance.notes,
      'confidence': _$FrontConfidenceEnumMap[instance.confidence],
      'pluralkitUuid': instance.pluralkitUuid,
    };

const _$FrontConfidenceEnumMap = {
  FrontConfidence.unsure: 'unsure',
  FrontConfidence.strong: 'strong',
  FrontConfidence.certain: 'certain',
};
