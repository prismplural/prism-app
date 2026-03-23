import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/sleep_sessions_table.dart';

part 'sleep_sessions_dao.g.dart';

@DriftAccessor(tables: [SleepSessions])
class SleepSessionsDao extends DatabaseAccessor<AppDatabase>
    with _$SleepSessionsDaoMixin {
  SleepSessionsDao(super.db);

  Stream<List<SleepSession>> watchAllSleepSessions() =>
      (select(sleepSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
          .watch();

  Stream<SleepSession?> watchActiveSleepSession() {
    final query = select(sleepSessions)
      ..where(
          (s) => s.endTime.isNull() & s.isDeleted.equals(false))
      ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Future<List<SleepSession>> getRecentSleepSessions(int limit) =>
      (select(sleepSessions)
            ..where((s) => s.isDeleted.equals(false))
            ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
            ..limit(limit))
          .get();

  Future<int> createSleepSession(SleepSessionsCompanion session) =>
      into(sleepSessions).insert(session);

  Future<void> updateSleepSession(
      String id, SleepSessionsCompanion session) {
    return (update(sleepSessions)..where((s) => s.id.equals(id)))
        .write(session);
  }

  Future<void> endSleepSession(String id, DateTime endTime) =>
      (update(sleepSessions)..where((s) => s.id.equals(id))).write(
          SleepSessionsCompanion(endTime: Value(endTime)));

  Future<void> deleteSleepSession(String id) =>
      (update(sleepSessions)..where((s) => s.id.equals(id))).write(
          const SleepSessionsCompanion(isDeleted: Value(true)));
}
