import 'package:prism_plurality/domain/models/sleep_session.dart' as domain;

abstract class SleepSessionRepository {
  Stream<List<domain.SleepSession>> watchAllSleepSessions();
  Stream<domain.SleepSession?> watchActiveSleepSession();
  Future<List<domain.SleepSession>> getRecentSleepSessions({int limit = 10});
  Future<void> createSleepSession(domain.SleepSession session);
  Future<void> updateSleepSession(domain.SleepSession session);
  Future<void> endSleepSession(String id, DateTime endTime);
  Future<void> deleteSleepSession(String id);
}
