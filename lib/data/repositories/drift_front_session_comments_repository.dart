import 'package:flutter/material.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/front_session_comments_dao.dart';
import 'package:prism_plurality/data/mappers/front_session_comment_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';

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
  /// Comments with `targetTime == null` are excluded: they are pre-Phase-5
  /// rows awaiting backfill and don't fall in any range until Phase 5 writes a
  /// real timestamp.  After backfill every row has a non-null `targetTime`.
  ///
  /// Filtering is done in Dart rather than SQL so we can reuse the DAO's
  /// `watchAllComments()` stream without a new DAO method.  The comment table
  /// is small (typically < few hundred rows per user) so client-side filtering
  /// is fine; if it becomes a concern a dedicated DAO query can replace this.
  @override
  Stream<List<domain.FrontSessionComment>> watchCommentsForRange(
      DateTimeRange range) {
    return _dao.watchAllComments().map((rows) => rows
        .map(FrontSessionCommentMapper.toDomain)
        .where((c) =>
            c.targetTime != null &&
            !c.targetTime!.isBefore(range.start) &&
            c.targetTime!.isBefore(range.end))
        .toList());
  }

  /// Comment count for a time range.  Pre-backfill (null targetTime) rows
  /// are excluded — see [watchCommentsForRange].
  @override
  Stream<int> watchCommentCountForRange(DateTimeRange range) {
    return watchCommentsForRange(range).map((list) => list.length);
  }

  @override
  Stream<List<domain.FrontSessionComment>> watchAllComments() {
    return _dao.watchAllComments().map(
        (rows) => rows.map(FrontSessionCommentMapper.toDomain).toList());
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
      // session_id column still exists in v7 Drift schema (dropped in v8
      // cleanup via TableMigration rebuild); leave null on new inserts so the
      // column stays inert.  Do NOT write a session_id here — new comments
      // are anchored to target_time, not a session FK.
      'target_time': _toSyncUtcOrNull(c.targetTime),
      'author_member_id': c.authorMemberId,
      'body': c.body,
      'timestamp': _toSyncUtc(c.timestamp),
      'created_at': _toSyncUtc(c.createdAt),
      'is_deleted': false,
    };
  }
}

/// Normalizes a DateTime to UTC ISO-8601 (Z-suffixed) for sync wire emission.
///
/// Local DateTimes serialize with no offset/Z, so a peer in a different
/// timezone would parse the value as their own local time and shift the
/// absolute moment by the timezone delta on every sync. Routing every
/// DateTime through here mirrors the `_dateTimeToSyncString` helper in
/// `core/sync/drift_sync_adapter.dart`.
String _toSyncUtc(DateTime dt) => dt.toUtc().toIso8601String();

String? _toSyncUtcOrNull(DateTime? dt) => dt?.toUtc().toIso8601String();
