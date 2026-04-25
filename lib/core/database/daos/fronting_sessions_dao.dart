import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/fronting_sessions_table.dart';

part 'fronting_sessions_dao.g.dart';

const _normalSessionType = 0;
const _sleepSessionType = 1;

@DriftAccessor(tables: [FrontingSessions])
class FrontingSessionsDao extends DatabaseAccessor<AppDatabase>
    with _$FrontingSessionsDaoMixin {
  FrontingSessionsDao(super.db);

  Future<List<FrontingSession>> getAllSessions() =>
      (select(frontingSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  /// Like [getAllSessions] but includes soft-deleted tombstones. Used by
  /// the export importer to detect unique-constraint collisions on
  /// `pluralkit_uuid` against tombstones — the partial unique index
  /// `idx_fronting_sessions_pluralkit_uuid` covers tombstones (no
  /// `is_deleted = 0` clause), so dedup off the active-only
  /// `getAllSessions` set is unsafe.
  Future<List<FrontingSession>> getAllSessionsIncludingDeleted() =>
      (select(frontingSessions)
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Stream<List<FrontingSession>> watchAllSessions() =>
      (select(frontingSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .watch();

  Future<List<FrontingSession>> getActiveSessions() =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.endTime.isNull() &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Stream<List<FrontingSession>> watchActiveSessions() =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.endTime.isNull() &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .watch();

  Future<List<FrontingSession>> getAllActiveSessionsUnfiltered() =>
      (select(frontingSessions)
            ..where((s) => s.endTime.isNull() & s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Future<FrontingSession?> getSessionById(String id) => (select(
    frontingSessions,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  Stream<FrontingSession?> watchSessionById(String id) => (select(
    frontingSessions,
  )..where((s) => s.id.equals(id))).watchSingleOrNull();

  Future<List<FrontingSession>> getSessionsForMember(String memberId) =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.memberId.equals(memberId) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Future<List<FrontingSession>> getRecentSessions({int limit = 20}) =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .get();

  Stream<List<FrontingSession>> watchRecentSessions({int limit = 20}) =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .watch();

  Stream<List<FrontingSession>> watchRecentAllSessions({int limit = 30}) =>
      (select(frontingSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .watch();

  Future<List<FrontingSession>> getFrontingSessions() =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  Stream<FrontingSession?> watchActiveSleepSession() {
    return (select(frontingSessions)
          ..where(
            (s) =>
                s.sessionType.equals(_sleepSessionType) &
                s.endTime.isNull() &
                s.isDeleted.equals(false),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Stream<List<FrontingSession>> watchAllSleepSessions() =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_sleepSessionType) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .watch();

  Future<List<FrontingSession>> getRecentSleepSessions(int limit) =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_sleepSessionType) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .get();

  Future<int> insertSession(FrontingSessionsCompanion session) =>
      into(frontingSessions).insert(session);

  Future<void> updateSession(FrontingSessionsCompanion session) {
    assert(session.id.present, 'Session id is required for update');
    return (update(
      frontingSessions,
    )..where((s) => s.id.equals(session.id.value))).write(session);
  }

  Future<void> softDeleteSession(String id) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
        const FrontingSessionsCompanion(isDeleted: Value(true)),
      );

  /// Tombstoned sessions that still carry a PK switch UUID and a
  /// delete intent epoch. See `MembersDao.getDeletedLinkedMembers` for the
  /// epoch-gated guard that callers must still apply before pushing.
  Future<List<FrontingSession>> getDeletedLinkedSessions() =>
      (select(frontingSessions)
            ..where((s) =>
                s.isDeleted.equals(true) &
                s.pluralkitUuid.isNotNull() &
                s.deleteIntentEpoch.isNotNull()))
          .get();

  /// Plan 02 R3: clear the PK link on a tombstone. Bypasses the
  /// `is_deleted = false` filter. Repository callers should pair this with
  /// a `syncRecordUpdate` so peers converge.
  Future<void> clearPluralKitLinkRaw(String id) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
        const FrontingSessionsCompanion(pluralkitUuid: Value(null)),
      );

  Future<void> stampDeleteIntent(String id, int epoch) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
        FrontingSessionsCompanion(deleteIntentEpoch: Value(epoch)),
      );

  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
        FrontingSessionsCompanion(deletePushStartedAt: Value(timestampMs)),
      );

  Future<void> endSession(String id, DateTime endTime) =>
      (update(frontingSessions)..where((s) => s.id.equals(id))).write(
        FrontingSessionsCompanion(endTime: Value(endTime)),
      );

  Future<List<FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  s.startTime.isBiggerOrEqualValue(start) &
                  s.startTime.isSmallerOrEqualValue(end) &
                  s.isDeleted.equals(false),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .get();

  /// Returns sessions that overlap the [start, end] range.
  /// Includes sessions that started before the range if they end within or
  /// after it, and active (open-ended) sessions.
  Future<List<FrontingSession>> getSessionsInRange(
    DateTime start,
    DateTime end,
  ) =>
      (select(frontingSessions)
            ..where(
              (s) =>
                  s.sessionType.equals(_normalSessionType) &
                  // Session overlaps range if it started before range-end
                  // AND ended after range-start (or is still active).
                  s.startTime.isSmallerOrEqualValue(end) &
                  (s.endTime.isBiggerOrEqualValue(start) | s.endTime.isNull()) &
                  s.isDeleted.equals(false),
            )
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

  Future<int> getFrontingCount() async {
    final count = countAll();
    final query = selectOnly(frontingSessions)
      ..where(
        frontingSessions.sessionType.equals(_normalSessionType) &
            frontingSessions.isDeleted.equals(false),
      )
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }

  /// Returns member_id → session count for non-deleted fronting sessions.
  ///
  /// When [withinDays] is null (default), considers the most recent
  /// [recentLimit] sessions. When set, considers all sessions within
  /// that many days.
  ///
  /// Optional [startHour]/[endHour] filter by local time-of-day
  /// (e.g. 6..11 for morning sessions).
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  }) async {
    final variables = <Variable>[];
    final conditions = <String>[
      'session_type = 0',
      'is_deleted = 0',
      'member_id IS NOT NULL',
    ];

    if (withinDays != null) {
      final cutoff = DateTime.now()
          .subtract(Duration(days: withinDays))
          .millisecondsSinceEpoch;
      conditions.add('start_time > ?');
      variables.add(Variable.withInt(cutoff));
    }

    if (startHour != null && endHour != null) {
      conditions.add(
        "CAST(strftime('%H', datetime(start_time / 1000, 'unixepoch', 'localtime')) AS INTEGER) BETWEEN ? AND ?",
      );
      variables.add(Variable.withInt(startHour));
      variables.add(Variable.withInt(endHour));
    }

    final where = conditions.join(' AND ');

    final String sql;
    if (withinDays != null) {
      // Date-range mode: no LIMIT subquery, count all matching sessions
      sql = 'SELECT member_id, COUNT(*) AS cnt '
          'FROM fronting_sessions WHERE $where '
          'GROUP BY member_id';
    } else {
      // Recent-limit mode: existing behavior with subquery
      sql = 'SELECT member_id, COUNT(*) AS cnt '
          'FROM (SELECT member_id FROM fronting_sessions '
          'WHERE $where ORDER BY start_time DESC LIMIT ?) '
          'GROUP BY member_id';
      variables.add(Variable.withInt(recentLimit));
    }

    final results = await customSelect(sql, variables: variables).get();
    final counts = <String, int>{};
    for (final row in results) {
      counts[row.read<String>('member_id')] = row.read<int>('cnt');
    }
    return counts;
  }
}
