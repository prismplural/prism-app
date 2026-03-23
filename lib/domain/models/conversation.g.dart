// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Conversation _$ConversationFromJson(Map<String, dynamic> json) =>
    _Conversation(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
      title: json['title'] as String?,
      emoji: json['emoji'] as String?,
      isDirectMessage: json['isDirectMessage'] as bool? ?? false,
      creatorId: json['creatorId'] as String?,
      participantIds:
          (json['participantIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      archivedByMemberIds:
          (json['archivedByMemberIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      mutedByMemberIds:
          (json['mutedByMemberIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      lastReadTimestamps:
          (json['lastReadTimestamps'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, DateTime.parse(e as String)),
          ) ??
          const {},
      description: json['description'] as String?,
      categoryId: json['categoryId'] as String?,
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ConversationToJson(_Conversation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastActivityAt': instance.lastActivityAt.toIso8601String(),
      'title': instance.title,
      'emoji': instance.emoji,
      'isDirectMessage': instance.isDirectMessage,
      'creatorId': instance.creatorId,
      'participantIds': instance.participantIds,
      'archivedByMemberIds': instance.archivedByMemberIds,
      'mutedByMemberIds': instance.mutedByMemberIds,
      'lastReadTimestamps': instance.lastReadTimestamps.map(
        (k, e) => MapEntry(k, e.toIso8601String()),
      ),
      'description': instance.description,
      'categoryId': instance.categoryId,
      'displayOrder': instance.displayOrder,
    };
