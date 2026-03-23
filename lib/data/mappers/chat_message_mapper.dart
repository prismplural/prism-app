import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/chat_message.dart' as domain;
import 'package:prism_plurality/domain/models/message_reaction.dart';

class ChatMessageMapper {
  ChatMessageMapper._();

  static domain.ChatMessage toDomain(ChatMessage row) {
    List<MessageReaction> reactions = [];
    if (row.reactions.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.reactions) as List;
        reactions = decoded
            .map((e) =>
                MessageReaction.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        ErrorReportingService.instance.report(
          'Failed to parse reactions JSON in message ${row.id}: $e',
          severity: ErrorSeverity.warning,
        );
      }
    }

    return domain.ChatMessage(
      id: row.id,
      content: row.content,
      timestamp: row.timestamp,
      isSystemMessage: row.isSystemMessage,
      editedAt: row.editedAt,
      authorId: row.authorId,
      conversationId: row.conversationId,
      reactions: reactions,
      replyToId: row.replyToId,
      replyToAuthorId: row.replyToAuthorId,
      replyToContent: row.replyToContent,
    );
  }

  static ChatMessagesCompanion toCompanion(domain.ChatMessage model) {
    final reactionsJson =
        model.reactions.map((r) => r.toJson()).toList();

    return ChatMessagesCompanion(
      id: Value(model.id),
      content: Value(model.content),
      timestamp: Value(model.timestamp),
      isSystemMessage: Value(model.isSystemMessage),
      editedAt: Value(model.editedAt),
      authorId: Value(model.authorId),
      conversationId: Value(model.conversationId),
      reactions: Value(jsonEncode(reactionsJson)),
      replyToId: Value(model.replyToId),
      replyToAuthorId: Value(model.replyToAuthorId),
      replyToContent: Value(model.replyToContent),
    );
  }
}
