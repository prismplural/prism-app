import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:uuid/uuid.dart';

/// Pure Dart service for managing fronter transitions.
///
/// Ensures seamless handoffs between fronting sessions with no time gaps.
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
  /// Ends all active sessions at the current time and, if [newMemberId] is
  /// non-null, starts a new session at the exact same instant to avoid gaps.
  /// Optional [coFronterIds] can be provided for co-fronting sessions.
  ///
  /// The entire read-end-create sequence runs inside a single database
  /// transaction via [MutationRunner].
  Future<void> transitionFronter({
    required String? newMemberId,
    List<String>? coFronterIds,
    required FrontingSessionRepository repo,
  }) async {
    await _mutationRunner.runVoid(
      actionLabel: 'Transition fronter',
      action: () async {
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
        final activeSessions = await repo.getActiveSessions();
        for (final session in activeSessions) {
          await repo.endSession(session.id, now);
        }
      },
    );
  }
}
