import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SessionType;
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_service.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

FrontingSessionSnapshot _snap({
  String id = 's1',
  String? memberId = 'alice',
  required DateTime start,
  DateTime? end,
  String? notes,
  int? confidenceIndex,
  SessionType sessionType = SessionType.normal,
}) {
  return FrontingSessionSnapshot(
    id: id,
    memberId: memberId,
    start: start,
    end: end,
    notes: notes,
    confidenceIndex: confidenceIndex,
    sessionType: sessionType,
  );
}

void main() {
  const service = FrontingEditResolutionService();

  // ════════════════════════════════════════════════════════════════════════════
  // computeTrimChanges
  // ════════════════════════════════════════════════════════════════════════════

  group('computeTrimChanges', () {
    test('partial overlap — edited starts first: conflicting start moves to edited end',
        () {
      // Edited: 10:00–12:00, Conflicting: 11:00–13:00
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );
      final conflicting = _snap(
        id: 'conflict',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 13, 0),
      );

      final result = service.computeTrimChanges(edited, conflicting);

      expect(result.wouldDeleteConflicting, isFalse);
      expect(result.changes, hasLength(1));
      final change = result.changes.first as UpdateSessionChange;
      expect(change.sessionId, 'conflict');
      expect(change.patch.start, DateTime(2025, 1, 1, 12, 0));
      expect(change.patch.end, isNull);
    });

    test('partial overlap — conflicting starts first: conflicting end moves to edited start',
        () {
      // Edited: 11:00–13:00, Conflicting: 10:00–12:00
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 13, 0),
      );
      final conflicting = _snap(
        id: 'conflict',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );

      final result = service.computeTrimChanges(edited, conflicting);

      expect(result.wouldDeleteConflicting, isFalse);
      expect(result.changes, hasLength(1));
      final change = result.changes.first as UpdateSessionChange;
      expect(change.sessionId, 'conflict');
      expect(change.patch.end, DateTime(2025, 1, 1, 11, 0));
      expect(change.patch.start, isNull);
    });

    test('full containment: conflicting deleted, wouldDeleteConflicting=true', () {
      // Edited: 10:00–14:00, Conflicting: 11:00–13:00 (fully inside)
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );
      final conflicting = _snap(
        id: 'conflict',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 13, 0),
      );

      final result = service.computeTrimChanges(edited, conflicting);

      expect(result.wouldDeleteConflicting, isTrue);
      expect(
        result.changes.whereType<DeleteSessionChange>().map((c) => c.sessionId),
        contains('conflict'),
      );
    });

    test('near-zero duration after trim: wouldDeleteConflicting=true', () {
      // Edited: 10:00–12:00, Conflicting: 11:00–12:00 — after trim start moves to 12:00 = zero duration
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );
      final conflicting = _snap(
        id: 'conflict',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );

      final result = service.computeTrimChanges(edited, conflicting);

      expect(result.wouldDeleteConflicting, isTrue);
      expect(
        result.changes.whereType<DeleteSessionChange>().map((c) => c.sessionId),
        contains('conflict'),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // resolveAllOverlaps
  // ════════════════════════════════════════════════════════════════════════════

  group('resolveAllOverlaps', () {
    test('cancel returns empty list', () {
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );
      final overlap = _snap(
        id: 'overlap',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 12, 0),
        end: DateTime(2025, 1, 1, 15, 0),
      );

      final changes = service.resolveAllOverlaps(
        edited: edited,
        overlaps: [overlap],
        resolution: OverlapResolution.cancel,
      );

      expect(changes, isEmpty);
    });

    test('cross-type overlaps are skipped — never trimmed (data-loss guard)', () {
      // An open-ended normal front whose effective end is far-future would
      // "contain" every later sleep session. resolveAllOverlaps must drop
      // cross-type overlaps so none are deleted, even if a caller passes them.
      final edited = _snap(
        id: 'front',
        start: DateTime(2025, 1, 1, 10, 0),
        end: null, // active / open-ended
        sessionType: SessionType.normal,
      );
      final sleeps = [
        for (var i = 1; i <= 5; i++)
          _snap(
            id: 'sleep$i',
            memberId: null,
            start: DateTime(2025, 1, 1 + i, 22, 0),
            end: DateTime(2025, 1, 2 + i, 6, 0),
            sessionType: SessionType.sleep,
          ),
      ];

      final changes = service.resolveAllOverlaps(
        edited: edited,
        overlaps: sleeps,
        resolution: OverlapResolution.trim,
      );

      expect(changes, isEmpty);
    });

    test('single overlap resolves correctly with trim', () {
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );
      final overlap = _snap(
        id: 'overlap',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 12, 0),
        end: DateTime(2025, 1, 1, 15, 0),
      );

      final changes = service.resolveAllOverlaps(
        edited: edited,
        overlaps: [overlap],
        resolution: OverlapResolution.trim,
      );

      expect(changes, isNotEmpty);
      // Should have trim change for the overlap
      final update = changes.whereType<UpdateSessionChange>().first;
      expect(update.sessionId, 'overlap');
      expect(update.patch.start, DateTime(2025, 1, 1, 14, 0));
    });

    // makeCoFronting is removed — cross-member overlaps are valid by design
    // and are never passed to resolveAllOverlaps. Only same-member self-overlaps
    // or sleep↔front cross-type overlaps reach resolution.

    test('multiple overlaps: boundaries update after each resolution', () {
      // Edited: 10:00–16:00
      // Overlap1: 11:00–13:00 (fully contained by edited — will be deleted)
      // Overlap2: 14:00–17:00 (partial overlap — will have start trimmed to 16:00)
      final edited = _snap(
        id: 'edited',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 16, 0),
      );
      final overlap1 = _snap(
        id: 'overlap1',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 13, 0),
      );
      final overlap2 = _snap(
        id: 'overlap2',
        memberId: 'charlie',
        start: DateTime(2025, 1, 1, 14, 0),
        end: DateTime(2025, 1, 1, 17, 0),
      );

      final changes = service.resolveAllOverlaps(
        edited: edited,
        overlaps: [overlap1, overlap2],
        resolution: OverlapResolution.trim,
      );

      // overlap1 is fully contained by edited, so it gets deleted
      final deletedIds = changes.whereType<DeleteSessionChange>()
          .map((c) => c.sessionId)
          .toSet();
      expect(deletedIds, contains('overlap1'));

      // overlap2 partially overlaps (extends past edited.end), so its start is trimmed
      final updatedIds = changes.whereType<UpdateSessionChange>()
          .map((c) => c.sessionId)
          .toSet();
      expect(updatedIds, contains('overlap2'));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // computeDeleteChanges
  // ════════════════════════════════════════════════════════════════════════════

  group('computeDeleteChanges', () {
    test('extendPrevious: previous end set to session end, session deleted', () {
      final session = _snap(
        id: 'to-delete',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );
      final previous = _snap(
        id: 'prev',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 11, 0),
      );
      final context = FrontingDeleteContext(
        session: session,
        previous: previous,
      );

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.extendPrevious);

      expect(changes, hasLength(2));
      final update = changes.whereType<UpdateSessionChange>().first;
      expect(update.sessionId, 'prev');
      expect(update.patch.end, DateTime(2025, 1, 1, 12, 0));
      expect(update.patch.clearEnd, isFalse);

      final del = changes.whereType<DeleteSessionChange>().first;
      expect(del.sessionId, 'to-delete');
    });

    test('extendPrevious on active session: previous gets clearEnd=true', () {
      final session = _snap(
        id: 'to-delete',
        start: DateTime(2025, 1, 1, 11, 0),
        end: null, // active
      );
      final previous = _snap(
        id: 'prev',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 11, 0),
      );
      final context = FrontingDeleteContext(
        session: session,
        previous: previous,
      );

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.extendPrevious);

      final update = changes.whereType<UpdateSessionChange>().first;
      expect(update.sessionId, 'prev');
      expect(update.patch.clearEnd, isTrue);
      expect(update.patch.end, isNull);
    });

    test('extendNext: next start set to session start, session deleted', () {
      final session = _snap(
        id: 'to-delete',
        start: DateTime(2025, 1, 1, 11, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );
      final next = _snap(
        id: 'next',
        memberId: 'charlie',
        start: DateTime(2025, 1, 1, 12, 0),
        end: DateTime(2025, 1, 1, 13, 0),
      );
      final context = FrontingDeleteContext(
        session: session,
        next: next,
      );

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.extendNext);

      expect(changes, hasLength(2));
      final update = changes.whereType<UpdateSessionChange>().first;
      expect(update.sessionId, 'next');
      expect(update.patch.start, DateTime(2025, 1, 1, 11, 0));

      final del = changes.whereType<DeleteSessionChange>().first;
      expect(del.sessionId, 'to-delete');
    });

    test('splitBetweenNeighbors: correct midpoint for both neighbors', () {
      final session = _snap(
        id: 'to-delete',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );
      final previous = _snap(
        id: 'prev',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 9, 0),
        end: DateTime(2025, 1, 1, 10, 0),
      );
      final next = _snap(
        id: 'next',
        memberId: 'charlie',
        start: DateTime(2025, 1, 1, 12, 0),
        end: DateTime(2025, 1, 1, 13, 0),
      );
      final context = FrontingDeleteContext(
        session: session,
        previous: previous,
        next: next,
      );

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.splitBetweenNeighbors);

      // midpoint of 10:00–12:00 is 11:00
      expect(changes, hasLength(3));
      final updates = changes.whereType<UpdateSessionChange>().toList();
      final prevUpdate = updates.firstWhere((u) => u.sessionId == 'prev');
      final nextUpdate = updates.firstWhere((u) => u.sessionId == 'next');
      expect(prevUpdate.patch.end, DateTime(2025, 1, 1, 11, 0));
      expect(nextUpdate.patch.start, DateTime(2025, 1, 1, 11, 0));

      final del = changes.whereType<DeleteSessionChange>().first;
      expect(del.sessionId, 'to-delete');
    });

    test(
        'convertToUnknown: memberId set to Unknown sentinel, '
        'session not deleted',
        () {
      // In the per-member model, coFronterIds no longer exists.
      // convertToUnknown writes the canonical Unknown sentinel id
      // directly so analytics treats the row identically to rows from
      // the "Front as Unknown" sheet — no clearMemberId / null-routing
      // step required at read time.
      final session = _snap(
        id: 'to-convert',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 11, 0),
      );
      final context = FrontingDeleteContext(session: session);

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.convertToUnknown);

      expect(changes, hasLength(1));
      final update = changes.whereType<UpdateSessionChange>().first;
      expect(update.sessionId, 'to-convert');
      expect(update.patch.clearMemberId, isFalse,
          reason: 'should write the sentinel id, not null');
      expect(update.patch.memberId, unknownSentinelMemberId);
    });

    test('leaveGap: just deletes the session', () {
      final session = _snap(
        id: 'to-delete',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 11, 0),
      );
      final context = FrontingDeleteContext(session: session);

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.leaveGap);

      expect(changes, hasLength(1));
      final del = changes.whereType<DeleteSessionChange>().first;
      expect(del.sessionId, 'to-delete');
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // computeGapFillChanges
  // ════════════════════════════════════════════════════════════════════════════

  group('computeGapFillChanges', () {
    test(
        'creates Unknown session with the sentinel memberId for each gap',
        () {
      final gaps = [
        GapInfo(
          start: DateTime(2025, 1, 1, 11, 0),
          end: DateTime(2025, 1, 1, 12, 0),
        ),
        GapInfo(
          start: DateTime(2025, 1, 1, 13, 0),
          end: DateTime(2025, 1, 1, 14, 0),
        ),
      ];

      final changes = service.computeGapFillChanges(gaps);

      expect(changes, hasLength(2));
      for (final change in changes) {
        final create = change as CreateSessionChange;
        // The writer side now produces the canonical sentinel id rather
        // than null — analytics no longer has to compensate, and the
        // change executor lazily creates the sentinel member entity
        // before the session row lands.
        expect(create.session.memberId, unknownSentinelMemberId);
      }
      final creates = changes.cast<CreateSessionChange>().toList();
      expect(creates[0].session.start, DateTime(2025, 1, 1, 11, 0));
      expect(creates[0].session.end, DateTime(2025, 1, 1, 12, 0));
      expect(creates[1].session.start, DateTime(2025, 1, 1, 13, 0));
      expect(creates[1].session.end, DateTime(2025, 1, 1, 14, 0));
    });

    test('returns empty list for empty gaps', () {
      final changes = service.computeGapFillChanges([]);
      expect(changes, isEmpty);
    });

    test('single gap creates one Unknown sentinel session', () {
      final gaps = [
        GapInfo(
          start: DateTime(2025, 1, 1, 11, 0),
          end: DateTime(2025, 1, 1, 12, 0),
          beforeSessionId: 'before',
          afterSessionId: 'after',
        ),
      ];

      final changes = service.computeGapFillChanges(gaps);

      expect(changes, hasLength(1));
      final create = changes.first as CreateSessionChange;
      expect(create.session.memberId, unknownSentinelMemberId);
      expect(create.session.start, DateTime(2025, 1, 1, 11, 0));
      expect(create.session.end, DateTime(2025, 1, 1, 12, 0));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // computeDeletePeriodChanges
  // ════════════════════════════════════════════════════════════════════════════

  group('computeDeletePeriodChanges', () {
    final pStart = DateTime(2026, 5, 1, 14, 0);
    final pEnd = DateTime(2026, 5, 1, 15, 0);

    test('fully-contained sessions → all deleted (leaveGap)', () {
      // Alice + Bob both fronting exactly [P_start, P_end].
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: pStart,
        end: pEnd,
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: pStart,
        end: pEnd,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      expect(changes, hasLength(2));
      expect(changes.whereType<DeleteSessionChange>().map((c) => c.sessionId),
          containsAll(['alice-s', 'bob-s']));
    });

    test('both-straddler with leaveGap → splits into halves; right-half '
        'carries splitFromSessionId for comment reparenting', () {
      // Alice [13:00, 16:00] crosses the period [14:00, 15:00].
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      // Expect: trim alice's end to P_start + create [P_end, 16:00] for alice.
      expect(changes, hasLength(2));
      final update = changes.whereType<UpdateSessionChange>().single;
      expect(update.sessionId, 'alice-s');
      expect(update.patch.end, pStart);
      final create = changes.whereType<CreateSessionChange>().single;
      expect(create.session.memberId, 'alice');
      expect(create.session.start, pEnd);
      expect(create.session.end, DateTime(2026, 5, 1, 16, 0));
      // The right-half references its source so the executor reparents
      // any comments timestamped in [pEnd, origEnd] onto the new session.
      expect(create.session.splitFromSessionId, 'alice-s');
      // Deterministic id (matches FrontingMutationService.splitSession's
      // splitNamespace pattern) so two synced devices converge instead
      // of creating duplicate right-half rows.
      final expectedPresetId = const Uuid().v5(
        splitNamespace,
        'alice-s:${pEnd.toUtc().toIso8601String()}',
      );
      expect(create.session.presetId, expectedPresetId);
    });

    test('both-straddler with extendPrevious → left untouched (covers slice)',
        () {
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: pStart,
        end: pEnd,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      // Alice (both-straddler) untouched. Bob (fully contained) deleted.
      expect(changes, hasLength(1));
      final delete = changes.single as DeleteSessionChange;
      expect(delete.sessionId, 'bob-s');
    });

    test('straddle-start-only with extendPrevious → end moves to P_end', () {
      // Alice [13:00, 14:30] dangles into the slice from before.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      expect(changes, hasLength(1));
      final update = changes.single as UpdateSessionChange;
      expect(update.sessionId, 'alice-s');
      expect(update.patch.end, pEnd);
      expect(update.patch.clearEnd, isFalse);
    });

    test('straddle-start-only with leaveGap → end trimmed to P_start', () {
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      expect(changes, hasLength(1));
      final update = changes.single as UpdateSessionChange;
      expect(update.sessionId, 'alice-s');
      expect(update.patch.end, pStart);
    });

    test('straddle-end-only → start trimmed to P_end (any strategy)', () {
      // Bob [14:30, 16:00] starts inside, extends past.
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [bob],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      expect(changes, hasLength(1));
      final update = changes.single as UpdateSessionChange;
      expect(update.sessionId, 'bob-s');
      expect(update.patch.start, pEnd);
    });

    test('extendPrevious + straddle-end: trim reparents to previousSession', () {
      // Carol ended at periodStart (touching previous). Bob starts inside
      // the slice and continues past pEnd (straddle-end). For
      // extendPrevious, Carol gets extended to pEnd; Bob is trimmed at
      // pEnd. Comments timestamped on Bob in [origStart, pEnd) should
      // move to Carol — matching single-session extendPrevious behavior.
      final carol = _snap(
        id: 'carol-s',
        memberId: 'carol',
        start: DateTime(2026, 5, 1, 13, 0),
        end: pStart,
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [bob],
        previousSessions: [carol],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      // Bob trim with reparent to Carol; Carol extended.
      final bobUpdate = changes
          .whereType<UpdateSessionChange>()
          .firstWhere((u) => u.sessionId == 'bob-s');
      expect(bobUpdate.patch.start, pEnd);
      expect(bobUpdate.patch.reparentOrphansToSessionId, 'carol-s');
      expect(bobUpdate.patch.dropOrphanedComments, isFalse);
    });

    test('extendPrevious + both-straddler + straddle-end: the both-straddler '
        'is the reparent target (it natively covers the slice)', () {
      // Alice spans the slice both directions (both-straddler) — left
      // intact under extendPrevious. Bob is straddle-end-only — trimmed
      // at pEnd. Bob's [origStart, pEnd) comments should land on Alice,
      // not be dropped, since Alice still owns that time.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 15, 30),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      // Alice left untouched. Bob is fully-contained in the slice
      // (start=14:30, end=15:30), so under extendPrevious he's deleted —
      // not trimmed. Comments on Bob would reparent via the executor's
      // delete→overlapping-update pass onto Alice (untouched updates
      // aren't checked, but Alice's range already covers Bob's). That
      // path is independent of `sliceCommentTargetId`; what we're
      // asserting here is the *target-selection* logic: if anything got
      // trimmed under extendPrevious, the both-straddler is the chosen
      // reparent target.
      //
      // Force the trim path by widening Bob into a real straddle-end.
      final bob2 = _snap(
        id: 'bob2-s',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 15, 30),
      );
      final straddleEnd = _snap(
        id: 'straddle-end-s',
        memberId: 'carol',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 30),
      );
      final ctx2 = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob2, straddleEnd],
      );
      final changes2 = service.computeDeletePeriodChanges(
        ctx2,
        FrontingDeleteStrategy.extendPrevious,
      );
      final straddleUpdate = changes2
          .whereType<UpdateSessionChange>()
          .firstWhere((u) => u.sessionId == 'straddle-end-s');
      expect(straddleUpdate.patch.start, pEnd);
      expect(straddleUpdate.patch.reparentOrphansToSessionId, 'alice-s');
      expect(straddleUpdate.patch.dropOrphanedComments, isFalse);
      // Sanity: also confirm the first call's change list compiles.
      expect(changes, isNotEmpty);
    });

    test('extendPrevious + straddle-end + straddle-start: straddle-start '
        'is the reparent target (it covers the slice after extension)', () {
      // Alice straddles start (extended to pEnd); Bob straddles end
      // (trimmed at pEnd). Bob's slice comments move to Alice (whose new
      // range covers them), not to any touching previousSession (none
      // here).
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 30),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      final bobUpdate = changes
          .whereType<UpdateSessionChange>()
          .firstWhere((u) => u.sessionId == 'bob-s');
      expect(bobUpdate.patch.reparentOrphansToSessionId, 'alice-s');
      expect(bobUpdate.patch.dropOrphanedComments, isFalse);
    });

    test('touching previousSessions extended under extendPrevious', () {
      // Carol's session ends exactly at periodStart.
      final carol = _snap(
        id: 'carol-s',
        memberId: 'carol',
        start: DateTime(2026, 5, 1, 13, 0),
        end: pStart,
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: pStart,
        end: pEnd,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [bob],
        previousSessions: [carol],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      // Bob deleted, Carol extended to P_end.
      expect(changes, hasLength(2));
      expect(
        changes.whereType<DeleteSessionChange>().map((c) => c.sessionId),
        contains('bob-s'),
      );
      final carolUpdate = changes
          .whereType<UpdateSessionChange>()
          .firstWhere((u) => u.sessionId == 'carol-s');
      expect(carolUpdate.patch.end, pEnd);
      expect(carolUpdate.patch.clearEnd, isFalse);
    });

    test('convertToUnknown survivor selection is deterministic across '
        'sessionsInPeriod order (CRDT convergence)', () {
      // Two equally-valid survivors (Alice and Bob, both fully-contained,
      // same start). Without a deterministic tiebreak, two synced
      // devices could pick different survivors and after sync's
      // per-field LWW both rows end up is_deleted=true — the Unknown
      // the user asked for disappears. Sort by (start, id) so every
      // device converges on the same id.
      final alice = _snap(
        id: 'aaa',
        memberId: 'alice',
        start: pStart,
        end: pEnd,
      );
      final bob = _snap(
        id: 'bbb',
        memberId: 'bob',
        start: pStart,
        end: pEnd,
      );

      // Call with both orderings — they must produce the same survivor.
      final ctx1 = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob],
      );
      final ctx2 = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [bob, alice],
      );
      final changes1 = service.computeDeletePeriodChanges(
        ctx1,
        FrontingDeleteStrategy.convertToUnknown,
      );
      final changes2 = service.computeDeletePeriodChanges(
        ctx2,
        FrontingDeleteStrategy.convertToUnknown,
      );
      final survivor1 = changes1.whereType<UpdateSessionChange>().firstWhere(
            (u) => u.patch.memberId == unknownSentinelMemberId,
          );
      final survivor2 = changes2.whereType<UpdateSessionChange>().firstWhere(
            (u) => u.patch.memberId == unknownSentinelMemberId,
          );
      expect(survivor1.sessionId, survivor2.sessionId);
      // Lower id wins under (start, id) sort with identical start.
      expect(survivor1.sessionId, 'aaa');
    });

    test('convertToUnknown repurposes a contained session as the Unknown '
        'survivor', () {
      // Single contained session: should be UPDATED to become the Unknown
      // — not Delete + Create, which would orphan its comments.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: pStart,
        end: pEnd,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.convertToUnknown,
      );

      expect(changes, hasLength(1));
      final update = changes.single as UpdateSessionChange;
      expect(update.sessionId, 'alice-s');
      expect(update.patch.memberId, unknownSentinelMemberId);
      expect(update.patch.start, pStart);
      expect(update.patch.end, pEnd);
      expect(update.patch.clearEnd, isFalse);
    });

    test('ongoing period: open-ended session inside is deleted (leaveGap)', () {
      // Alice started inside the period and is currently fronting.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: pStart,
        end: null,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: true,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      expect(changes, hasLength(1));
      expect(
        (changes.single as DeleteSessionChange).sessionId,
        'alice-s',
      );
    });

    test('ongoing period: extendPrevious clears previousSession end', () {
      // Carol ended at periodStart; Alice is currently fronting inside.
      final carol = _snap(
        id: 'carol-s',
        memberId: 'carol',
        start: DateTime(2026, 5, 1, 13, 0),
        end: pStart,
      );
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: pStart,
        end: null,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: true,
        sessionsInPeriod: [alice],
        previousSessions: [carol],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.extendPrevious,
      );

      // Alice deleted; Carol re-opened (clearEnd) so she's currently fronting.
      expect(changes, hasLength(2));
      expect(changes.whereType<DeleteSessionChange>().single.sessionId,
          'alice-s');
      final carolUpdate = changes.whereType<UpdateSessionChange>().single;
      expect(carolUpdate.sessionId, 'carol-s');
      expect(carolUpdate.patch.clearEnd, isTrue);
    });

    test('ongoing convertToUnknown repurposes the open-ended session as '
        'the survivor (clearEnd + Unknown memberId)', () {
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: pStart,
        end: null,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: true,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.convertToUnknown,
      );

      expect(changes, hasLength(1));
      final update = changes.single as UpdateSessionChange;
      expect(update.sessionId, 'alice-s');
      expect(update.patch.memberId, unknownSentinelMemberId);
      expect(update.patch.start, pStart);
      expect(update.patch.clearEnd, isTrue);
    });

    test('mixed period (fully-contained + straddle-start + straddle-end) '
        'with leaveGap', () {
      // Realistic shape: Alice was already fronting, Bob joins for the
      // period only, Carol takes over and keeps going past the slice.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 30),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: pStart,
        end: pEnd,
      );
      final carol = _snap(
        id: 'carol-s',
        memberId: 'carol',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob, carol],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      // Alice trimmed end → P_start, Bob deleted, Carol trimmed start → P_end.
      expect(changes, hasLength(3));
      final updates = {
        for (final u in changes.whereType<UpdateSessionChange>())
          u.sessionId: u.patch,
      };
      expect(updates['alice-s']!.end, pStart);
      expect(updates['carol-s']!.start, pEnd);
      expect(changes.whereType<DeleteSessionChange>().single.sessionId,
          'bob-s');
    });

    test('convertToUnknown with straddlers: slice cleared, contained '
        'session becomes Unknown survivor', () {
      // Alice straddles from before, Bob fully-contained, Carol straddles
      // past the end. Bob is the only fully-contained session, so it gets
      // repurposed as the Unknown survivor (no Delete + Create — keeps
      // Bob's comments intact).
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 30),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: pStart,
        end: pEnd,
      );
      final carol = _snap(
        id: 'carol-s',
        memberId: 'carol',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob, carol],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.convertToUnknown,
      );

      // 3 updates (alice trim + bob become Unknown + carol trim), no deletes,
      // no creates. The straddler trims reparent their slice comments onto
      // the Unknown survivor (Bob's id) so the slice's annotations don't
      // disappear under convertToUnknown.
      expect(changes, hasLength(3));
      expect(changes.whereType<DeleteSessionChange>(), isEmpty);
      expect(changes.whereType<CreateSessionChange>(), isEmpty);
      final updates = {
        for (final u in changes.whereType<UpdateSessionChange>())
          u.sessionId: u.patch,
      };
      expect(updates['alice-s']!.end, pStart);
      expect(updates['alice-s']!.reparentOrphansToSessionId, 'bob-s');
      expect(updates['alice-s']!.dropOrphanedComments, isFalse);
      expect(updates['carol-s']!.start, pEnd);
      expect(updates['carol-s']!.reparentOrphansToSessionId, 'bob-s');
      expect(updates['carol-s']!.dropOrphanedComments, isFalse);
      expect(updates['bob-s']!.memberId, unknownSentinelMemberId);
      expect(updates['bob-s']!.start, pStart);
      expect(updates['bob-s']!.end, pEnd);
    });

    test('convertToUnknown with only straddlers (no contained survivor) '
        'emits Unknown Create first and reparents slice comments to it',
        () {
      // Alice straddles start, Bob straddles end. No fully-contained
      // session to repurpose — emit the Unknown Create up front with a
      // preset id, then route the straddler-trim orphans onto that id
      // so slice comments survive the "Mark as Unknown" choice.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 30),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final bob = _snap(
        id: 'bob-s',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 30),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice, bob],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.convertToUnknown,
      );

      // Order matters: Create first (so its id exists by the time
      // subsequent trims reparent into it), then the two trims.
      expect(changes, hasLength(3));
      expect(changes.first, isA<CreateSessionChange>());
      final create = changes.first as CreateSessionChange;
      expect(create.session.memberId, unknownSentinelMemberId);
      expect(create.session.start, pStart);
      expect(create.session.end, pEnd);
      expect(create.session.presetId, isNotNull);
      final unknownId = create.session.presetId!;

      final updates = {
        for (final u in changes.whereType<UpdateSessionChange>())
          u.sessionId: u.patch,
      };
      expect(updates['alice-s']!.end, pStart);
      expect(updates['alice-s']!.reparentOrphansToSessionId, unknownId);
      expect(updates['bob-s']!.start, pEnd);
      expect(updates['bob-s']!.reparentOrphansToSessionId, unknownId);
    });

    test('convertToUnknown with both-straddler routes slice comments to '
        'the Unknown via sliceReparentToSessionId', () {
      // Single both-straddler. No fully-contained survivor, so the
      // Unknown Create gets a preset id; the right-half split carries
      // sliceReparentToSessionId pointing to that id, so comments
      // timestamped inside [pStart, pEnd) move to the Unknown.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.convertToUnknown,
      );

      // Order: Unknown Create, trim Alice, right-half Create.
      expect(changes, hasLength(3));
      final unknownCreate = changes.first as CreateSessionChange;
      expect(unknownCreate.session.memberId, unknownSentinelMemberId);
      expect(unknownCreate.session.presetId, isNotNull);
      final unknownId = unknownCreate.session.presetId!;

      final rightHalf = changes
          .whereType<CreateSessionChange>()
          .firstWhere((c) => c.session.memberId == 'alice');
      expect(rightHalf.session.start, pEnd);
      expect(rightHalf.session.splitFromSessionId, 'alice-s');
      expect(rightHalf.session.sliceReparentToSessionId, unknownId);
    });

    test(
        'ongoing period + both-straddler-open + leaveGap: trim end to '
        'P_start (no post-period continuation)', () {
      // Alice has been fronting from 13:00 and is still active.
      final alice = _snap(
        id: 'alice-s',
        memberId: 'alice',
        start: DateTime(2026, 5, 1, 13, 0),
        end: null,
      );
      final ctx = FrontingDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: true,
        sessionsInPeriod: [alice],
      );

      final changes = service.computeDeletePeriodChanges(
        ctx,
        FrontingDeleteStrategy.leaveGap,
      );

      // Single update closing Alice at P_start — no Create for a post-period
      // half, since the slice ends at "now" and there's no post-period time.
      expect(changes, hasLength(1));
      final update = changes.single as UpdateSessionChange;
      expect(update.sessionId, 'alice-s');
      expect(update.patch.end, pStart);
      expect(update.patch.clearEnd, isFalse);
    });
  });
}
