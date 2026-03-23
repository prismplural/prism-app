import 'package:prism_plurality/domain/models/front_session_comment.dart'
    as domain;

abstract class FrontSessionCommentsRepository {
  Stream<List<domain.FrontSessionComment>> watchCommentsForSession(
      String sessionId);
  Stream<int> watchCommentCount(String sessionId);
  Future<void> createComment(domain.FrontSessionComment comment);
  Future<void> updateComment(domain.FrontSessionComment comment);
  Future<void> deleteComment(String id);
}
