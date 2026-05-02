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
      // Surface the legacy column on the model so migration/import
      // backfill code can read it. Empty string maps to null so callers
      // don't have to special-case the inert sentinel. Removed in 0.8.0
      // alongside the column drop.
      sessionId: row.sessionId.isEmpty ? null : row.sessionId,
    );
  }

  static FrontSessionCommentsCompanion toCompanion(
    domain.FrontSessionComment model,
  ) {
    // sessionId is a NOT NULL legacy column that the schema cleanup will
    // drop via TableMigration rebuild. Inserts must still satisfy the
    // NOT NULL constraint; we write the model's legacy sessionId when
    // present (so migration/import paths can preserve it) and otherwise
    // an empty-string sentinel — new-shape readers consult target_time,
    // not session_id, and the column is unread by the new code paths.
    //
    // Once the schema rebuild lands and `session_id` is gone, drop the
    // model field and this column write together.
    return FrontSessionCommentsCompanion(
      id: Value(model.id),
      sessionId: Value(model.sessionId ?? ''),
      body: Value(model.body),
      timestamp: Value(model.timestamp),
      createdAt: Value(model.createdAt),
      targetTime: Value(model.targetTime),
      authorMemberId: Value(model.authorMemberId),
    );
  }
}
