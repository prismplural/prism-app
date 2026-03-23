import 'package:freezed_annotation/freezed_annotation.dart';

import 'message_reaction.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String content,
    required DateTime timestamp,
    @Default(false) bool isSystemMessage,
    DateTime? editedAt,
    String? authorId,
    required String conversationId,
    @Default([]) List<MessageReaction> reactions,
    String? replyToId,
    String? replyToAuthorId,
    String? replyToContent,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
