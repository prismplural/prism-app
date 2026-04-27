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
    // sessionId is a NOT NULL legacy column that v8 cleanup will drop via
    // TableMigration rebuild. v7-era inserts must still satisfy the NOT
    // NULL constraint; we write an empty string (the inert sentinel)
    // since new-shape readers consult target_time, not session_id, and
    // the column is unread by the new code paths.
    //
    // TODO(phase-5d): once the v8 schema rebuild lands and `session_id`
    // is gone, drop the explicit empty-string write here.
    return FrontSessionCommentsCompanion(
      id: Value(model.id),
      sessionId: const Value(''),
      body: Value(model.body),
      timestamp: Value(model.timestamp),
      createdAt: Value(model.createdAt),
      targetTime: Value(model.targetTime),
      authorMemberId: Value(model.authorMemberId),
    );
  }
}
