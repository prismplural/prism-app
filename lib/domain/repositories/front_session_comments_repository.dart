import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;
import 'package:prism_plurality/domain/utils/time_range.dart';

abstract class FrontSessionCommentsRepository {
  Stream<List<domain.FrontSessionComment>> watchCommentsForSession(
    String sessionId,
  );

  Stream<int> watchCommentCount(String sessionId);

  /// Comments attached to one of [sessionIds] whose user-visible timestamp
  /// falls in [range]. Used by derived period detail views.
  Stream<List<domain.FrontSessionComment>> watchCommentsForPeriod({
    required Iterable<String> sessionIds,
    required TimeRange range,
  });

  Stream<int> watchCommentCountForPeriod({
    required Iterable<String> sessionIds,
    required TimeRange range,
  });

  Stream<List<domain.FrontSessionComment>> watchAllComments();
  Future<List<domain.FrontSessionComment>> getAllComments();
  Future<void> createComment(domain.FrontSessionComment comment);
  Future<void> updateComment(domain.FrontSessionComment comment);
  Future<void> deleteComment(String id);
  Future<void> reparentComments({
    required String fromSessionId,
    required String toSessionId,
  });
  Future<void> reparentCommentsAtOrAfter({
    required String fromSessionId,
    required String toSessionId,
    required DateTime atOrAfter,
  });
}
