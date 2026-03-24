import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/fronting_sessions_table.dart';

part 'fronting_sessions_dao.g.dart';

@DriftAccessor(tables: [FrontingSessions])
class FrontingSessionsDao extends DatabaseAccessor<AppDatabase>
    with _$FrontingSessionsDaoMixin {
  FrontingSessionsDao(super.db);

  Future<List<FrontingSession>> getAllSessions() => (select(frontingSessions)
        ..where((s) => s.isDeleted.equals(false))
        ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
      .get();

  Stream<List<FrontingSession>> watchAllSessions() =>
      (select(frontingSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .watch();

  Future<List<FrontingSession>> getActiveSessions() =>
      (select(frontingSessions)
            ..where((s) =>
                s.endTime.isNull() & s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Stream<List<FrontingSession>> watchActiveSessions() =>
      (select(frontingSessions)
            ..where((s) =>
                s.endTime.isNull() & s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .watch();

  Future<FrontingSession?> getSessionById(String id) =>
      (select(frontingSessions)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  Stream<FrontingSession?> watchSessionById(String id) =>
      (select(frontingSessions)..where((s) => s.id.equals(id)))
          .watchSingleOrNull();

  Future<List<FrontingSession>> getSessionsForMember(String memberId) =>
      (select(frontingSessions)
            ..where((s) =>
                s.memberId.equals(memberId) &
                s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Future<List<FrontingSession>> getRecentSessions({int limit = 20}) =>
      (select(frontingSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .get();

  Stream<List<FrontingSession>> watchRecentSessions({int limit = 20}) =>
      (select(frontingSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .watch();

  Future<int> insertSession(FrontingSessionsCompanion session) =>
      into(frontingSessions).insert(session);

  Future<void> updateSession(FrontingSessionsCompanion session) {
    assert(session.id.present, 'Session id is required for update');
    return (update(frontingSessions)
          ..where((s) => s.id.equals(session.id.value)))
        .write(session);
  }

  Future<void> softDeleteSession(String id) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
          const FrontingSessionsCompanion(isDeleted: Value(true)));

  Future<void> endSession(String id, DateTime endTime) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
          FrontingSessionsCompanion(endTime: Value(endTime)));

  Future<List<FrontingSession>> getSessionsBetween(
          DateTime start, DateTime end) =>
      (select(frontingSessions)
            ..where((s) =>
                s.startTime.isBiggerOrEqualValue(start) &
                s.startTime.isSmallerOrEqualValue(end) &
                s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  /// Returns sessions that overlap the [start, end] range.
  /// Includes sessions that started before the range if they end within or
  /// after it, and active (open-ended) sessions.
  Future<List<FrontingSession>> getSessionsInRange(
          DateTime start, DateTime end) =>
      (select(frontingSessions)
            ..where((s) =>
                // Session overlaps range if it started before range-end
                // AND ended after range-start (or is still active).
                s.startTime.isSmallerOrEqualValue(end) &
                (s.endTime.isBiggerOrEqualValue(start) |
                    s.endTime.isNull()) &
                s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(frontingSessions)
      ..where(frontingSessions.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }

  /// Returns a map of member_id -> session count for non-deleted sessions,
  /// considering only the most recent [limit] sessions.
  Future<Map<String, int>> getMemberFrontingCounts({int limit = 50}) async {
    // Use a raw query to COUNT grouped by member_id within the top N sessions.
    final results = await customSelect(
      'SELECT member_id, COUNT(*) AS cnt '
      'FROM (SELECT member_id FROM fronting_sessions '
      '  WHERE is_deleted = 0 AND member_id IS NOT NULL '
      '  ORDER BY start_time DESC LIMIT ?) '
      'GROUP BY member_id',
      variables: [Variable.withInt(limit)],
    ).get();

    final counts = <String, int>{};
    for (final row in results) {
      final memberId = row.read<String>('member_id');
      final count = row.read<int>('cnt');
      counts[memberId] = count;
    }
    return counts;
  }
}
