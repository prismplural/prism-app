// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_board_post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MemberBoardPost _$MemberBoardPostFromJson(Map<String, dynamic> json) =>
    _MemberBoardPost(
      id: json['id'] as String,
      targetMemberId: json['targetMemberId'] as String?,
      authorId: json['authorId'] as String?,
      audience: json['audience'] as String,
      title: json['title'] as String?,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      writtenAt: DateTime.parse(json['writtenAt'] as String),
      editedAt: json['editedAt'] == null
          ? null
          : DateTime.parse(json['editedAt'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
    );

Map<String, dynamic> _$MemberBoardPostToJson(_MemberBoardPost instance) =>
    <String, dynamic>{
      'id': instance.id,
      'targetMemberId': instance.targetMemberId,
      'authorId': instance.authorId,
      'audience': instance.audience,
      'title': instance.title,
      'body': instance.body,
      'createdAt': instance.createdAt.toIso8601String(),
      'writtenAt': instance.writtenAt.toIso8601String(),
      'editedAt': instance.editedAt?.toIso8601String(),
      'isDeleted': instance.isDeleted,
    };
