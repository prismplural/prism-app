import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;

abstract class FrontSessionCommentsRepository {
  /// Comments whose [domain.FrontSessionComment.targetTime] falls in [range].
  ///
  /// Pre-Phase-5 rows (targetTime == null) are excluded from range queries
  /// until the Phase 5 migration backfills real timestamps (spec §3.5).
  Stream<List<domain.FrontSessionComment>> watchCommentsForRange(
      DateTimeRange range);

  /// Count of comments in [range].  Pre-backfill rows (null targetTime) are
  /// excluded — see [watchCommentsForRange].
  Stream<int> watchCommentCountForRange(DateTimeRange range);

  Stream<List<domain.FrontSessionComment>> watchAllComments();
  Future<List<domain.FrontSessionComment>> getAllComments();
  Future<void> createComment(domain.FrontSessionComment comment);
  Future<void> updateComment(domain.FrontSessionComment comment);
  Future<void> deleteComment(String id);
}
