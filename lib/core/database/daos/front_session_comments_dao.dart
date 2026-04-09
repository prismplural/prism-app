import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/front_session_comments_table.dart';

part 'front_session_comments_dao.g.dart';

@DriftAccessor(tables: [FrontSessionComments])
class FrontSessionCommentsDao extends DatabaseAccessor<AppDatabase>
    with _$FrontSessionCommentsDaoMixin {
  FrontSessionCommentsDao(super.db);

  Stream<List<FrontSessionCommentRow>> watchCommentsForSession(
          String sessionId) =>
      (select(frontSessionComments)
            ..where((c) =>
                c.sessionId.equals(sessionId) & c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.timestamp)]))
          .watch();

  Stream<int> watchCommentCount(String sessionId) {
    final count = countAll();
    final query = selectOnly(frontSessionComments)
      ..where(frontSessionComments.sessionId.equals(sessionId) &
          frontSessionComments.isDeleted.equals(false))
      ..addColumns([count]);
    return query.watchSingle().map((row) => row.read(count)!);
  }

  /// Returns all active comments across all sessions.
  Stream<List<FrontSessionCommentRow>> watchAllComments() =>
      (select(frontSessionComments)
            ..where((c) => c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.timestamp)]))
          .watch();

  /// Returns all active comments across all sessions as a future.
  Future<List<FrontSessionCommentRow>> getAllComments() =>
      (select(frontSessionComments)
            ..where((c) => c.isDeleted.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.timestamp)]))
          .get();

  Future<int> createComment(FrontSessionCommentsCompanion companion) =>
      into(frontSessionComments).insert(companion);

  Future<void> updateComment(
          String id, FrontSessionCommentsCompanion companion) =>
      (update(frontSessionComments)..where((c) => c.id.equals(id)))
          .write(companion);

  Future<void> deleteComment(String id) =>
      (update(frontSessionComments)..where((c) => c.id.equals(id)))
          .write(const FrontSessionCommentsCompanion(isDeleted: Value(true)));
}
