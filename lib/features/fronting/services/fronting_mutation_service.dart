import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/front_session_comments_repository.dart';
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

/// Outcome of [FrontingMutationService.repairMemberSessionInvariants].
class FrontingRepairSummary {
  const FrontingRepairSummary({
    required this.openDuplicatesClosed,
    required this.overlapsMerged,
    required this.membersAffected,
  });

  /// Surplus open sessions that were closed so each member keeps at most one
  /// open session.
  final int openDuplicatesClosed;

  /// Same-member rows absorbed (deleted) by merging strictly-overlapping
  /// ranges into a single spanning session.
  final int overlapsMerged;

  /// Distinct members whose sessions were changed.
  final int membersAffected;

  bool get madeChanges => openDuplicatesClosed > 0 || overlapsMerged > 0;
}

class FrontingMutationService {
  FrontingMutationService({
    required FrontingSessionRepository repository,
    required MutationRunner mutationRunner,
    MemberRepository? memberRepository,
    FrontSessionCommentsRepository? frontSessionCommentsRepository,
    SessionLifecycleService lifecycle = const SessionLifecycleService(),
    FrontingEditGuard editGuard = const FrontingEditGuard(),
    Uuid? uuid,
  }) : _repository = repository,
       _mutationRunner = mutationRunner,
       _memberRepository = memberRepository,
       _frontSessionCommentsRepository = frontSessionCommentsRepository,
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
  final FrontSessionCommentsRepository? _frontSessionCommentsRepository;
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
    throw AppFailure.validation(issues.map((i) => i.summary).join('; '));
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

  List<String> _dedupeMemberIds(List<String> memberIds) {
    final seen = <String>{};
    return [
      for (final memberId in memberIds)
        if (seen.add(memberId)) memberId,
    ];
  }

  FrontingSession? _earliestSession(List<FrontingSession> sessions) {
    if (sessions.isEmpty) return null;
    return sessions.reduce(
      (earliest, session) =>
          session.startTime.isBefore(earliest.startTime) ? session : earliest,
    );
  }

