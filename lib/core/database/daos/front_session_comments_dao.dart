import 'dart:async';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/front_session_comments_table.dart';

part 'front_session_comments_dao.g.dart';

@DriftAccessor(tables: [FrontSessionComments])
class FrontSessionCommentsDao extends DatabaseAccessor<AppDatabase>
    with _$FrontSessionCommentsDaoMixin {
  FrontSessionCommentsDao(super.db);

  Stream<List<FrontSessionCommentRow>> watchCommentsForSession(
    String sessionId,
  ) =>
      (select(frontSessionComments)
            ..where(
              (c) => c.sessionId.equals(sessionId) & c.isDeleted.equals(false),
            )
            ..orderBy([(c) => OrderingTerm.asc(c.timestamp)]))
          .watch();

  Stream<int> watchCommentCount(String sessionId) {
    final count = countAll();
    final query = selectOnly(frontSessionComments)
      ..where(
        frontSessionComments.sessionId.equals(sessionId) &
            frontSessionComments.isDeleted.equals(false),
      )
      ..addColumns([count]);
    return query.watchSingle().map((row) => row.read(count)!);
  }

  /// Watches comments attached to any of [sessionIds] whose user-visible
  /// timestamp falls in `[start, end)`.
  Stream<List<FrontSessionCommentRow>> watchCommentsForPeriod(
    Iterable<String> sessionIds,
    DateTime start,
    DateTime end,
  ) {
    final ids = sessionIds.toSet().toList(growable: false);
    if (ids.isEmpty) return Stream.value(const <FrontSessionCommentRow>[]);
    return (select(frontSessionComments)
          ..where(
            (c) =>
                c.sessionId.isIn(ids) &
                c.isDeleted.equals(false) &
                c.timestamp.isBiggerOrEqualValue(start) &
                c.timestamp.isSmallerThanValue(end),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.timestamp)]))
        .watch();
  }

  Stream<int> watchCommentCountForPeriod(
    Iterable<String> sessionIds,
    DateTime start,
    DateTime end,
  ) {
    final ids = sessionIds.toSet().toList(growable: false);
    if (ids.isEmpty) return Stream.value(0);
    final count = countAll();
    final query = selectOnly(frontSessionComments)
      ..where(
        frontSessionComments.sessionId.isIn(ids) &
            frontSessionComments.isDeleted.equals(false) &
            frontSessionComments.timestamp.isBiggerOrEqualValue(start) &
            frontSessionComments.timestamp.isSmallerThanValue(end),
      )
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

  Future<List<FrontSessionCommentRow>> getActiveCommentsForSession(
    String sessionId, {
    DateTime? atOrAfter,
  }) {
    final query = select(frontSessionComments)
      ..where(
        (c) =>
            c.sessionId.equals(sessionId) &
            c.isDeleted.equals(false) &
            (atOrAfter == null
                ? const Constant(true)
                : c.timestamp.isBiggerOrEqualValue(atOrAfter)),
      )
      ..orderBy([(c) => OrderingTerm.asc(c.timestamp)]);
    return query.get();
  }

  Future<void> reparentComments({
    required String fromSessionId,
    required String toSessionId,
    DateTime? atOrAfter,
  }) {
    final companion = FrontSessionCommentsCompanion(
      sessionId: Value(toSessionId),
    );
    return (update(frontSessionComments)
          ..where(
            (c) =>
                c.sessionId.equals(fromSessionId) &
                c.isDeleted.equals(false) &
                (atOrAfter == null
                    ? const Constant(true)
                    : c.timestamp.isBiggerOrEqualValue(atOrAfter)),
          ))
        .write(companion);
  }

  Future<void> softDeleteCommentsForSession(String sessionId) =>
      (update(frontSessionComments)
            ..where(
              (c) =>
                  c.sessionId.equals(sessionId) & c.isDeleted.equals(false),
            ))
          .write(const FrontSessionCommentsCompanion(isDeleted: Value(true)));

  Future<int> createComment(FrontSessionCommentsCompanion companion) =>
      into(frontSessionComments).insert(companion);

  Future<void> updateComment(
    String id,
    FrontSessionCommentsCompanion companion,
  ) => (update(
    frontSessionComments,
  )..where((c) => c.id.equals(id))).write(companion);

  Future<void> deleteComment(String id) =>
      (update(frontSessionComments)..where((c) => c.id.equals(id))).write(
        const FrontSessionCommentsCompanion(isDeleted: Value(true)),
      );
}
