import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;

class FrontSessionCommentMapper {
  FrontSessionCommentMapper._();

  static domain.FrontSessionComment toDomain(FrontSessionCommentRow row) {
    return domain.FrontSessionComment(
      id: row.id,
      body: row.body,
      timestamp: row.timestamp,
      createdAt: row.createdAt,
      // targetTime is nullable in v7 — existing rows are backfilled by the
      // Phase 5 app-layer migration. Downstream callers fall back to
      // timestamp when targetTime is null; the mapper returns null as-is
      // (pure translation, no fallback here).
      targetTime: row.targetTime,
      authorMemberId: row.authorMemberId,
    );
  }

  static FrontSessionCommentsCompanion toCompanion(
      domain.FrontSessionComment model) {
    return FrontSessionCommentsCompanion(
      id: Value(model.id),
      body: Value(model.body),
      timestamp: Value(model.timestamp),
      createdAt: Value(model.createdAt),
      targetTime: Value(model.targetTime),
      authorMemberId: Value(model.authorMemberId),
    );
  }
}
