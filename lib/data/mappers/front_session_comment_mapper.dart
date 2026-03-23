import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;

class FrontSessionCommentMapper {
  FrontSessionCommentMapper._();

  static domain.FrontSessionComment toDomain(FrontSessionCommentRow row) {
    return domain.FrontSessionComment(
      id: row.id,
      sessionId: row.sessionId,
      body: row.body,
      timestamp: row.timestamp,
      createdAt: row.createdAt,
    );
  }

  static FrontSessionCommentsCompanion toCompanion(
      domain.FrontSessionComment model) {
    return FrontSessionCommentsCompanion(
      id: Value(model.id),
      sessionId: Value(model.sessionId),
      body: Value(model.body),
      timestamp: Value(model.timestamp),
      createdAt: Value(model.createdAt),
    );
  }
}