  /// For the explicit always-fronting members among [sessions], returns the
  /// single open session to preserve per member — the earliest-started, i.e.
  /// their persistent background session. Non-always-fronting rows, sleep rows,
  /// and null-member rows are excluded. Any *extra* open sessions for these
  /// members beyond the returned one are duplicates the caller should close so
  /// the one-open-per-member invariant holds.
  Future<Map<String, FrontingSession>> _earliestAlwaysFrontingByMember(
    List<FrontingSession> sessions,
  ) async {
    final byMember = <String, List<FrontingSession>>{};
    for (final s in sessions) {
      final memberId = s.memberId;
      if (s.isSleep || memberId == null) continue;
      if (!await _isActiveExplicitAlwaysFrontingMember(memberId)) continue;
      (byMember[memberId] ??= <FrontingSession>[]).add(s);
    }
    return {
      for (final entry in byMember.entries)
        entry.key: _earliestSession(entry.value)!,
    };
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
        final selectedMemberIds = _dedupeMemberIds(memberIds);
        // Auto-create the Unknown sentinel member before any session
        // writes if its id appears in the payload.  Done inside the
        // mutation runner so the sentinel create + session create live
        // in the same transaction; either both land or neither does.
        await _ensureSentinelIfNeeded(selectedMemberIds);

        final now = startTime ?? DateTime.now();
        _assertTimeRange(now, null);
        final created = <FrontingSession>[];
        final existing = await _repository.getAllActiveSessionsUnfiltered();

        for (final memberId in selectedMemberIds) {
          // Hard-block: a member can only have one active normal row. If the
          // member is already active, reuse that row instead of splitting a
          // continuous front into adjacent duplicate entries. Any extra active
          // rows for the same member are closed as corruption cleanup.
          final sameMemberActive = existing
              .where((s) => s.memberId == memberId && !s.isSleep)
              .toList();
          final preservedActiveSession = _earliestSession(sameMemberActive);
          if (preservedActiveSession != null) {
            for (final s in sameMemberActive) {
              if (s.id == preservedActiveSession.id) continue;
              await _repository.endSession(s.id, now);
            }
            created.add(preservedActiveSession);
            continue;
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

  /// Creates one closed fronting row per member in [memberIds] for the
  /// historical range `[startTime, endTime]`.
  ///
  /// Same-member rows that overlap or touch the inserted range are collapsed
  /// into one continuous session. Cross-member overlap is intentionally left
  /// untouched.
  Future<MutationResult<FrontingMutationResult>> logHistoricalFronting(
    List<String> memberIds, {
    required DateTime startTime,
    required DateTime endTime,
    FrontConfidence? confidence,
    String? notes,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Log historical fronting session',
      action: () async {
        final selectedMemberIds = _dedupeMemberIds(memberIds);
        await _ensureSentinelIfNeeded(selectedMemberIds);
        _assertTimeRange(startTime, endTime);

        final mergedSessions = <FrontingSession>[];
        for (final memberId in selectedMemberIds) {
          final drafted = FrontingSession(
            id: _uuid.v4(),
            startTime: startTime,
            endTime: endTime,
            memberId: memberId,
            confidence: confidence,
            notes: notes,
          );
          final merged = await _mergeOrCreateHistoricalSession(drafted);
          mergedSessions.add(merged);
        }

        return FrontingMutationResult(sessions: mergedSessions);
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
    int quickSwitchThresholdSeconds = 0,
  }) {
    return _mutationRunner.run<FrontingMutationResult>(
      actionLabel: 'Replace fronting session',
      action: () async {
        final selectedMemberIds = _dedupeMemberIds(memberIds);
        // Sentinel auto-create runs inside the same transaction so the
        // member + session writes are atomic together — same contract as
        // [startFronting].
        await _ensureSentinelIfNeeded(selectedMemberIds);

        final at = now ?? DateTime.now();
        _assertTimeRange(at, null);

        // 1. End every currently-active *normal* (non-sleep) session.
        //    Sleep sessions are deliberately untouched: replacing fronts
        //    while sleeping isn't a meaningful UX, and the per-member
        //    model treats sleep as orthogonal to member fronting.
        final actives = await _repository.getAllActiveSessionsUnfiltered();
        final previousMemberIds = <String?>[];
        final replaceableActives = <FrontingSession>[];
        final preserved = <String, FrontingSession>{};
        final selectedSet = selectedMemberIds.toSet();
        for (final memberId in selectedMemberIds) {
          final sameMemberActive = actives
              .where((s) => s.memberId == memberId && !s.isSleep)
              .toList();
          final preservedSession = _earliestSession(sameMemberActive);
          if (preservedSession != null) preserved[memberId] = preservedSession;
        }
        for (final s in actives) {
          if (s.isSleep) continue;
          final memberId = s.memberId;
          if (memberId != null && selectedSet.contains(memberId)) {
            if (preserved[memberId]?.id == s.id) continue;
          } else if (memberId != null &&
              await _isActiveExplicitAlwaysFrontingMember(memberId)) {
            preserved.putIfAbsent(memberId, () => s);
            if (preserved[memberId]?.id == s.id) continue;
          }
          replaceableActives.add(s);
          previousMemberIds.add(s.memberId);
        }

        if (memberIds.length == 1 &&
            replaceableActives.length == 1 &&
            !preserved.containsKey(memberIds.single) &&
            _lifecycle.evaluateQuickSwitch(
                  replaceableActives.single,
                  thresholdSeconds: quickSwitchThresholdSeconds,
                  now: at,
                ) ==
                QuickSwitchAction.correctExisting) {
          final corrected = replaceableActives.single.copyWith(
            memberId: memberIds.single,
          );
          await _repository.updateSession(corrected);
          return FrontingMutationResult(
            sessions: [corrected],
            previousMemberIds: previousMemberIds,
          );
        }

        for (final s in replaceableActives) {
          await _repository.endSession(s.id, at);
        }

        // 2. Start a fresh session for each requested member, all sharing
        //    the same `at` so end_time of the previous == start_time of
        //    the new.
        final created = <FrontingSession>[];
        for (final memberId in selectedMemberIds) {
          final preservedSession = preserved[memberId];
          if (preservedSession != null) {
            created.add(preservedSession);
            continue;
          }
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
        final activeSessions = await _repository
            .getAllActiveSessionsUnfiltered();
        final previousMemberIds = activeSessions
            .map((s) => s.memberId)
            .toList();
        final now = startTime ?? DateTime.now();
        _assertTimeRange(now, null);
        // Preserve exactly one open session per explicit always-fronting member
        // (their persistent background session); end everything else, including
        // any duplicate opens for those members so the one-open-per-member
        // invariant holds through sleep.
        final preservedIds = {
          for (final s in (await _earliestAlwaysFrontingByMember(
            activeSessions,
          )).values)
            s.id,
        };
        for (final session in activeSessions) {
          if (preservedIds.contains(session.id)) continue;
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
  /// optionally starts fronting sessions for selected members.
  ///
  /// All writes run in a single transaction to prevent partial state
  /// (e.g. sleep ended but fronting failed to start).
  Future<MutationResult<FrontingMutationResult?>> wakeUp(
    String sleepSessionId, {
    SleepQuality? quality,
    List<String> frontingMemberIds = const [],
  }) {
    return _mutationRunner.run<FrontingMutationResult?>(
      actionLabel: 'Wake up',
      action: () async {
        final selectedMemberIds = <String>{...frontingMemberIds}.toList();

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

        // 2. Start fronting if members were selected.
        if (selectedMemberIds.isEmpty) return null;

        // Auto-create the Unknown sentinel member if waking up into Unknown
        // alongside any other selected members.
        await _ensureSentinelIfNeeded(selectedMemberIds);

        // Safety: end any other active sessions that may remain (e.g. a
        // second sleep session from sync or migration). Explicit
        // always-fronting sessions are preserved; if one is selected, reuse
        // its existing row instead of creating a duplicate.
        final remaining = await _repository.getAllActiveSessionsUnfiltered();
        final preservedFrontingSessions = <String, FrontingSession>{};
        final previousMemberIds = <String?>[null]; // was sleeping (no member)

        // Preserve exactly one open session per always-fronting member (the
        // earliest = persistent background session). Selected members reuse it
        // for the new front; non-selected ones simply keep fronting. Every
        // other open session — including duplicate opens for these members — is
        // closed so each member ends up with a single open session.
        final preservedAlwaysFronting = await _earliestAlwaysFrontingByMember(
          remaining,
        );
        final preservedIds = {
          for (final s in preservedAlwaysFronting.values) s.id,
        };
        for (final entry in preservedAlwaysFronting.entries) {
          if (selectedMemberIds.contains(entry.key)) {
            preservedFrontingSessions[entry.key] = entry.value;
          }
        }
        for (final s in remaining) {
          if (preservedIds.contains(s.id)) continue;
          await _repository.endSession(s.id, now);
          if (!s.isSleep) previousMemberIds.add(s.memberId);
        }

        final frontingSessions = <FrontingSession>[];
        for (final memberId in selectedMemberIds) {
          final preservedFrontingSession = preservedFrontingSessions[memberId];
          if (preservedFrontingSession != null) {
            frontingSessions.add(preservedFrontingSession);
            continue;
          }
          final created = FrontingSession(
            id: _uuid.v4(),
            startTime: now,
            memberId: memberId,
          );
          await _repository.createSession(created);
          frontingSessions.add(created);
        }

        return FrontingMutationResult(
          sessions: frontingSessions,
          previousMemberIds: previousMemberIds,
        );
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
        await reparentFrontSessionCommentsByTimestamp(
          _frontSessionCommentsRepository,
          fromSessionId: session.id,
          targets: [
            FrontSessionCommentReparentTarget(
              sessionId: secondHalf.id,
              startTime: splitTime,
              endTime: null,
            ),
          ],
        );
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

  Future<bool> _isActiveExplicitAlwaysFrontingMember(String? memberId) async {
    if (memberId == null) return false;
    final repo = _memberRepository;
    if (repo == null) return false;
    final member = await repo.getMemberById(memberId);
    return member != null &&
        member.isActive &&
        !member.isDeleted &&
        member.isAlwaysFronting;
  }

  Future<FrontingSession> _mergeOrCreateHistoricalSession(
    FrontingSession drafted,
  ) async {
    final memberId = drafted.memberId;
    if (memberId == null) {
      await _repository.createSession(drafted);
      return drafted;
    }

    final existing = await _repository.getSessionsForMember(memberId);
    final mergeCandidates = _collectSameMemberMergeCandidates(
      existing,
      drafted,
    );

    if (mergeCandidates.isEmpty) {
      await _repository.createSession(drafted);
      return drafted;
    }

    final survivor = mergeCandidates.first;
    final allSessions = [...mergeCandidates, drafted]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final merged = survivor.copyWith(
      startTime: allSessions
          .map((session) => session.startTime)
          .reduce((a, b) => a.isBefore(b) ? a : b),
      endTime: _mergeEndTime(allSessions),
      notes: _mergeNotes(allSessions.map((session) => session.notes)),
      confidence: _mergeConfidence(
        allSessions.map((session) => session.confidence),
      ),
    );
    await _repository.updateSession(merged);

    for (final session in mergeCandidates.skip(1)) {
      await reparentFrontSessionComments(
        _frontSessionCommentsRepository,
        fromSessionId: session.id,
        toSessionId: survivor.id,
      );
      await _repository.deleteSession(session.id);
    }

    return merged;
  }

  bool _shouldMergeSameMember(
    FrontingSession existing,
    DateTime start,
    DateTime? end,
  ) {
    if (existing.isSleep) return false;
    final mergedEnd = end ?? DateTime.utc(9999);
    final existingEnd = existing.endTime ?? DateTime.utc(9999);
    return !existing.startTime.isAfter(mergedEnd) &&
        !start.isAfter(existingEnd);
  }

  List<FrontingSession> _collectSameMemberMergeCandidates(
    List<FrontingSession> existing,
    FrontingSession drafted,
  ) {
    var mergedStart = drafted.startTime;
    var mergedEnd = drafted.endTime;
    if (mergedEnd == null) return const [];

    final remaining = [...existing];
    final mergeCandidates = <FrontingSession>[];

    var madeProgress = true;
    while (madeProgress) {
      madeProgress = false;
      for (var i = remaining.length - 1; i >= 0; i--) {
        final session = remaining[i];
        if (!_shouldMergeSameMember(session, mergedStart, mergedEnd)) continue;
        remaining.removeAt(i);
        mergeCandidates.add(session);
        if (session.startTime.isBefore(mergedStart)) {
          mergedStart = session.startTime;
        }
        final sessionEnd = session.endTime;
        if (sessionEnd == null) {
          mergedEnd = null;
        } else if (mergedEnd == null || sessionEnd.isAfter(mergedEnd)) {
          mergedEnd = sessionEnd;
        }
        madeProgress = true;
      }
    }

    mergeCandidates.sort((a, b) => a.startTime.compareTo(b.startTime));
    return mergeCandidates;
  }

  DateTime? _mergeEndTime(Iterable<FrontingSession> sessions) {
    DateTime? latest;
    for (final session in sessions) {
      final end = session.endTime;
      if (end == null) return null;
      if (latest == null || end.isAfter(latest)) latest = end;
    }
    return latest;
  }

  String? _mergeNotes(Iterable<String?> notes) {
    final nonEmpty = notes
        .whereType<String>()
        .map((note) => note.trim())
        .where((note) => note.isNotEmpty)
        .toList();
    if (nonEmpty.isEmpty) return null;
    return nonEmpty.join('\n\n');
  }

  FrontConfidence? _mergeConfidence(Iterable<FrontConfidence?> confidences) {
    FrontConfidence? strongest;
    for (final confidence in confidences) {
      if (confidence == null) continue;
      if (strongest == null || confidence.index > strongest.index) {
        strongest = confidence;
      }
    }
    return strongest;
  }

  // ---------------------------------------------------------------------------
  // Repair / data-integrity maintenance
  // ---------------------------------------------------------------------------

  /// Idempotent repair that restores the per-member session invariants on
  /// existing data. The mutation-time guards in [startFronting] /
  /// [replaceFronting] only prevent new duplicates on the device making the
  /// edit; opens that accumulate across unsynced devices only collapse here.
  ///
  ///  1. **At most one open session per member.** When a member has more than
  ///     one open (`end_time == null`) session, the most-recently started open
  ///     is kept open and each earlier open is closed at the start of that
  ///     member's next session, turning stale opens into contiguous history.
  ///  2. **No strictly-overlapping same-member sessions.** Sessions for the
  ///     same member whose `[start, end]` ranges strictly overlap are merged
  ///     into one session spanning the union, preserving notes, confidence,
  ///     attached comments, and the PluralKit link. Adjacent (touching)
  ///     sessions are left distinct.
  ///
  /// Every write goes through the repository, so each close / merge / delete
  /// emits a synced CRDT op — running this on one device converges every peer.
  /// Safe to run repeatedly: a second run finds at most one open per member and
  /// no strict overlaps, so it emits nothing.
  Future<MutationResult<FrontingRepairSummary>>
  repairMemberSessionInvariants() {
    return _mutationRunner.run<FrontingRepairSummary>(
      actionLabel: 'Repair fronting sessions',
      action: () async {
        final all = await _repository.getFrontingSessions();
        final byMember = <String, List<FrontingSession>>{};
        for (final s in all) {
          final memberId = s.memberId;
          if (memberId == null) continue;
          (byMember[memberId] ??= <FrontingSession>[]).add(s);
        }

        var openDuplicatesClosed = 0;
        var overlapsMerged = 0;
        final affected = <String>{};
        for (final memberId in byMember.keys) {
          final closed = await _collapseOpenDuplicates(
            memberId,
            byMember[memberId]!,
          );
          // _mergeOverlappingSessions re-reads the member's rows so the overlap
          // pass observes the freshly-closed end_times (same transaction →
          // reads see prior writes).
          final merged = await _mergeOverlappingSessions(memberId);
          openDuplicatesClosed += closed;
          overlapsMerged += merged;
          if (closed > 0 || merged > 0) affected.add(memberId);
        }

        return FrontingRepairSummary(
          openDuplicatesClosed: openDuplicatesClosed,
          overlapsMerged: overlapsMerged,
          membersAffected: affected.length,
        );
      },
    );
  }

  /// Collapses multiple open sessions for [memberId] down to one. Keeps the
  /// most-recently started open and closes each earlier open at the start of
  /// the next session in [memberSessions] (clamped to a strictly positive
  /// duration). [memberSessions] is the pre-repair snapshot of this member's
  /// non-deleted normal sessions. Returns the number of opens closed.
  Future<int> _collapseOpenDuplicates(
    String memberId,
    List<FrontingSession> memberSessions,
  ) async {
    final sorted = [...memberSessions]..sort(_byStartThenId);
    final opens = [
      for (final s in sorted)
        if (s.endTime == null) s,
    ];
    if (opens.length <= 1) return 0;

    final keep = opens.last; // most-recently started
    var closed = 0;
    for (final open in opens) {
      if (open.id == keep.id) continue;
      // Close at the start of the next session that begins after this open —
      // the moment the member's next (duplicate) front took over.
      DateTime? nextStart;
      for (final other in sorted) {
        if (other.id == open.id) continue;
        if (other.startTime.isAfter(open.startTime) &&
            (nextStart == null || other.startTime.isBefore(nextStart))) {
          nextStart = other.startTime;
        }
      }
      final end = nextStart ?? keep.startTime;
      final safeEnd = end.isAfter(open.startTime)
          ? end
          : open.startTime.add(const Duration(seconds: 1));
      await _repository.endSession(open.id, safeEnd);
      closed++;
    }
    return closed;
  }

  /// Merges same-member sessions whose `[start, end]` ranges strictly overlap
  /// into a single spanning session. Touching/adjacent sessions
  /// (`end == next.start`) are left as distinct rows. Returns the number of
  /// rows absorbed by merges.
  Future<int> _mergeOverlappingSessions(String memberId) async {
    final fetched = await _repository.getSessionsForMember(memberId);
    final remaining = [...fetched]..sort(_byStartThenId);
    var absorbed = 0;

    while (remaining.isNotEmpty) {
      final seed = remaining.removeAt(0);
      final group = <FrontingSession>[seed];
      var groupStart = seed.startTime;
      DateTime? groupEnd = seed.endTime;

      var changed = true;
      while (changed) {
        changed = false;
        for (var i = remaining.length - 1; i >= 0; i--) {
          final s = remaining[i];
          if (!_rangesStrictlyOverlap(
            groupStart,
            groupEnd,
            s.startTime,
            s.endTime,
          )) {
            continue;
          }
          group.add(s);
          remaining.removeAt(i);
          if (s.startTime.isBefore(groupStart)) groupStart = s.startTime;
          final end = s.endTime;
          if (groupEnd != null) {
            if (end == null) {
              groupEnd = null;
            } else if (end.isAfter(groupEnd)) {
              groupEnd = end;
            }
          }
          changed = true;
        }
      }

      if (group.length < 2) continue;
      await _mergeOverlapGroup(group);
      absorbed += group.length - 1;
    }
    return absorbed;
  }

  Future<void> _mergeOverlapGroup(List<FrontingSession> group) async {
    // Sort by start so merged notes read chronologically regardless of the
    // order rows were absorbed into the group.
    group.sort(_byStartThenId);
    final survivor = _pickMergeSurvivor(group);
    final unionStart = group
        .map((s) => s.startTime)
        .reduce((a, b) => a.isBefore(b) ? a : b);

    final merged = survivor.copyWith(
      startTime: unionStart,
      endTime: _mergeEndTime(group),
      notes: _mergeNotes(group.map((s) => s.notes)),
      confidence: _mergeConfidence(group.map((s) => s.confidence)),
    );
    await _repository.updateSession(merged);

    for (final s in group) {
      if (s.id == survivor.id) continue;
      await reparentFrontSessionComments(
        _frontSessionCommentsRepository,
        fromSessionId: s.id,
        toSessionId: survivor.id,
      );
      await _repository.deleteSession(s.id);
    }
  }

  /// Picks the row to keep when merging an overlap group.
  ///
  /// Prefers a PluralKit-linked row so its link survives without moving the
  /// `pluralkit_uuid` onto a different row: the partial unique index on
  /// `(pluralkit_uuid, member_id)` covers tombstones, so transferring a uuid
  /// while soft-deleting its previous holder would collide. Ties (and the
  /// no-link case) break on earliest start, then id.
  FrontingSession _pickMergeSurvivor(List<FrontingSession> group) {
    final linked = [
      for (final s in group)
        if (s.pluralkitUuid != null && s.pluralkitUuid!.isNotEmpty) s,
    ];
    final pool = linked.isNotEmpty ? linked : group;
    return pool.reduce((a, b) => _byStartThenId(a, b) <= 0 ? a : b);
  }

  static int _byStartThenId(FrontingSession a, FrontingSession b) {
    final c = a.startTime.compareTo(b.startTime);
    if (c != 0) return c;
    return a.id.compareTo(b.id);
  }

  /// Two `[start, end]` ranges strictly overlap when each starts before the
  /// other ends; a null end means open (+infinity). Touching boundaries
  /// (`aEnd == bStart`) do **not** count — adjacent sessions stay distinct.
  static bool _rangesStrictlyOverlap(
    DateTime aStart,
    DateTime? aEnd,
    DateTime bStart,
    DateTime? bEnd,
  ) {
    final aE = aEnd ?? _farFuture;
    final bE = bEnd ?? _farFuture;
    return aStart.isBefore(bE) && bStart.isBefore(aE);
  }

  static final DateTime _farFuture = DateTime.utc(9999);
}
