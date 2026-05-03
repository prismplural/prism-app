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

  @override
  Stream<List<domain.FrontSessionComment>> watchCommentsForSession(
    String sessionId,
  ) {
    return _dao
        .watchCommentsForSession(sessionId)
        .map((rows) => rows.map(FrontSessionCommentMapper.toDomain).toList());
  }

  @override
  Stream<int> watchCommentCount(String sessionId) {
    return _dao.watchCommentCount(sessionId);
  }

  @override
  Stream<List<domain.FrontSessionComment>> watchCommentsForPeriod({
    required Iterable<String> sessionIds,
    required TimeRange range,
  }) {
    return _dao
        .watchCommentsForPeriod(sessionIds, range.start, range.end)
        .map((rows) => rows.map(FrontSessionCommentMapper.toDomain).toList());
  }

  @override
  Stream<int> watchCommentCountForPeriod({
    required Iterable<String> sessionIds,
    required TimeRange range,
  }) {
    return _dao.watchCommentCountForPeriod(sessionIds, range.start, range.end);
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

  @override
  Future<void> reparentComments({
    required String fromSessionId,
    required String toSessionId,
  }) async {
    await _reparentComments(
      fromSessionId: fromSessionId,
      toSessionId: toSessionId,
    );
  }

  @override
  Future<void> reparentCommentsAtOrAfter({
    required String fromSessionId,
    required String toSessionId,
    required DateTime atOrAfter,
  }) async {
    await _reparentComments(
      fromSessionId: fromSessionId,
      toSessionId: toSessionId,
      atOrAfter: atOrAfter,
    );
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

  Future<void> _reparentComments({
    required String fromSessionId,
    required String toSessionId,
    DateTime? atOrAfter,
  }) async {
    if (fromSessionId == toSessionId) return;
    final rows = await _dao.getActiveCommentsForSession(
      fromSessionId,
      atOrAfter: atOrAfter,
    );
    if (rows.isEmpty) return;
    await _dao.reparentComments(
      fromSessionId: fromSessionId,
      toSessionId: toSessionId,
      atOrAfter: atOrAfter,
    );
    for (final row in rows) {
      final updated = FrontSessionCommentMapper.toDomain(
        row,
      ).copyWith(sessionId: toSessionId);
      await syncRecordUpdate(_table, updated.id, _commentFields(updated));
    }
  }

  Map<String, dynamic> _commentFields(domain.FrontSessionComment c) {
    return {
      'session_id': c.sessionId,
      'body': c.body,
      'timestamp': toSyncUtc(c.timestamp),
      'created_at': toSyncUtc(c.createdAt),
      'is_deleted': false,
    };
  }
}
