import 'package:uuid/uuid.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';

/// Bridges typed [FrontingSessionChange] descriptors to the repository and
/// [MutationRunner]. All changes in a batch are wrapped in a single
/// [MutationRunner.run] call so they are atomic from a CRDT sync perspective.
class FrontingChangeExecutor {
  FrontingChangeExecutor({
    required FrontingSessionRepository repository,
    required MutationRunner mutationRunner,
  })  : _repository = repository,
        _mutationRunner = mutationRunner;

  final FrontingSessionRepository _repository;
  final MutationRunner _mutationRunner;

  /// Executes a list of [FrontingSessionChange]s atomically.
  ///
  /// Returns a [MutationResult<void>] — success if all changes applied, failure
  /// if any step threw (including session-not-found for updates).
  Future<MutationResult<void>> execute(
    List<FrontingSessionChange> changes,
  ) async {
    return _mutationRunner.run<void>(
      actionLabel: _buildLabel(changes),
      action: () async {
        for (final change in changes) {
          await _applyChange(change);
        }
      },
    );
  }

  Future<void> _applyChange(FrontingSessionChange change) async {
    switch (change) {
      case CreateSessionChange(:final session):
        final newSession = FrontingSession(
          id: const Uuid().v4(),
          startTime: session.start,
          endTime: session.end,
          memberId: session.memberId,
          coFronterIds: session.coFronterIds,
          notes: session.notes,
          confidence: session.confidenceIndex != null
              ? FrontConfidence.values[session.confidenceIndex!]
              : null,
        );
        await _repository.createSession(newSession);

      case UpdateSessionChange(:final sessionId, :final patch):
        final existing = await _repository.getSessionById(sessionId);
        if (existing == null) {
          throw StateError(
            'FrontingChangeExecutor: session not found for update: $sessionId',
          );
        }
        final updated = _applyPatch(existing, patch);
        await _repository.updateSession(updated);

      case DeleteSessionChange(:final sessionId):
        await _repository.deleteSession(sessionId);
    }
  }

  FrontingSession _applyPatch(
    FrontingSession session,
    FrontingSessionPatch patch,
  ) {
    // For nullable fields (endTime, memberId), freezed copyWith treats Dart null
    // as an explicit "set to null" — the freezed sentinel is used to mean
    // "leave unchanged". So we can use copyWith safely for most fields,
    // but must build the full constructor when clearEnd or clearMemberId is set.
    final needsFullConstructor = patch.clearEnd || patch.clearMemberId;

    if (needsFullConstructor) {
      return FrontingSession(
        id: session.id,
        startTime: patch.start ?? session.startTime,
        endTime: patch.clearEnd ? null : (patch.end ?? session.endTime),
        memberId:
            patch.clearMemberId ? null : (patch.memberId ?? session.memberId),
        coFronterIds: patch.coFronterIds ?? session.coFronterIds,
        notes: patch.notes ?? session.notes,
        confidence: patch.confidenceIndex != null
            ? FrontConfidence.values[patch.confidenceIndex!]
            : session.confidence,
        pluralkitUuid: session.pluralkitUuid,
      );
    }

    return session.copyWith(
      startTime: patch.start ?? session.startTime,
      endTime: patch.end ?? session.endTime,
      memberId: patch.memberId ?? session.memberId,
      coFronterIds: patch.coFronterIds ?? session.coFronterIds,
      notes: patch.notes ?? session.notes,
      confidence: patch.confidenceIndex != null
          ? FrontConfidence.values[patch.confidenceIndex!]
          : session.confidence,
    );
  }

  String _buildLabel(List<FrontingSessionChange> changes) {
    if (changes.isEmpty) return 'apply 0 session changes';
    if (changes.length == 1) {
      return switch (changes.first) {
        CreateSessionChange() => 'create fronting session',
        UpdateSessionChange() => 'update fronting session',
        DeleteSessionChange() => 'delete fronting session',
      };
    }
    return 'apply ${changes.length} fronting session changes';
  }
}
