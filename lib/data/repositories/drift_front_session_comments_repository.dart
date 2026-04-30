import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/front_session_comments_dao.dart';
import 'package:prism_plurality/data/mappers/front_session_comment_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
import 'package:prism_plurality/domain/utils/time_range.dart';

class DriftFrontSessionCommentsRepository
    with SyncRecordMixin
    implements FrontSessionCommentsRepository {
  final FrontSessionCommentsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'front_session_comments';

  DriftFrontSessionCommentsRepository(this._dao, this._syncHandle);

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Returns comments whose [domain.FrontSessionComment.targetTime] falls in
  /// [range] (inclusive start, exclusive end).
  ///
  /// Filtering happens in SQL — backed by `idx_comments_target_time` — so
  /// each watcher only wakes when a row in its own range changes.
  /// Comments with `targetTime == null` are excluded; see the
  /// repository-interface docstring for the rationale.
  @override
  Stream<List<domain.FrontSessionComment>> watchCommentsForRange(
    TimeRange range,
  ) {
    return _dao
        .watchCommentsForRange(range.start, range.end)
        .map((rows) => rows.map(FrontSessionCommentMapper.toDomain).toList());
  }

  /// Comment count for a time range. Pre-backfill (null targetTime) rows
  /// are excluded — see [watchCommentsForRange].
  @override
  Stream<int> watchCommentCountForRange(TimeRange range) {
    return _dao.watchCommentCountForRange(range.start, range.end);
  }

  @override
  Stream<List<domain.FrontSessionComment>> watchAllComments() {
    return _dao.watchAllComments().map(
      (rows) => rows.map(FrontSessionCommentMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.FrontSessionComment>> getAllComments() async {
    final rows = await _dao.getAllComments();
    return rows.map(FrontSessionCommentMapper.toDomain).toList();
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  @override
  Future<void> createComment(domain.FrontSessionComment comment) async {
    final companion = FrontSessionCommentMapper.toCompanion(comment);
    await _dao.createComment(companion);
    await syncRecordCreate(_table, comment.id, _commentFields(comment));
  }

  @override
  Future<void> updateComment(domain.FrontSessionComment comment) async {
    final companion = FrontSessionCommentMapper.toCompanion(comment);
    await _dao.updateComment(comment.id, companion);
    await syncRecordUpdate(_table, comment.id, _commentFields(comment));
  }

  @override
  Future<void> deleteComment(String id) async {
    await _dao.deleteComment(id);
    await syncRecordDelete(_table, id);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Visible-for-testing: builds the field map this repository hands to the
  /// Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC — see
  /// drift_front_session_comments_repository_test.
  @visibleForTesting
  Map<String, dynamic> debugCommentFields(domain.FrontSessionComment c) =>
      _commentFields(c);

  Map<String, dynamic> _commentFields(domain.FrontSessionComment c) {
    return {
      // session_id column still exists in v7 Drift schema (dropped in
      // schema cleanup via TableMigration rebuild); leave null on new
      // inserts so the column stays inert. Do NOT write a session_id
      // here — new comments are anchored to target_time, not a session FK.
      'target_time': toSyncUtcOrNull(c.targetTime),
      'author_member_id': c.authorMemberId,
      'body': c.body,
      'timestamp': toSyncUtc(c.timestamp),
      'created_at': toSyncUtc(c.createdAt),
      'is_deleted': false,
    };
  }
}
