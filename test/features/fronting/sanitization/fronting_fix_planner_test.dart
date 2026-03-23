import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_models.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_planner.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

void main() {
  const planner = FrontingFixPlanner();

  // ─── Helpers ───────────────────────────────────────────────────────────────

  FrontingSessionSnapshot makeSession({
    required String id,
    required DateTime start,
    DateTime? end,
    String? memberId,
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

  FrontingValidationIssue makeIssue({
    required FrontingIssueType type,
    required List<String> sessionIds,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    List<String> memberIds = const [],
  }) {
    return FrontingValidationIssue(
      id: 'issue-1',
      type: type,
      severity: FrontingIssueSeverity.warning,
      sessionIds: sessionIds,
      memberIds: memberIds,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      summary: 'Test issue',
    );
  }

  // ─── Overlap: same member ─────────────────────────────────────────────────

  group('overlap – same member', () {
    final t0 = DateTime(2024, 1, 1, 10, 0);
    final t1 = DateTime(2024, 1, 1, 11, 0);
    final t2 = DateTime(2024, 1, 1, 12, 0);
    final t3 = DateTime(2024, 1, 1, 13, 0);

    final sessionA = makeSession(id: 'a', memberId: 'member-1', start: t0, end: t2);
    final sessionB = makeSession(id: 'b', memberId: 'member-1', start: t1, end: t3);

    final issue = makeIssue(
      type: FrontingIssueType.overlap,
      sessionIds: ['a', 'b'],
      memberIds: ['member-1'],
      rangeStart: t1,
      rangeEnd: t2,
    );

    test('returns a merge plan', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      expect(plans, isNotEmpty);
      expect(plans.any((p) => p.type == FrontingFixType.mergeAdjacent), isTrue);
    });

    test('merge plan covers both session ids', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final merge = plans.firstWhere((p) => p.type == FrontingFixType.mergeAdjacent);
      expect(merge.affectedSessionIds, containsAll(['a', 'b']));
    });

    test('merge plan keeps earliest start and latest end', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final merge = plans.firstWhere((p) => p.type == FrontingFixType.mergeAdjacent);

      // Should have an UpdateSessionChange for the kept session
      final updates = merge.changes.whereType<UpdateSessionChange>().toList();
      expect(updates, isNotEmpty);
      final kept = updates.first;
      expect(kept.patch.start, t0); // earliest start
      expect(kept.patch.end, t3); // latest end
    });

    test('merge plan deletes the other session', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final merge = plans.firstWhere((p) => p.type == FrontingFixType.mergeAdjacent);

      final deletes = merge.changes.whereType<DeleteSessionChange>().toList();
      expect(deletes.length, 1);
    });
  });

  // ─── Overlap: different members ───────────────────────────────────────────

  group('overlap – different members', () {
    final t0 = DateTime(2024, 1, 1, 10, 0);
    final t1 = DateTime(2024, 1, 1, 11, 0);
    final t2 = DateTime(2024, 1, 1, 12, 0);
    final t3 = DateTime(2024, 1, 1, 13, 0);

    final sessionA = makeSession(id: 'a', memberId: 'member-1', start: t0, end: t2);
    final sessionB = makeSession(id: 'b', memberId: 'member-2', start: t1, end: t3);

    final issue = makeIssue(
      type: FrontingIssueType.overlap,
      sessionIds: ['a', 'b'],
      memberIds: ['member-1', 'member-2'],
      rangeStart: t1,
      rangeEnd: t2,
    );

    test('returns two trim plans', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final trimEarlier = plans.where((p) => p.type == FrontingFixType.trimEarlier).toList();
      final trimLater = plans.where((p) => p.type == FrontingFixType.trimLater).toList();
      expect(trimEarlier, isNotEmpty);
      expect(trimLater, isNotEmpty);
    });

    test('trimEarlier sets earlier session end to later session start', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final trim = plans.firstWhere((p) => p.type == FrontingFixType.trimEarlier);

      final updates = trim.changes.whereType<UpdateSessionChange>().toList();
      expect(updates.length, 1);
      // Earlier session (a) end should be trimmed to start of later session (b)
      expect(updates.first.sessionId, 'a');
      expect(updates.first.patch.end, t1);
    });

    test('trimLater sets later session start to earlier session end', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final trim = plans.firstWhere((p) => p.type == FrontingFixType.trimLater);

      final updates = trim.changes.whereType<UpdateSessionChange>().toList();
      expect(updates.length, 1);
      // Later session (b) start should be trimmed to end of earlier session (a)
      expect(updates.first.sessionId, 'b');
      expect(updates.first.patch.start, t2);
    });
  });

  // ─── Gap ─────────────────────────────────────────────────────────────────

  group('gap', () {
    final t0 = DateTime(2024, 1, 1, 10, 0);
    final t1 = DateTime(2024, 1, 1, 11, 0);
    final t2 = DateTime(2024, 1, 1, 12, 0);
    final t3 = DateTime(2024, 1, 1, 13, 0);

    final sessionA = makeSession(id: 'a', memberId: 'member-1', start: t0, end: t1);
    final sessionB = makeSession(id: 'b', memberId: 'member-2', start: t2, end: t3);

    final issue = makeIssue(
      type: FrontingIssueType.gap,
      sessionIds: ['a', 'b'],
      rangeStart: t1,
      rangeEnd: t2,
    );

    test('returns fill and leave plans', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      expect(plans.any((p) => p.type == FrontingFixType.fillGapWithUnknown), isTrue);
      expect(plans.any((p) => p.type == FrontingFixType.leaveGap), isTrue);
    });

    test('fill plan creates a session with null memberId spanning the gap', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final fill = plans.firstWhere((p) => p.type == FrontingFixType.fillGapWithUnknown);

      final creates = fill.changes.whereType<CreateSessionChange>().toList();
      expect(creates.length, 1);
      expect(creates.first.session.memberId, isNull);
      expect(creates.first.session.start, t1);
      expect(creates.first.session.end, t2);
    });

    test('leaveGap plan has empty changes list', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final leave = plans.firstWhere((p) => p.type == FrontingFixType.leaveGap);
      expect(leave.changes, isEmpty);
    });
  });

  // ─── Duplicate ────────────────────────────────────────────────────────────

  group('duplicate', () {
    final t0 = DateTime(2024, 1, 1, 10, 0);
    final t1 = DateTime(2024, 1, 1, 12, 0);

    // Session A has more data (notes + confidence), B has less
    final sessionA = makeSession(
      id: 'a',
      memberId: 'member-1',
      start: t0,
      end: t1,
      notes: 'Some notes',
      confidenceIndex: 4,
      coFronterIds: ['member-2'],
    );
    final sessionB = makeSession(
      id: 'b',
      memberId: 'member-1',
      start: t0,
      end: t1,
    );

    final issue = makeIssue(
      type: FrontingIssueType.duplicate,
      sessionIds: ['a', 'b'],
      memberIds: ['member-1'],
      rangeStart: t0,
      rangeEnd: t1,
    );

    test('returns a deleteDuplicate plan', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      expect(plans.any((p) => p.type == FrontingFixType.deleteDuplicate), isTrue);
    });

    test('deletes the session with less data (B)', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final del = plans.firstWhere((p) => p.type == FrontingFixType.deleteDuplicate);

      final deletes = del.changes.whereType<DeleteSessionChange>().toList();
      expect(deletes.length, 1);
      expect(deletes.first.sessionId, 'b');
    });
  });

  // ─── Mergeable adjacent ───────────────────────────────────────────────────

  group('mergeableAdjacent', () {
    final t0 = DateTime(2024, 1, 1, 10, 0);
    final t1 = DateTime(2024, 1, 1, 12, 0);
    final t2 = DateTime(2024, 1, 1, 14, 0);

    final sessionA = makeSession(
      id: 'a',
      memberId: 'member-1',
      start: t0,
      end: t1,
      notes: 'First',
    );
    final sessionB = makeSession(
      id: 'b',
      memberId: 'member-1',
      start: t1,
      end: t2,
      notes: 'Second',
    );

    final issue = makeIssue(
      type: FrontingIssueType.mergeableAdjacent,
      sessionIds: ['a', 'b'],
      memberIds: ['member-1'],
      rangeStart: t0,
      rangeEnd: t2,
    );

    test('returns a mergeAdjacent plan', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      expect(plans.any((p) => p.type == FrontingFixType.mergeAdjacent), isTrue);
    });

    test('merge extends earlier session to cover both', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final merge = plans.firstWhere((p) => p.type == FrontingFixType.mergeAdjacent);

      final updates = merge.changes.whereType<UpdateSessionChange>().toList();
      expect(updates, isNotEmpty);
      final update = updates.firstWhere((u) => u.sessionId == 'a');
      expect(update.patch.end, t2);
    });

    test('merge deletes later session', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final merge = plans.firstWhere((p) => p.type == FrontingFixType.mergeAdjacent);

      final deletes = merge.changes.whereType<DeleteSessionChange>().toList();
      expect(deletes.length, 1);
      expect(deletes.first.sessionId, 'b');
    });

    test('merge joins notes with separator', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      final merge = plans.firstWhere((p) => p.type == FrontingFixType.mergeAdjacent);

      final updates = merge.changes.whereType<UpdateSessionChange>().toList();
      final update = updates.firstWhere((u) => u.sessionId == 'a');
      expect(update.patch.notes, 'First | Second');
    });
  });

  // ─── Invalid range ────────────────────────────────────────────────────────

  group('invalidRange', () {
    // end before start
    final t0 = DateTime(2024, 1, 1, 12, 0);
    final t1 = DateTime(2024, 1, 1, 10, 0); // earlier than t0

    final session = makeSession(id: 'a', memberId: 'member-1', start: t0, end: t1);

    final issue = makeIssue(
      type: FrontingIssueType.invalidRange,
      sessionIds: ['a'],
      memberIds: ['member-1'],
      rangeStart: t1,
      rangeEnd: t0,
    );

    test('returns swapStartEnd and deleteSession plans', () {
      final plans = planner.plansForIssue(issue, [session]);
      expect(plans.any((p) => p.type == FrontingFixType.swapStartEnd), isTrue);
      expect(plans.any((p) => p.type == FrontingFixType.deleteSession), isTrue);
    });

    test('swap plan swaps start and end', () {
      final plans = planner.plansForIssue(issue, [session]);
      final swap = plans.firstWhere((p) => p.type == FrontingFixType.swapStartEnd);

      final updates = swap.changes.whereType<UpdateSessionChange>().toList();
      expect(updates.length, 1);
      expect(updates.first.patch.start, t1); // was end
      expect(updates.first.patch.end, t0);   // was start
    });

    test('delete plan removes the session', () {
      final plans = planner.plansForIssue(issue, [session]);
      final del = plans.firstWhere((p) => p.type == FrontingFixType.deleteSession);

      final deletes = del.changes.whereType<DeleteSessionChange>().toList();
      expect(deletes.length, 1);
      expect(deletes.first.sessionId, 'a');
    });
  });

  // ─── Future session ───────────────────────────────────────────────────────

  group('futureSession', () {
    final futureStart = DateTime.now().add(const Duration(hours: 2));
    final futureEnd = DateTime.now().add(const Duration(hours: 4));

    final session = makeSession(id: 'a', memberId: 'member-1', start: futureStart, end: futureEnd);

    final issue = makeIssue(
      type: FrontingIssueType.futureSession,
      sessionIds: ['a'],
      memberIds: ['member-1'],
      rangeStart: futureStart,
      rangeEnd: futureEnd,
    );

    test('returns a clampToNow plan', () {
      final plans = planner.plansForIssue(issue, [session]);
      expect(plans.any((p) => p.type == FrontingFixType.clampToNow), isTrue);
    });

    test('clamp plan adjusts start to now or earlier', () {
      final before = DateTime.now();
      final plans = planner.plansForIssue(issue, [session]);
      final after = DateTime.now();

      final clamp = plans.firstWhere((p) => p.type == FrontingFixType.clampToNow);
      final updates = clamp.changes.whereType<UpdateSessionChange>().toList();
      expect(updates, isNotEmpty);

      final newStart = updates.first.patch.start;
      expect(newStart, isNotNull);
      // newStart should be at or between before and after (i.e. "now" at plan generation time)
      expect(
        newStart!.millisecondsSinceEpoch >= before.millisecondsSinceEpoch - 1000 &&
            newStart.millisecondsSinceEpoch <= after.millisecondsSinceEpoch + 1000,
        isTrue,
        reason: 'Expected newStart to be approximately now',
      );
    });
  });

  // ─── Preview generation ───────────────────────────────────────────────────

  group('buildPreview', () {
    final t0 = DateTime(2024, 1, 1, 10, 0);
    final t1 = DateTime(2024, 1, 1, 12, 0);
    final t2 = DateTime(2024, 1, 1, 14, 0);

    final sessionA = makeSession(id: 'a', memberId: 'member-1', start: t0, end: t1, notes: 'A');
    final sessionB = makeSession(id: 'b', memberId: 'member-1', start: t1, end: t2, notes: 'B');

    final issue = makeIssue(
      type: FrontingIssueType.mergeableAdjacent,
      sessionIds: ['a', 'b'],
      memberIds: ['member-1'],
      rangeStart: t0,
      rangeEnd: t2,
    );

    test('preview has non-empty summary', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      for (final plan in plans) {
        final preview = planner.buildPreview(plan);
        expect(preview.summary.trim(), isNotEmpty,
            reason: 'Plan ${plan.type} should have non-empty summary');
      }
    });

    test('preview has at least one bullet point', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      for (final plan in plans) {
        final preview = planner.buildPreview(plan);
        expect(preview.bulletPoints, isNotEmpty,
            reason: 'Plan ${plan.type} should have bullet points');
        for (final bp in preview.bulletPoints) {
          expect(bp.trim(), isNotEmpty);
        }
      }
    });

    test('preview plan reference matches the plan', () {
      final plans = planner.plansForIssue(issue, [sessionA, sessionB]);
      for (final plan in plans) {
        final preview = planner.buildPreview(plan);
        expect(preview.plan, same(plan));
      }
    });
  });
}
