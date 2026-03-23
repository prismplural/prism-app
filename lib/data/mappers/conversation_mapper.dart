import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/domain/models/conversation.dart' as domain;

class ConversationMapper {
  ConversationMapper._();

  static domain.Conversation toDomain(Conversation row) {
    List<String> participantIds = [];
    if (row.participantIds.isNotEmpty) {
      try {
        participantIds =
            (jsonDecode(row.participantIds) as List).cast<String>();
      } catch (e) {
        ErrorReportingService.instance.report(
          'Failed to parse JSON field in conversation ${row.id}: $e',
          severity: ErrorSeverity.warning,
        );
      }
    }

    List<String> archivedByMemberIds = [];
    if (row.archivedByMemberIds.isNotEmpty) {
      try {
        archivedByMemberIds =
            (jsonDecode(row.archivedByMemberIds) as List).cast<String>();
      } catch (e) {
        ErrorReportingService.instance.report(
          'Failed to parse JSON field in conversation ${row.id}: $e',
          severity: ErrorSeverity.warning,
        );
      }
    }

    List<String> mutedByMemberIds = [];
    if (row.mutedByMemberIds.isNotEmpty) {
      try {
        mutedByMemberIds =
            (jsonDecode(row.mutedByMemberIds) as List).cast<String>();
      } catch (e) {
        ErrorReportingService.instance.report(
          'Failed to parse JSON field in conversation ${row.id}: $e',
          severity: ErrorSeverity.warning,
        );
      }
    }

    Map<String, DateTime> lastReadTimestamps = {};
    if (row.lastReadTimestamps.isNotEmpty) {
      try {
        final decoded =
            jsonDecode(row.lastReadTimestamps) as Map<String, dynamic>;
        lastReadTimestamps = decoded.map(
          (key, value) => MapEntry(key, DateTime.parse(value as String)),
        );
      } catch (e) {
        ErrorReportingService.instance.report(
          'Failed to parse JSON field in conversation ${row.id}: $e',
          severity: ErrorSeverity.warning,
        );
      }
    }

    return domain.Conversation(
      id: row.id,
      createdAt: row.createdAt,
      lastActivityAt: row.lastActivityAt,
      title: row.title,
      emoji: row.emoji,
      isDirectMessage: row.isDirectMessage,
      creatorId: row.creatorId,
      participantIds: participantIds,
      archivedByMemberIds: archivedByMemberIds,
      mutedByMemberIds: mutedByMemberIds,
      lastReadTimestamps: lastReadTimestamps,
      description: row.description,
      categoryId: row.categoryId,
      displayOrder: row.displayOrder,
    );
  }

  static ConversationsCompanion toCompanion(domain.Conversation model) {
    final lastReadJson = model.lastReadTimestamps.map(
      (key, value) => MapEntry(key, value.toIso8601String()),
    );

    return ConversationsCompanion(
      id: Value(model.id),
      createdAt: Value(model.createdAt),
      lastActivityAt: Value(model.lastActivityAt),
      title: Value(model.title),
      emoji: Value(model.emoji),
      isDirectMessage: Value(model.isDirectMessage),
      creatorId: Value(model.creatorId),
      participantIds: Value(jsonEncode(model.participantIds)),
      archivedByMemberIds: Value(jsonEncode(model.archivedByMemberIds)),
      mutedByMemberIds: Value(jsonEncode(model.mutedByMemberIds)),
      lastReadTimestamps: Value(jsonEncode(lastReadJson)),
      description: Value(model.description),
      categoryId: Value(model.categoryId),
      displayOrder: Value(model.displayOrder),
    );
  }
}
