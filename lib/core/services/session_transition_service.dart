import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:uuid/uuid.dart';

/// Pure Dart service for managing fronter transitions.
///
/// Ensures seamless handoffs between fronting sessions with no time gaps.
class SessionTransitionService {
  const SessionTransitionService();

  static const _uuid = Uuid();

  /// Transitions the current fronter to [newMemberId].
  ///
  /// Ends all active sessions at the current time and, if [newMemberId] is
  /// non-null, starts a new session at the exact same instant to avoid gaps.
  /// Optional [coFronterIds] can be provided for co-fronting sessions.
  Future<void> transitionFronter({
    required String? newMemberId,
    List<String>? coFronterIds,
    required FrontingSessionRepository repo,
  }) async {
    final now = DateTime.now();

    // End all currently active sessions at exactly [now].
    final activeSessions = await repo.getActiveSessions();
    for (final session in activeSessions) {
      await repo.endSession(session.id, now);
    }

    // If a new member is specified, start a new session at the same instant.
    if (newMemberId != null) {
      final newSession = FrontingSession(
        id: _uuid.v4(),
        startTime: now,
        memberId: newMemberId,
        coFronterIds: coFronterIds ?? const [],
      );
      await repo.createSession(newSession);
    }
  }

  /// Ends all currently active sessions at [DateTime.now].
  Future<void> endAllActiveSessions(FrontingSessionRepository repo) async {
    final now = DateTime.now();
    final activeSessions = await repo.getActiveSessions();
    for (final session in activeSessions) {
      await repo.endSession(session.id, now);
    }
  }
}
