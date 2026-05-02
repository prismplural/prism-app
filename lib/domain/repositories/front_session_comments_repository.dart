import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;
import 'package:prism_plurality/domain/utils/time_range.dart';

abstract class FrontSessionCommentsRepository {
  /// Comments whose [domain.FrontSessionComment.targetTime] falls in [range].
  ///
  /// Rows with `targetTime == null` are excluded by design: pre-Phase-5
  /// rows haven't been backfilled yet and don't belong to any range until
  /// the migration writes a real value. After backfill every row has a
  /// non-null `targetTime`.
  Stream<List<domain.FrontSessionComment>> watchCommentsForRange(
    TimeRange range,
  );

  /// Count of comments in [range]. Pre-backfill rows (null targetTime) are
  /// excluded — see [watchCommentsForRange].
  Stream<int> watchCommentCountForRange(TimeRange range);

  Stream<List<domain.FrontSessionComment>> watchAllComments();
  Future<List<domain.FrontSessionComment>> getAllComments();
  Future<void> createComment(domain.FrontSessionComment comment);
  Future<void> updateComment(domain.FrontSessionComment comment);
  Future<void> deleteComment(String id);
}
