import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_guard.dart';
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
    MemberRepository? memberRepository,
    SessionLifecycleService lifecycle = const SessionLifecycleService(),
    FrontingEditGuard editGuard = const FrontingEditGuard(),
    Uuid? uuid,
  }) : _repository = repository,
       _mutationRunner = mutationRunner,
       _memberRepository = memberRepository,
       _lifecycle = lifecycle,
       _editGuard = editGuard,
       _uuid = uuid ?? const Uuid();

  final FrontingSessionRepository _repository;
  final MutationRunner _mutationRunner;
  // Optional so unit tests that don't exercise the Unknown sentinel path
  // can omit it.  When the Unknown sentinel id appears in a mutation
  // payload, this MUST be wired or the service throws (see
  // [_ensureSentinelIfNeeded]).
  final MemberRepository? _memberRepository;
  final SessionLifecycleService _lifecycle;
  final FrontingEditGuard _editGuard;
  final Uuid _uuid;

  /// Throws [AppFailure.validation] if [start]/[end] violate the basic
  /// time invariants (end <= start, start in the future, end in the
  /// future). The single choke point every public write method is
  /// expected to call before touching the repository.
  void _assertTimeRange(DateTime start, DateTime? end) {
    final issues = _editGuard.validateTimeRange(start, end);
    if (issues.isEmpty) return;
    throw AppFailure.validation(
      issues.map((i) => i.summary).join('; '),
    );
  }

  /// If [memberIds] contains the Unknown sentinel id, lazily creates the
  /// sentinel member so the freshly-emitted fronting_sessions row has a
  /// resolvable foreign key.  No-op (no read) when the sentinel isn't
  /// referenced — keeps the hot path free of an extra round trip.
  ///
  /// Throws [StateError] if a sentinel id is present but no
  /// MemberRepository was wired — that combination indicates a misconfig
  /// at the provider layer, not user input we can recover from.
  Future<void> _ensureSentinelIfNeeded(List<String> memberIds) async {
    if (!memberIds.contains(unknownSentinelMemberId)) return;
    final repo = _memberRepository;
    if (repo == null) {
      throw StateError(
        'FrontingMutationService received the Unknown sentinel id but no '
        'MemberRepository was wired.  Provide one in the constructor.',
      );
    }
    await repo.ensureUnknownSentinelMember();
  }

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
        // Auto-create the Unknown sentinel member before any session
        // writes if its id appears in the payload.  Done inside the
        // mutation runner so the sentinel create + session create live
        // in the same transaction; either both land or neither does.
        await _ensureSentinelIfNeeded(memberIds);

        final now = startTime ?? DateTime.now();
        _assertTimeRange(now, null);
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

  /// Atomically ends all currently-active normal (non-sleep) fronting
  /// sessions AND starts a session for each member in [memberIds],
  /// inside a single MutationRunner transaction with one captured `now`.
  ///
  /// Used by the add-front sheet's "replace" mode and quick-front's replace
  /// mode. A crash mid-block leaves the user with the prior state intact
  /// (atomicity), not "no fronts at all," which is the failure mode of
  /// looping `endFronting` then `startFronting` from the call site.
  ///
  /// The captured `now` is shared across the end-time of every prior session
  /// and the start-time of every new session, so the new period begins at
  /// exactly the same instant the old ones ended (no off-by-microseconds
  /// gap, no overlap).
  ///
  /// If any [memberIds] entry is the Unknown sentinel id, the sentinel
  /// member is auto-created via [_ensureSentinelIfNeeded] inside the same
  /// transaction (matching [startFronting]'s contract).
  ///
  /// Returns the newly created sessions plus the previous member ids whose
  /// sessions were ended (for invalidation hooks).
  Future<MutationResult<FrontingMutationResult>> replaceFronting(
    List<String> memberIds, {
    DateTime? now,
    FrontConfidence? confidence,
    String? notes,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Replace fronting session',
      action: () async {
        // Sentinel auto-create runs inside the same transaction so the
        // member + session writes are atomic together — same contract as
        // [startFronting].
        await _ensureSentinelIfNeeded(memberIds);

        final at = now ?? DateTime.now();
        _assertTimeRange(at, null);

        // 1. End every currently-active *normal* (non-sleep) session.
        //    Sleep sessions are deliberately untouched: replacing fronts
        //    while sleeping isn't a meaningful UX, and the per-member
        //    model treats sleep as orthogonal to member fronting.
        final actives = await _repository.getAllActiveSessionsUnfiltered();
        final previousMemberIds = <String?>[];
        for (final s in actives) {
          if (!s.isSleep) {
            await _repository.endSession(s.id, at);
            previousMemberIds.add(s.memberId);
          }
        }

        // 2. Start a fresh session for each requested member, all sharing
        //    the same `at` so end_time of the previous == start_time of
        //    the new.
        final created = <FrontingSession>[];
        for (final memberId in memberIds) {
          final session = FrontingSession(
            id: _uuid.v4(),
            startTime: at,
            memberId: memberId,
            confidence: confidence,
            notes: notes,
          );
          await _repository.createSession(session);
          created.add(session);
        }

        return FrontingMutationResult(
          sessions: created,
          previousMemberIds: previousMemberIds,
        );
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
            // Caller-supplied [endTime] could pre-date the session start
            // or sit in the future — either would produce an invalid row.
            _assertTimeRange(session.startTime, now);
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
        _assertTimeRange(now, null);
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
          // Auto-create the Unknown sentinel member if waking up directly
          // into Unknown — otherwise the new session would dangle.
          await _ensureSentinelIfNeeded([frontingMemberId]);
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

  Future<MutationResult<FrontingSession>> logHistoricalSleep({
    required DateTime startTime,
    required DateTime endTime,
    SleepQuality? quality,
    String? notes,
  }) {
    return _mutationRunner.run<FrontingSession>(
      actionLabel: 'Log historical sleep session',
      action: () async {
        if (!endTime.isAfter(startTime)) {
          throw AppFailure.validation('end must be after start');
        }
        if (startTime.isAfter(DateTime.now())) {
          throw AppFailure.validation('cannot log sleep in the future');
        }
        final created = FrontingSession(
          id: _uuid.v4(),
          startTime: startTime,
          endTime: endTime,
          memberId: null,
          notes: notes,
          sessionType: SessionType.sleep,
          quality: quality ?? SleepQuality.unknown,
        );
        await _repository.createSession(created);
        return created;
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
        _assertTimeRange(updated.startTime, updated.endTime);
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
        _assertTimeRange(updated.startTime, updated.endTime);

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

        // splitTime must land strictly inside the original range, else
        // the resulting halves would have invalid (zero or negative)
        // duration. For an open-ended session, only the lower bound
        // applies.
        if (!splitTime.isAfter(session.startTime)) {
          throw AppFailure.validation(
            'Split time must be after the session start.',
          );
        }
        if (session.endTime != null && !splitTime.isBefore(session.endTime!)) {
          throw AppFailure.validation(
            'Split time must be before the session end.',
          );
        }
        // The two halves still have to clear the time-range invariant
        // (notably: future-time guard, in case splitTime is in the future).
        _assertTimeRange(session.startTime, splitTime);
        _assertTimeRange(splitTime, session.endTime);

        final firstHalf = session.copyWith(endTime: splitTime);
        await _repository.updateSession(firstHalf);

        // The derivation key MUST normalize to UTC before serialization:
        // `DateTime.toIso8601String()` on a local `DateTime` (`isUtc==false`)
        // emits no timezone offset at all (no `Z`, no `+HH:MM`), so two
        // paired devices that represent the same instant differently —
        // one as a local wall-clock from a date picker, one as a UTC
        // round-trip via `fromMillisecondsSinceEpoch(..., isUtc: true)` —
        // would derive different v5 ids and produce divergent rows the
        // CRDT can't merge. Calling `.toUtc()` first fixes the wire format
        // to a single canonical representation.
        //
        // Precision note: Dart `DateTime` carries microseconds on the VM
        // and milliseconds on web. `splitTime` should already be at a
        // consistent precision before reaching this site (today it comes
        // from a UI date picker at second/minute precision, so this is
        // not a live risk).
        final newId = _uuid.v5(
          splitNamespace,
          '${session.id}:${splitTime.toUtc().toIso8601String()}',
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
