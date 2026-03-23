import 'package:flutter_test/flutter_test.dart';
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
  List<String> coFronterIds = const [],
  String? notes,
  int? confidenceIndex,
}) {
  return FrontingSessionSnapshot(
    id: id,
    memberId: memberId,
    start: start,
    end: end,
    coFronterIds: coFronterIds,
    notes: notes,
    confidenceIndex: confidenceIndex,
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
      // Edited: 10:00–12:00, Conflicting: 11:59–12:01 — after trim start moves to 12:00 = 1min
      // Let's make it zero: Conflicting: 12:00–12:00 won't happen, use same start/end
      // Instead: Conflicting 11:00–12:00 fully covered by edited 10:00–12:00
      final edited = _snap(
        id: 'edited',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 12, 0),
      );
      // Conflicting: 11:00–12:00 - after trim start would move to 12:00 = zero duration
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
  // computeCoFrontingChanges
  // ════════════════════════════════════════════════════════════════════════════

  group('computeCoFrontingChanges', () {
    test('partial overlap produces 3 changes (update A, create co-front, update B)',
        () {
      // A (alice, 10:00–14:00) overlaps B (bob, 13:00–15:00)
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      expect(changes, hasLength(3));
      expect(changes.whereType<UpdateSessionChange>(), hasLength(2));
      expect(changes.whereType<CreateSessionChange>(), hasLength(1));
    });

    test('co-front segment has edited member as memberId, conflicting as co-fronter',
        () {
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      final create = changes.whereType<CreateSessionChange>().first;
      expect(create.session.memberId, 'alice');
      expect(create.session.coFronterIds, contains('bob'));
    });

    test('existing co-fronters merge without duplicates', () {
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
        coFronterIds: ['charlie'], // alice already co-fronts with charlie
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
        coFronterIds: ['charlie'], // bob also co-fronts with charlie
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      final create = changes.whereType<CreateSessionChange>().first;
      // Should have bob and charlie, but charlie not duplicated
      expect(create.session.coFronterIds, contains('bob'));
      expect(create.session.coFronterIds, contains('charlie'));
      expect(create.session.coFronterIds.where((id) => id == 'charlie').length, 1);
      // alice is the memberId, should not be in coFronterIds
      expect(create.session.coFronterIds, isNot(contains('alice')));
    });

    test('higher confidence used in co-front segment', () {
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
        confidenceIndex: 0, // unsure
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
        confidenceIndex: 2, // certain
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      final create = changes.whereType<CreateSessionChange>().first;
      expect(create.session.confidenceIndex, 2); // higher wins
    });

    test('notes joined with " | "', () {
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
        notes: 'Alice note',
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
        notes: 'Bob note',
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      final create = changes.whereType<CreateSessionChange>().first;
      expect(create.session.notes, 'Alice note | Bob note');
    });

    test('notes: only one note, no separator', () {
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
        notes: 'Alice note',
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
        notes: null,
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      final create = changes.whereType<CreateSessionChange>().first;
      expect(create.session.notes, 'Alice note');
    });

    test('full containment: 4 changes (update A end, create co-front, create solo A, delete B)',
        () {
      // Edited A: 10:00–16:00, Conflicting B: 12:00–14:00 (fully inside A)
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 16, 0),
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 12, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      expect(changes, hasLength(4));
      // update A (trim to overlapStart)
      // create co-front (12:00–14:00)
      // create solo A (14:00–16:00)
      // delete B
      expect(changes.whereType<UpdateSessionChange>(), hasLength(1));
      expect(changes.whereType<CreateSessionChange>(), hasLength(2));
      expect(changes.whereType<DeleteSessionChange>(), hasLength(1));

      final del = changes.whereType<DeleteSessionChange>().first;
      expect(del.sessionId, 'bob-session');
    });

    test('active session overlap: active co-front segment keeps null end', () {
      // Edited A: 10:00–active, Conflicting B: 12:00–active
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: null, // active
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 12, 0),
        end: null, // active
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      final create = changes.whereType<CreateSessionChange>().first;
      // co-front segment should be active (null end) since both were active
      expect(create.session.end, isNull);
    });

    test('partial overlap where conflicting starts first: update conflicting end, create co-front, update edited start',
        () {
      // A (alice, 13:00–15:00) overlaps B (bob, 10:00–14:00), bob starts first
      final edited = _snap(
        id: 'alice-session',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 13, 0),
        end: DateTime(2025, 1, 1, 15, 0),
      );
      final conflicting = _snap(
        id: 'bob-session',
        memberId: 'bob',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 14, 0),
      );

      final changes = service.computeCoFrontingChanges(edited, conflicting);

      expect(changes, hasLength(3));
      // update B end to 13:00, create co-front 13:00–14:00, update A start to 14:00
      final updates = changes.whereType<UpdateSessionChange>().toList();
      final conflictingUpdate = updates.firstWhere((u) => u.sessionId == 'bob-session');
      expect(conflictingUpdate.patch.end, DateTime(2025, 1, 1, 13, 0));

      final editedUpdate = updates.firstWhere((u) => u.sessionId == 'alice-session');
      expect(editedUpdate.patch.start, DateTime(2025, 1, 1, 14, 0));

      final create = changes.whereType<CreateSessionChange>().first;
      expect(create.session.start, DateTime(2025, 1, 1, 13, 0));
      expect(create.session.end, DateTime(2025, 1, 1, 14, 0));
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

    test('single overlap resolves correctly with makeCoFronting', () {
      final edited = _snap(
        id: 'edited',
        memberId: 'alice',
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
        resolution: OverlapResolution.makeCoFronting,
      );

      expect(changes, isNotEmpty);
      expect(changes.whereType<CreateSessionChange>(), isNotEmpty);
    });

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

    test('convertToUnknown: memberId cleared, coFronterIds cleared, not deleted', () {
      final session = _snap(
        id: 'to-convert',
        memberId: 'alice',
        start: DateTime(2025, 1, 1, 10, 0),
        end: DateTime(2025, 1, 1, 11, 0),
        coFronterIds: ['bob'],
      );
      final context = FrontingDeleteContext(session: session);

      final changes = service.computeDeleteChanges(
          context, FrontingDeleteStrategy.convertToUnknown);

      expect(changes, hasLength(1));
      final update = changes.whereType<UpdateSessionChange>().first;
      expect(update.sessionId, 'to-convert');
      expect(update.patch.clearMemberId, isTrue);
      expect(update.patch.coFronterIds, isEmpty);
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
    test('creates Unknown session with null memberId for each gap', () {
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
        expect(create.session.memberId, isNull);
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

    test('single gap creates one Unknown session', () {
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
      expect(create.session.memberId, isNull);
      expect(create.session.coFronterIds, isEmpty);
      expect(create.session.start, DateTime(2025, 1, 1, 11, 0));
      expect(create.session.end, DateTime(2025, 1, 1, 12, 0));
    });
  });
}
