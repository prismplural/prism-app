// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poll.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Poll _$PollFromJson(Map<String, dynamic> json) => _Poll(
  id: json['id'] as String,
  question: json['question'] as String,
  description: json['description'] as String?,
  isAnonymous: json['isAnonymous'] as bool? ?? false,
  allowsMultipleVotes: json['allowsMultipleVotes'] as bool? ?? false,
  isClosed: json['isClosed'] as bool? ?? false,
  expiresAt: json['expiresAt'] == null
      ? null
      : DateTime.parse(json['expiresAt'] as String),
  createdAt: DateTime.parse(json['createdAt'] as String),
  options:
      (json['options'] as List<dynamic>?)
          ?.map((e) => PollOption.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$PollToJson(_Poll instance) => <String, dynamic>{
  'id': instance.id,
  'question': instance.question,
  'description': instance.description,
  'isAnonymous': instance.isAnonymous,
  'allowsMultipleVotes': instance.allowsMultipleVotes,
  'isClosed': instance.isClosed,
  'expiresAt': instance.expiresAt?.toIso8601String(),
  'createdAt': instance.createdAt.toIso8601String(),
  'options': instance.options,
};
