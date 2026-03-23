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

  @override
  Stream<List<domain.FrontSessionComment>> watchCommentsForSession(
      String sessionId) {
    return _dao.watchCommentsForSession(sessionId).map(
        (rows) => rows.map(FrontSessionCommentMapper.toDomain).toList());
  }

  @override
  Stream<int> watchCommentCount(String sessionId) {
    return _dao.watchCommentCount(sessionId);
  }

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

  Map<String, dynamic> _commentFields(domain.FrontSessionComment c) {
    return {
      'session_id': c.sessionId,
      'body': c.body,
      'timestamp': c.timestamp.toIso8601String(),
      'created_at': c.createdAt.toIso8601String(),
      'is_deleted': false,
    };
  }
}
