// lib/core/services/session_lifecycle_service.dart
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:uuid/uuid.dart';

// ──────────────────────────────────────────────
// Validation types (carried over)
// ──────────────────────────────────────────────

enum SessionValidationError {
  overlapWithExisting,
  startAfterEnd,
  futureSession,
  invalidDuration,
}

class GapInfo {
  const GapInfo({
    required this.startTime,
    required this.endTime,
    required this.beforeSession,
    required this.afterSession,
  });

  final DateTime startTime;
  final DateTime endTime;
  final FrontingSession beforeSession;
  final FrontingSession afterSession;

  Duration get duration => endTime.difference(startTime);
}

// ──────────────────────────────────────────────
// Delete types
// ──────────────────────────────────────────────

enum DeleteOption {
  /// Re-open the previous session (set its endTime to null). Active deletes only.
  makePreviousActive,

  /// Stretch the previous session's endTime to cover this session's time.
  extendPrevious,

  /// Stretch the next session's startTime backward to cover this session's time.
  extendNext,

  /// Just delete. An unknown session fills the gap automatically.
  delete,
}

class DeleteContext {
  const DeleteContext({
    required this.session,
    required this.previous,
    required this.next,
    required this.availableOptions,
  });

  final FrontingSession session;
  final FrontingSession? previous;
  final FrontingSession? next;
  final List<DeleteOption> availableOptions;
}

// ──────────────────────────────────────────────
// Edit types
// ──────────────────────────────────────────────

class EditValidationResult {
  const EditValidationResult({
    this.errors = const [],
    this.overlaps = const [],
    this.gapsCreated = const [],
    this.adjacentMerges = const [],
  });

  /// Hard blocks — must be fixed before saving.
  final List<SessionValidationError> errors;

  /// Sessions the new time range collides with.
  final List<FrontingSession> overlaps;

  /// Gaps that would be created by shrinking the session.
  final List<GapInfo> gapsCreated;

  /// Adjacent sessions by the same member that could be merged (within 60s).
  final List<FrontingSession> adjacentMerges;

  bool get hasErrors => errors.isNotEmpty;
  bool get hasOverlaps => overlaps.isNotEmpty;
  bool get hasAdjacentMerges => adjacentMerges.isNotEmpty;
  bool get isClean => !hasErrors && !hasOverlaps && !hasAdjacentMerges;
}

// ──────────────────────────────────────────────
// Quick-switch types
// ──────────────────────────────────────────────

enum QuickSwitchAction {
  /// Session started recently — just update the member in place.
  correctExisting,

  /// Normal transition — end current session, create new one.
  createNew,
}

// ──────────────────────────────────────────────
// Service
// ──────────────────────────────────────────────

class SessionLifecycleService {
  const SessionLifecycleService({MemberRepository? memberRepository})
    : _memberRepository = memberRepository;

  /// Optional so unit tests that don't exercise the Unknown-sentinel filler
  /// paths (`executeDelete` with `DeleteOption.delete`, `fillGaps`) can omit
  /// it.  When those paths run without a wired [MemberRepository], the
  /// service throws — see [_ensureUnknownSentinel].
  final MemberRepository? _memberRepository;

  static const _uuid = Uuid();

  /// Lazily creates the Unknown sentinel member so the freshly-emitted
  /// fronting_sessions row that points at [unknownSentinelMemberId] has a
  /// resolvable foreign key.  Mirrors
  /// `FrontingMutationService._ensureSentinelIfNeeded`.
  ///
  /// Throws [StateError] when invoked without a wired [MemberRepository] —
  /// that combination indicates a misconfig at the provider layer (the
  /// Unknown-filler paths must be wired with a real repository in
  /// production), not user input we can recover from.
  Future<void> _ensureUnknownSentinel() async {
    final repo = _memberRepository;
    if (repo == null) {
      throw StateError(
        'SessionLifecycleService needs a MemberRepository to fill gaps with '
        'the Unknown sentinel member.  Provide one in the constructor.',
      );
    }
    await repo.ensureUnknownSentinelMember();
  }

  // ── Validation (existing) ──────────────────

