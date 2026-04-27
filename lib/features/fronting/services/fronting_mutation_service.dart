import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:uuid/uuid.dart';

class FrontingMutationResult {
  const FrontingMutationResult({
    required this.sessions,
    this.previousMemberIds = const [],
  });

  /// The sessions created or most-recently-modified by the mutation.
  ///
  /// Multi-member calls (e.g. `startFronting([alex, sky])`) produce N rows.
  /// Callers must explicitly handle the list — use `.single` to assert exactly
  /// one (throws on length mismatch) or iterate. There is intentionally no
  /// `.session` shorthand: a silent `sessions.first` collapse would hide
  /// downstream bugs where multi-member results get treated as single-member.
  final List<FrontingSession> sessions;
  final List<String?> previousMemberIds;
}

class FrontingMutationService {
  FrontingMutationService({
    required FrontingSessionRepository repository,
    required MutationRunner mutationRunner,
    SessionLifecycleService lifecycle = const SessionLifecycleService(),
    Uuid? uuid,
  }) : _repository = repository,
       _mutationRunner = mutationRunner,
       _lifecycle = lifecycle,
       _uuid = uuid ?? const Uuid();

  final FrontingSessionRepository _repository;
  final MutationRunner _mutationRunner;
  final SessionLifecycleService _lifecycle;
  final Uuid _uuid;

  // ---------------------------------------------------------------------------
  // Per-member API
  // ---------------------------------------------------------------------------

  /// Creates one fronting_sessions row per member in [memberIds], all sharing
  /// [startTime] (defaults to now).
  ///
  /// Does NOT auto-end existing active sessions for other members — overlapping
  /// sessions from different members are first-class in the per-member model.
  /// The only session ended is an existing open session for the *same* member
  /// (self-overlap hard-block: a member can't front twice concurrently).
  ///
  /// Returns the newly created sessions.
  Future<MutationResult<FrontingMutationResult>> startFronting(
    List<String> memberIds, {
    DateTime? startTime,
    FrontConfidence? confidence,
    String? notes,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Start fronting session',
      action: () async {
        final now = startTime ?? DateTime.now();
        final created = <FrontingSession>[];

        for (final memberId in memberIds) {
          // Hard-block: end any existing open session for this member before
          // creating a new one. A member can't front twice concurrently.
          final existing = await _repository.getAllActiveSessionsUnfiltered();
          for (final s in existing) {
            if (s.memberId == memberId && !s.isSleep) {
              await _repository.endSession(s.id, now);
            }
          }

          final session = FrontingSession(
            id: _uuid.v4(),
            startTime: now,
            memberId: memberId,
            confidence: confidence,
            notes: notes,
          );
          await _repository.createSession(session);
          created.add(session);
        }

        return FrontingMutationResult(sessions: created);
      },
    );
  }

  /// Ends active fronting sessions for each member in [memberIds].
  ///
  /// No-op for members that don't have an active (non-sleep) session.
  Future<MutationResult<void>> endFronting(
    List<String> memberIds, {
    DateTime? endTime,
  }) {
    return _mutationRunner.run<void>(
      actionLabel: 'End fronting session',
      action: () async {
        final now = endTime ?? DateTime.now();
        final active = await _repository.getAllActiveSessionsUnfiltered();
        for (final session in active) {
          if (session.memberId != null &&
              memberIds.contains(session.memberId) &&
              !session.isSleep) {
            await _repository.endSession(session.id, now);
          }
        }
      },
    );
  }

  /// Sugar: starts a fronting session for a single member.
  ///
  /// Equivalent to [startFronting]([memberId]). Kept as a named entry point
  /// for call sites that conceptually add one person to an ongoing front.
  Future<MutationResult<FrontingMutationResult>> addCoFronter(
    String memberId, {
    DateTime? startTime,
    FrontConfidence? confidence,
    String? notes,
  }) {
    return startFronting(
      [memberId],
      startTime: startTime,
      confidence: confidence,
      notes: notes,
    );
  }

