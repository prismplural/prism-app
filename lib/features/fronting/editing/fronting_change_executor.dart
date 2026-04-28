import 'package:uuid/uuid.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';

/// Bridges typed [FrontingSessionChange] descriptors to the repository and
/// [MutationRunner]. All changes in a batch are wrapped in a single
/// [MutationRunner.run] call so they are atomic from a CRDT sync perspective.
class FrontingChangeExecutor {
  FrontingChangeExecutor({
    required FrontingSessionRepository repository,
    required MutationRunner mutationRunner,
    MemberRepository? memberRepository,
  }) : _repository = repository,
       _mutationRunner = mutationRunner,
       _memberRepository = memberRepository;

  final FrontingSessionRepository _repository;
  final MutationRunner _mutationRunner;
  // Optional so unit tests that don't exercise the Unknown sentinel
  // path can omit it.  Required at runtime whenever a change in the
  // batch references [unknownSentinelMemberId] — see
  // [_ensureSentinelIfNeeded].
  final MemberRepository? _memberRepository;

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
        // Lazily create the Unknown sentinel member inside the same
        // mutation transaction so the freshly-emitted row's foreign
        // key is resolvable.  Mirrors the pattern in
        // FrontingMutationService._ensureSentinelIfNeeded.
        await _ensureSentinelIfNeeded(changes);
        for (final change in changes) {
          await _applyChange(change);
        }
      },
    );
  }

  /// If any change in [changes] writes [unknownSentinelMemberId], make
  /// sure the sentinel member entity exists locally before applying the
  /// session writes.  No-op (no read) when the sentinel isn't
  /// referenced.
  ///
  /// Throws [StateError] if the sentinel id appears but no
  /// MemberRepository was wired — that's a provider misconfig, not user
  /// input we can recover from.
  Future<void> _ensureSentinelIfNeeded(
    List<FrontingSessionChange> changes,
  ) async {
    final referencesSentinel = changes.any((change) {
      switch (change) {
        case CreateSessionChange(:final session):
          return session.memberId == unknownSentinelMemberId;
        case UpdateSessionChange(:final patch):
          return patch.memberId == unknownSentinelMemberId;
        case DeleteSessionChange():
          return false;
      }
    });
    if (!referencesSentinel) return;
    final repo = _memberRepository;
    if (repo == null) {
      throw StateError(
        'FrontingChangeExecutor received the Unknown sentinel id but no '
        'MemberRepository was wired.  Provide one in the constructor.',
      );
    }
    await repo.ensureUnknownSentinelMember();
  }

  Future<void> _applyChange(FrontingSessionChange change) async {
    switch (change) {
      case CreateSessionChange(:final session):
        final newSession = FrontingSession(
          id: const Uuid().v4(),
          startTime: session.start,
          endTime: session.end,
          memberId: session.memberId,
          notes: session.notes,
          sessionType: session.sessionType,
          quality: session.quality,
          isHealthKitImport: session.isHealthKitImport,
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
        memberId: patch.clearMemberId
            ? null
            : (patch.memberId ?? session.memberId),
        notes: patch.notes ?? session.notes,
        confidence: patch.confidenceIndex != null
            ? FrontConfidence.values[patch.confidenceIndex!]
            : session.confidence,
        pluralkitUuid: session.pluralkitUuid,
        sessionType: session.sessionType,
        quality: session.quality,
        isHealthKitImport: session.isHealthKitImport,
      );
    }

    return session.copyWith(
      startTime: patch.start ?? session.startTime,
      endTime: patch.end ?? session.endTime,
      memberId: patch.memberId ?? session.memberId,
      notes: patch.notes ?? session.notes,
      confidence: patch.confidenceIndex != null
          ? FrontConfidence.values[patch.confidenceIndex!]
          : session.confidence,
      sessionType: session.sessionType,
      quality: session.quality,
      isHealthKitImport: session.isHealthKitImport,
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