  List<SessionValidationError> validateTimeRange(
    DateTime start,
    DateTime? end,
  ) {
    final errors = <SessionValidationError>[];

    if (end != null && start.isAfter(end)) {
      errors.add(SessionValidationError.startAfterEnd);
    }

    final now = DateTime.now();
    if (start.isAfter(now.add(const Duration(minutes: 1)))) {
      errors.add(SessionValidationError.futureSession);
    }

    if (end != null) {
      final duration = end.difference(start);
      if (duration.inSeconds < 1) {
        errors.add(SessionValidationError.invalidDuration);
      }
    }

    return errors;
  }

  List<FrontingSession> detectOverlaps(
    FrontingSession session,
    List<FrontingSession> allSessions,
  ) {
    final overlaps = <FrontingSession>[];
    final start = session.startTime;
    final end = session.endTime ?? DateTime.now();

    for (final other in allSessions) {
      if (other.id == session.id) continue;
      if (other.sessionType != session.sessionType) continue;
      final otherStart = other.startTime;
      final otherEnd = other.endTime ?? DateTime.now();
      if (start.isBefore(otherEnd) && otherStart.isBefore(end)) {
        overlaps.add(other);
      }
    }

    return overlaps;
  }

  // ── Delete ─────────────────────────────────

  /// Computes available delete options based on session context.
  ///
  /// [allSessions] should contain the full recent history.
  /// The service finds the immediate previous and next sessions.
  DeleteContext getDeleteOptions(
    FrontingSession session,
    List<FrontingSession> allSessions,
  ) {
    final sorted =
        allSessions.where((s) => s.sessionType == session.sessionType).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final idx = sorted.indexWhere((s) => s.id == session.id);
    final previous = idx > 0 ? sorted[idx - 1] : null;
    final next = idx >= 0 && idx < sorted.length - 1 ? sorted[idx + 1] : null;

    final options = <DeleteOption>[];

    if (session.isSleep) {
      options.add(DeleteOption.delete);
      return DeleteContext(
        session: session,
        previous: previous,
        next: next,
        availableOptions: options,
      );
    }

    if (session.isActive && previous != null) {
      options.add(DeleteOption.makePreviousActive);
    }

    if (!session.isActive) {
      if (previous != null) options.add(DeleteOption.extendPrevious);
      if (next != null) options.add(DeleteOption.extendNext);
    }

    options.add(DeleteOption.delete);

    return DeleteContext(
      session: session,
      previous: previous,
      next: next,
      availableOptions: options,
    );
  }

  /// Executes a delete option. Returns the ID of any unknown session created.
  Future<String?> executeDelete(
    DeleteOption option,
    DeleteContext ctx,
    FrontingSessionRepository repo,
  ) async {
    switch (option) {
      case DeleteOption.makePreviousActive:
        // Re-open previous session (remove its endTime).
        final updated = ctx.previous!.copyWith(endTime: null);
        await repo.updateSession(updated);
        await repo.deleteSession(ctx.session.id);
        return null;

      case DeleteOption.extendPrevious:
        final updated = ctx.previous!.copyWith(endTime: ctx.session.endTime);
        await repo.updateSession(updated);
        await repo.deleteSession(ctx.session.id);
        return null;

      case DeleteOption.extendNext:
        final updated = ctx.next!.copyWith(startTime: ctx.session.startTime);
        await repo.updateSession(updated);
        await repo.deleteSession(ctx.session.id);
        return null;

      case DeleteOption.delete:
        // Fill with unknown session if the deleted session had a time range.
        final endTime = ctx.session.isActive
            ? DateTime.now()
            : ctx.session.endTime;

        // Decide BEFORE deleting whether a filler is needed, and ensure the
        // Unknown sentinel up front. If `_ensureUnknownSentinel` throws
        // (e.g. no `MemberRepository` wired), we'd otherwise be left with
        // the original session deleted and no filler — a partial mutation.
        // Sleep deletes never get filled, so they skip the preflight.
        final needsFiller = !ctx.session.isSleep &&
            endTime != null &&
            endTime.difference(ctx.session.startTime).inSeconds > 0;

        if (needsFiller) {
          // Route the gap-filler row through the Unknown sentinel member so
          // the foreign key resolves and downstream code (validation,
          // exporters) doesn't need a special "memberId == null means
          // Unknown" branch.  Mirrors the pattern in
          // FrontingMutationService._ensureSentinelIfNeeded.
          await _ensureUnknownSentinel();
        }

        await repo.deleteSession(ctx.session.id);

        if (!needsFiller) {
          return null;
        }

        final unknownId = _uuid.v4();
        final unknown = FrontingSession(
          id: unknownId,
          startTime: ctx.session.startTime,
          endTime: endTime,
          memberId: unknownSentinelMemberId,
        );
        await repo.createSession(unknown);
        return unknownId;
    }
  }

