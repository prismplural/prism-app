import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:uuid/uuid.dart';

/// Pure Dart service for managing fronter transitions.
///
/// In the per-member model each member has their own session row; a "transition"
/// is simply ending one member's session and optionally starting another's.
/// All operations are wrapped in a [MutationRunner] transaction so that
/// ending old sessions and creating a new one are atomic — a crash
/// mid-operation will roll back instead of leaving the user with no
/// active fronter.
class SessionTransitionService {
  const SessionTransitionService({required MutationRunner mutationRunner})
    : _mutationRunner = mutationRunner;

  final MutationRunner _mutationRunner;

  static const _uuid = Uuid();

  /// Transitions the current fronter to [newMemberId].
  ///
  /// Ends all active sessions for the specified member (or all active sessions
  /// if [endAllActive] is true) at the current time and, if [newMemberId] is
  /// non-null, starts a new session at the exact same instant to avoid gaps.
  ///
  /// The entire read-end-create sequence runs inside a single database
  /// transaction via [MutationRunner].
  Future<void> transitionFronter({
    required String? newMemberId,
    required FrontingSessionRepository repo,
    bool endAllActive = false,
  }) async {
    await _mutationRunner.runVoid(
      actionLabel: 'Transition fronter',
      action: () async {
        final now = DateTime.now();

        // End currently active sessions.
        if (endAllActive) {
          final activeSessions = await repo.getAllActiveSessionsUnfiltered();
          for (final session in activeSessions) {
            await repo.endSession(session.id, now);
          }
        } else if (newMemberId != null) {
          // Only end the specific member's active sessions (if any) to avoid
          // self-overlap when transitioning a single member.
          final activeSessions = await repo.getAllActiveSessionsUnfiltered();
          final memberSessions =
              activeSessions.where((s) => s.memberId == newMemberId).toList();
          for (final session in memberSessions) {
            await repo.endSession(session.id, now);
          }
        }

        // If a new member is specified, start a new session at the same instant.
        if (newMemberId != null) {
          final newSession = FrontingSession(
            id: _uuid.v4(),
            startTime: now,
            memberId: newMemberId,
          );
          await repo.createSession(newSession);
        }
      },
    );
  }

  /// Ends all currently active sessions at [DateTime.now].
  ///
  /// Runs inside a single database transaction so that either all sessions
  /// are ended or none are (in case of a mid-operation failure).
  Future<void> endAllActiveSessions(FrontingSessionRepository repo) async {
    await _mutationRunner.runVoid(
      actionLabel: 'End all active sessions',
      action: () async {
        final now = DateTime.now();
        final activeSessions = await repo.getAllActiveSessionsUnfiltered();
        for (final session in activeSessions) {
          await repo.endSession(session.id, now);
        }
      },
    );
  }
}
