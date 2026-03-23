import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

abstract class FrontingSessionRepository {
  Future<List<domain.FrontingSession>> getAllSessions();
  Stream<List<domain.FrontingSession>> watchAllSessions();
  Future<List<domain.FrontingSession>> getActiveSessions();
  Stream<List<domain.FrontingSession>> watchActiveSessions();
  Future<domain.FrontingSession?> getActiveSession();
  Stream<domain.FrontingSession?> watchActiveSession();
  Future<domain.FrontingSession?> getSessionById(String id);
  Stream<domain.FrontingSession?> watchSessionById(String id);
  Future<List<domain.FrontingSession>> getSessionsForMember(String memberId);
  Future<List<domain.FrontingSession>> getRecentSessions({int limit = 20});
  Stream<List<domain.FrontingSession>> watchRecentSessions({int limit = 20});
  Future<void> createSession(domain.FrontingSession session);
  Future<void> updateSession(domain.FrontingSession session);
  Future<void> endSession(String id, DateTime endTime);
  Future<void> deleteSession(String id);
  Future<List<domain.FrontingSession>> getSessionsBetween(
      DateTime start, DateTime end);
  Future<int> getCount();
}
