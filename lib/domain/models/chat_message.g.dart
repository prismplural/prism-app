// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => _ChatMessage(
  id: json['id'] as String,
  content: json['content'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  isSystemMessage: json['isSystemMessage'] as bool? ?? false,
  editedAt: json['editedAt'] == null
      ? null
      : DateTime.parse(json['editedAt'] as String),
  authorId: json['authorId'] as String?,
  conversationId: json['conversationId'] as String,
  reactions:
      (json['reactions'] as List<dynamic>?)
          ?.map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  replyToId: json['replyToId'] as String?,
  replyToAuthorId: json['replyToAuthorId'] as String?,
  replyToContent: json['replyToContent'] as String?,
);

Map<String, dynamic> _$ChatMessageToJson(_ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'content': instance.content,
      'timestamp': instance.timestamp.toIso8601String(),
      'isSystemMessage': instance.isSystemMessage,
      'editedAt': instance.editedAt?.toIso8601String(),
      'authorId': instance.authorId,
      'conversationId': instance.conversationId,
      'reactions': instance.reactions,
      'replyToId': instance.replyToId,
      'replyToAuthorId': instance.replyToAuthorId,
      'replyToContent': instance.replyToContent,
    };