  /// Sugar: ends the fronting session for a single member.
  ///
  /// Equivalent to [endFronting]([memberId]).
  Future<MutationResult<void>> removeCoFronter(
    String memberId, {
    DateTime? endTime,
  }) {
    return endFronting([memberId], endTime: endTime);
  }

  // ---------------------------------------------------------------------------
  // Sleep
  // ---------------------------------------------------------------------------

  Future<MutationResult<FrontingMutationResult>> startSleep({
    String? notes,
    DateTime? startTime,
    SleepQuality? quality,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Start sleep session',
      action: () async {
        final activeSessions = await _repository.getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions.map((s) => s.memberId).toList();
        final now = startTime ?? DateTime.now();
        for (final session in activeSessions) {
          await _repository.endSession(session.id, now);
        }

        final created = FrontingSession(
          id: _uuid.v4(),
          startTime: now,
          memberId: null,
          notes: notes,
          sessionType: SessionType.sleep,
          quality: quality ?? SleepQuality.unknown,
        );
        await _repository.createSession(created);
        return FrontingMutationResult(
          sessions: [created],
          previousMemberIds: previousMemberIds,
        );
      },
    );
  }

  Future<MutationResult<void>> endSleep(String id) {
    return _mutationRunner.run<void>(
      actionLabel: 'End sleep session',
      action: () async {
        final session = await _requireSession(id);
        if (!session.isSleep) {
          throw AppFailure.notFound('Sleep session not found.');
        }
        await _repository.endSession(id, DateTime.now());
      },
    );
  }

  /// Atomically ends a sleep session, optionally records quality, and
  /// optionally starts a fronting session for a member.
  ///
  /// All writes run in a single transaction to prevent partial state
  /// (e.g. sleep ended but fronting failed to start).
  Future<MutationResult<FrontingMutationResult?>> wakeUp(
    String sleepSessionId, {
    SleepQuality? quality,
    String? frontingMemberId,
  }) {
    return _mutationRunner.run<FrontingMutationResult?>(
      actionLabel: 'Wake up',
      action: () async {
        // 1. Validate and end sleep session (single write to avoid double sync op)
        final session = await _requireSession(sleepSessionId);
        if (!session.isSleep) {
          throw AppFailure.notFound('Sleep session not found.');
        }
        final now = DateTime.now();
        final hasQuality = quality != null && quality != SleepQuality.unknown;
        final ended = session.copyWith(
          endTime: now,
          quality: hasQuality ? quality : session.quality,
        );
        await _repository.updateSession(ended);

        // 2. Start fronting if member selected
        if (frontingMemberId != null) {
          // Safety: end any other active sessions that may remain (e.g. a
          // second sleep session from sync or migration).
          final remaining = await _repository.getAllActiveSessionsUnfiltered();
          for (final s in remaining) {
            await _repository.endSession(s.id, now);
          }
          final created = FrontingSession(
            id: _uuid.v4(),
            startTime: now,
            memberId: frontingMemberId,
          );
          await _repository.createSession(created);
          return FrontingMutationResult(
            sessions: [created],
            previousMemberIds: [null], // was sleeping (no member)
          );
        }
        return null;
      },
    );
  }

