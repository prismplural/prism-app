// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'front_session_comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FrontSessionComment _$FrontSessionCommentFromJson(Map<String, dynamic> json) =>
    _FrontSessionComment(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$FrontSessionCommentToJson(
  _FrontSessionComment instance,
) => <String, dynamic>{
  'id': instance.id,
  'sessionId': instance.sessionId,
  'body': instance.body,
  'timestamp': instance.timestamp.toIso8601String(),
  'createdAt': instance.createdAt.toIso8601String(),
};
