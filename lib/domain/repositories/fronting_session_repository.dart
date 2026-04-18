import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

abstract class FrontingSessionRepository {
  Future<List<domain.FrontingSession>> getAllSessions();
  Future<List<domain.FrontingSession>> getFrontingSessions();
  Stream<List<domain.FrontingSession>> watchAllSessions();
  Future<List<domain.FrontingSession>> getActiveSessions();
  Future<List<domain.FrontingSession>> getAllActiveSessionsUnfiltered();
  Stream<List<domain.FrontingSession>> watchActiveSessions();
  Future<domain.FrontingSession?> getActiveSession();
  Stream<domain.FrontingSession?> watchActiveSession();
  Stream<domain.FrontingSession?> watchActiveSleepSession();
  Stream<List<domain.FrontingSession>> watchAllSleepSessions();
  Future<domain.FrontingSession?> getSessionById(String id);
  Stream<domain.FrontingSession?> watchSessionById(String id);
  Future<List<domain.FrontingSession>> getSessionsForMember(String memberId);
  Future<List<domain.FrontingSession>> getRecentSessions({int limit = 20});
  Future<List<domain.FrontingSession>> getRecentSleepSessions({int limit = 10});
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20});
  Stream<List<domain.FrontingSession>> watchRecentAllSessions({int limit = 30});
  Future<void> createSession(domain.FrontingSession session);
  Future<void> updateSession(domain.FrontingSession session);
  Future<void> endSession(String id, DateTime endTime);
  Future<void> deleteSession(String id);
  Future<List<domain.FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  );
  Future<int> getCount();
  Future<int> getFrontingCount();

  // -- Plan 02 (PK deletion push) ------------------------------------------

  /// Soft-deleted sessions with a stamped PK switch UUID and intent epoch.
  Future<List<domain.FrontingSession>> getDeletedLinkedSessions();

  /// Clear `pluralkitUuid` on a tombstone row and emit a CRDT op. R3.
  Future<void> clearPluralKitLink(String id);

  /// Synced cross-device coordination stamp. R6.
  Future<void> stampDeletePushStartedAt(String id, int timestampMs);
  Future<Map<String, int>> getMemberFrontingCounts({
    int recentLimit = 50,
    int? startHour,
    int? endHour,
    int? withinDays,
  });
}