  Future<MutationResult<FrontingSession>> updateSleepQuality(
    String id,
    SleepQuality quality,
  ) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Update sleep quality',
      action: () async {
        final session = await _requireSession(id);
        final updated = session.copyWith(quality: quality);
        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<void>> deleteSleep(String id) {
    return _mutationRunner.run<void>(
      actionLabel: 'Delete sleep session',
      action: () async {
        final session = await _requireSession(id);
        if (!session.isSleep) {
          throw AppFailure.notFound('Sleep session not found.');
        }
        await _repository.deleteSession(id);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Edit / update
  // ---------------------------------------------------------------------------

  Future<MutationResult<FrontingSession>> updateSession(
    String sessionId,
    UpdateFrontingSessionPatch patch,
  ) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Update fronting session',
      action: () async {
        final session = await _requireSession(sessionId);
        final updated = patch.applyTo(session);
        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  Future<MutationResult<FrontingSession>> applyEdit({
    required String sessionId,
    required UpdateFrontingSessionPatch patch,
    List<FrontingSession> overlapsToTrim = const [],
    List<FrontingSession> adjacentMerges = const [],
    List<GapInfo> gapsToFill = const [],
  }) {
    return saveValidatedEdit(
      sessionId: sessionId,
      patch: patch,
      validationResult: EditValidationResult(
        overlaps: overlapsToTrim,
        adjacentMerges: adjacentMerges,
        gapsCreated: gapsToFill,
      ),
      trimOverlaps: overlapsToTrim.isNotEmpty,
    );
  }

  Future<MutationResult<FrontingSession>> saveValidatedEdit({
    required String sessionId,
    required UpdateFrontingSessionPatch patch,
    required EditValidationResult validationResult,
    bool trimOverlaps = false,
  }) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Save fronting edit',
      action: () async {
        final session = await _requireSession(sessionId);
        var updated = patch.applyTo(session);

        if (trimOverlaps) {
          for (final overlap in validationResult.overlaps) {
            await _lifecycle.trimOverlap(updated, overlap, _repository);
          }
        }

        if (validationResult.hasAdjacentMerges) {
          updated = await _lifecycle.mergeAdjacent(
            updated,
            validationResult.adjacentMerges,
            _repository,
          );
        }

        if (validationResult.gapsCreated.isNotEmpty) {
          await _lifecycle.fillGaps(validationResult.gapsCreated, _repository);
        }

        await _repository.updateSession(updated);
        return updated;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<MutationResult<String?>> deleteSession(
    DeleteOption option,
    DeleteContext context,
  ) {
    return _mutationRunner.run<String?>(
      actionLabel: 'Delete fronting session',
      action: () => _lifecycle.executeDelete(option, context, _repository),
    );
  }

  Future<MutationResult<String?>> executeDeleteOption({
    required String sessionId,
    required DeleteOption option,
    required List<FrontingSession> allSessions,
  }) {
    return _mutationRunner.run<String?>(
      actionLabel: 'Delete fronting session',
      action: () async {
        final session = await _requireSession(sessionId);
        final context = _lifecycle.getDeleteOptions(session, allSessions);
        return _lifecycle.executeDelete(option, context, _repository);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Split
  // ---------------------------------------------------------------------------

  /// Splits the session at [splitTime]: trims the original's end to [splitTime]
  /// and creates a new row from [splitTime] onwards.
  ///
  /// The new row gets a deterministic id derived from the split namespace so
  /// that concurrent splits on two paired devices converge on the same id.
  ///
  /// The PK link is cleared on the new row (splitting breaks PK provenance).
  Future<MutationResult<FrontingSession>> splitSession(
    String sessionId,
    DateTime splitTime,
  ) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Split fronting session',
      action: () async {
        final session = await _requireSession(sessionId);

        final firstHalf = session.copyWith(endTime: splitTime);
        await _repository.updateSession(firstHalf);

        final newId = _uuid.v5(
          splitNamespace,
          '${session.id}:${splitTime.toIso8601String()}',
        );
        final secondHalf = FrontingSession(
          id: newId,
          startTime: splitTime,
          endTime: session.endTime,
          memberId: session.memberId,
          confidence: session.confidence,
          notes: session.notes,
          // The PK link belongs to the original session — the split-half is a
          // new local segment with no matching PK switch; sharing the UUID
          // would violate the composite unique index on
          // fronting_sessions(pluralkit_uuid, member_id). See c0ebbdc4.
          pluralkitUuid: null,
          sessionType: session.sessionType,
          quality: session.quality,
          isHealthKitImport: session.isHealthKitImport,
        );
        await _repository.createSession(secondHalf);
        return secondHalf;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<FrontingSession> _requireSession(String sessionId) async {
    final session = await _repository.getSessionById(sessionId);
    if (session == null) {
      throw AppFailure.notFound('Fronting session not found.');
    }
    return session;
  }
}
