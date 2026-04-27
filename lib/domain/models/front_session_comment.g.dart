// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'front_session_comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FrontSessionComment _$FrontSessionCommentFromJson(Map<String, dynamic> json) =>
    _FrontSessionComment(
      id: json['id'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      targetTime: json['targetTime'] == null
          ? null
          : DateTime.parse(json['targetTime'] as String),
      authorMemberId: json['authorMemberId'] as String?,
    );

Map<String, dynamic> _$FrontSessionCommentToJson(
  _FrontSessionComment instance,
) => <String, dynamic>{
  'id': instance.id,
  'body': instance.body,
  'timestamp': instance.timestamp.toIso8601String(),
  'createdAt': instance.createdAt.toIso8601String(),
  'targetTime': instance.targetTime?.toIso8601String(),
  'authorMemberId': instance.authorMemberId,
};