  /// Trims an overlapping session to not overlap with the edited session.
  /// If trimming would make the session zero or negative duration, deletes it.
  Future<void> trimOverlap(
    FrontingSession edited,
    FrontingSession overlapping,
    FrontingSessionRepository repo,
  ) async {
    if (edited.sessionType != overlapping.sessionType) {
      return;
    }

    final editedEnd = edited.endTime ?? DateTime.now();
    final overlapEnd = overlapping.endTime ?? DateTime.now();

    if (overlapping.startTime.isBefore(edited.startTime)) {
      // Overlapping session started first — trim its end
      final trimmed = overlapping.copyWith(endTime: edited.startTime);
      if (edited.startTime.difference(overlapping.startTime).inSeconds > 0) {
        await repo.updateSession(trimmed);
      } else {
        await repo.deleteSession(overlapping.id);
      }
    } else {
      // Overlapping session started during edited — trim its start
      final trimmed = overlapping.copyWith(startTime: editedEnd);
      if (overlapEnd.difference(editedEnd).inSeconds > 0) {
        await repo.updateSession(trimmed);
      } else {
        await repo.deleteSession(overlapping.id);
      }
    }
  }

  /// Merges adjacent sessions into the target session. Extends the target
  /// to span all merged sessions and concatenates notes.
  Future<FrontingSession> mergeAdjacent(
    FrontingSession target,
    List<FrontingSession> toMerge,
    FrontingSessionRepository repo,
  ) async {
    if (target.isSleep) {
      return target;
    }

    final compatible = toMerge
        .where((session) => session.sessionType == target.sessionType)
        .toList();
    if (compatible.isEmpty) {
      return target;
    }

    var earliest = target.startTime;
    DateTime? latest = target.endTime;
    final allNotes = <String>[];
    if (target.notes != null && target.notes!.isNotEmpty) {
      allNotes.add(target.notes!);
    }

    for (final session in compatible) {
      if (session.startTime.isBefore(earliest)) {
        earliest = session.startTime;
      }
      if (session.endTime == null) {
        latest = null; // one of them is active
      } else if (latest != null && session.endTime!.isAfter(latest)) {
        latest = session.endTime;
      }
      if (session.notes != null && session.notes!.isNotEmpty) {
        allNotes.add(session.notes!);
      }
      await repo.deleteSession(session.id);
    }

    final merged = target.copyWith(
      startTime: earliest,
      endTime: latest,
      notes: allNotes.isNotEmpty ? allNotes.join(' | ') : null,
    );
    await repo.updateSession(merged);
    return merged;
  }

  /// Creates unknown sessions to fill gaps created by an edit.
  ///
  /// Each filler row is attributed to the Unknown sentinel member so it has
  /// a resolvable foreign key — see [executeDelete] for the same pattern.
  Future<void> fillGaps(
    List<GapInfo> gaps,
    FrontingSessionRepository repo,
  ) async {
    if (gaps.isEmpty) return;
    await _ensureUnknownSentinel();
    for (final gap in gaps) {
      final fill = FrontingSession(
        id: _uuid.v4(),
        startTime: gap.startTime,
        endTime: gap.endTime,
        memberId: unknownSentinelMemberId,
      );
      await repo.createSession(fill);
    }
  }

  // ── Quick-switch ───────────────────────────

  /// Evaluates whether a fronter switch should correct the existing session
  /// or create a new one, based on how recently the current session started.
  QuickSwitchAction evaluateQuickSwitch(
    FrontingSession? currentSession, {
    int thresholdSeconds = 30,
    DateTime? now,
  }) {
    if (currentSession == null || !currentSession.isActive) {
      return QuickSwitchAction.createNew;
    }

    final elapsed = (now ?? DateTime.now())
        .difference(currentSession.startTime)
        .inSeconds;

    if (thresholdSeconds > 0 && elapsed <= thresholdSeconds) {
      return QuickSwitchAction.correctExisting;
    }

    return QuickSwitchAction.createNew;
  }
}
