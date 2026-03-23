import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_guard.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_service.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_planner.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_session_validator.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Apply a list of [FrontingSessionChange] mutations to a snapshot list and
/// return the resulting timeline sorted by start time.
List<FrontingSessionSnapshot> applyChanges(
  List<FrontingSessionSnapshot> sessions,
  List<FrontingSessionChange> changes,
) {
  final result = [...sessions];
  for (final change in changes) {
    switch (change) {
      case CreateSessionChange(:final session):
        result.add(FrontingSessionSnapshot(
          id: 'new-${result.length}',
          memberId: session.memberId,
          start: session.start,
          end: session.end,
          coFronterIds: session.coFronterIds,
        ));
      case UpdateSessionChange(:final sessionId, :final patch):
        final idx = result.indexWhere((s) => s.id == sessionId);
        if (idx >= 0) {
          final s = result[idx];
          result[idx] = FrontingSessionSnapshot(
            id: s.id,
            memberId: patch.clearMemberId ? null : (patch.memberId ?? s.memberId),
            start: patch.start ?? s.start,
            end: patch.clearEnd ? null : (patch.end ?? s.end),
            coFronterIds: patch.coFronterIds ?? s.coFronterIds,
          );
        }
      case DeleteSessionChange(:final sessionId):
        result.removeWhere((s) => s.id == sessionId);
    }
  }
  result.sort((a, b) => a.start.compareTo(b.start));
  return result;
}

/// Build a snapshot anchored relative to a base time.
FrontingSessionSnapshot makeSnapshot({
  required String id,
  required DateTime start,
  DateTime? end,
  String memberId = 'alice',
  List<String> coFronterIds = const [],
}) {
  return FrontingSessionSnapshot(
    id: id,
    memberId: memberId,
    start: start,
    end: end,
    coFronterIds: coFronterIds,
  );
}

void main() {
  // Base anchor: 2 days ago so all sessions are safely in the past.
  final base = DateTime.now().subtract(const Duration(days: 2));

  DateTime h(int hour) => base.copyWith(hour: hour, minute: 0, second: 0, millisecond: 0, microsecond: 0);

  const service = FrontingEditResolutionService();
  const guard = FrontingEditGuard();
  const planner = FrontingFixPlanner();
  const validator = FrontingSessionValidator(
    config: FrontingValidationConfig(
      detectGaps: false, // suppress gap noise in integration tests
      detectMergeableAdjacent: false,
      detectDuplicates: false,
      detectFutureSessions: false,
    ),
  );

  // ---------------------------------------------------------------------------
  // Test 1: edit creates overlap → resolve as co-fronting → timeline is clean
  // ---------------------------------------------------------------------------

  group('edit creates overlap → resolve as co-fronting → timeline is clean', () {
    test('three segments with no overlap issues after co-fronting resolution', () {
      // Initial timeline: Alice 10:00–12:00, Bob 12:00–14:00
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      var timeline = [alice, bob];

      // Edit: extend Alice to 13:00 (overlaps Bob by 1 hour)
      final editedAlice = makeSnapshot(id: 'alice', start: h(10), end: h(13), memberId: 'alice');

      // Detect overlap via the edit guard
      final validation = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(validation.canSaveDirectly, isFalse);
      expect(validation.overlappingSessions, hasLength(1));
      expect(validation.overlappingSessions.first.id, 'bob');

      // Resolve as co-fronting
      final changes = service.resolveAllOverlaps(
        edited: editedAlice,
        overlaps: validation.overlappingSessions,
        resolution: OverlapResolution.makeCoFronting,
      );

      expect(changes, isNotEmpty);

      // Apply changes to the timeline (alice was extended, so update her first)
      timeline = applyChanges(timeline, [
        UpdateSessionChange(
          sessionId: 'alice',
          patch: FrontingSessionPatch(end: h(13)),
        ),
      ]);
      timeline = applyChanges(timeline, changes);

      // Verify: at least 3 segments
      expect(timeline.length, greaterThanOrEqualTo(3));

      // Verify: no overlap issues on rescan
      final issues = validator.validate(timeline);
      final overlaps = issues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(overlaps, isEmpty, reason: 'No overlaps expected after co-fronting resolution');

      // The overlap segment must have both alice and bob represented
      final coFrontSegment = timeline.where((s) =>
          s.coFronterIds.isNotEmpty || (s.memberId == 'alice' && s.coFronterIds.contains('bob')),
      ).toList();
      expect(coFrontSegment, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 2: edit creates overlap → resolve as trim → timeline is clean
  // ---------------------------------------------------------------------------

  group('edit creates overlap → resolve as trim → timeline is clean', () {
    test('two segments remain with no overlap issues after trim resolution', () {
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      var timeline = [alice, bob];

      final editedAlice = makeSnapshot(id: 'alice', start: h(10), end: h(13), memberId: 'alice');

      final validation = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(validation.canSaveDirectly, isFalse);
      expect(validation.overlappingSessions, hasLength(1));

      // Resolve as trim
      final changes = service.resolveAllOverlaps(
        edited: editedAlice,
        overlaps: validation.overlappingSessions,
        resolution: OverlapResolution.trim,
      );

      expect(changes, isNotEmpty);

      // Apply the extended alice then the trim changes
      timeline = applyChanges(timeline, [
        UpdateSessionChange(
          sessionId: 'alice',
          patch: FrontingSessionPatch(end: h(13)),
        ),
      ]);
      timeline = applyChanges(timeline, changes);

      // Verify: 2 segments (trim may delete or shrink bob)
      expect(timeline.length, lessThanOrEqualTo(2));

      // Verify: no overlap issues
      final issues = validator.validate(timeline);
      final overlaps = issues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(overlaps, isEmpty, reason: 'No overlaps expected after trim resolution');
    });
  });

  // ---------------------------------------------------------------------------
  // Test 3: Delete with each of the 5 strategies
  // ---------------------------------------------------------------------------

  group('delete with each strategy produces valid timeline', () {
    // 3-session timeline: Alice 10–11, Bob 11–12, Carol 12–13
    late FrontingSessionSnapshot alice;
    late FrontingSessionSnapshot bob;
    late FrontingSessionSnapshot carol;
    late List<FrontingSessionSnapshot> threeSessionTimeline;

    setUp(() {
      alice = makeSnapshot(id: 'alice', start: h(10), end: h(11), memberId: 'alice');
      bob = makeSnapshot(id: 'bob', start: h(11), end: h(12), memberId: 'bob');
      carol = makeSnapshot(id: 'carol', start: h(12), end: h(13), memberId: 'carol');
      threeSessionTimeline = [alice, bob, carol];
    });

    for (final strategy in FrontingDeleteStrategy.values) {
      test('delete middle session with $strategy', () {
        final context = guard.getDeleteContext(bob, threeSessionTimeline);

        // Skip strategies that require a neighbor that doesn't exist —
        // the guard only offers valid strategies, so we check availability.
        if (!context.availableStrategies.contains(strategy)) {
          // Strategy not available for this context, nothing to test.
          return;
        }

        final changes = service.computeDeleteChanges(context, strategy);
        expect(changes, isNotEmpty);

        var result = applyChanges(threeSessionTimeline, changes);
        result = result.where((s) => !s.isDeleted).toList();

        switch (strategy) {
          case FrontingDeleteStrategy.leaveGap:
            // Bob deleted, gap remains — 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);

          case FrontingDeleteStrategy.convertToUnknown:
            // Bob kept but memberId cleared — still 3 sessions
            expect(result.length, equals(3));
            final unknown = result.firstWhere((s) => s.id == 'bob');
            expect(unknown.memberId, isNull);

          case FrontingDeleteStrategy.extendPrevious:
            // Alice extended to cover Bob's time, Bob deleted — 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);
            final extAlice = result.firstWhere((s) => s.id == 'alice');
            expect(extAlice.end, equals(h(12)));

          case FrontingDeleteStrategy.extendNext:
            // Carol pulled back to cover Bob's time, Bob deleted — 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);
            final extCarol = result.firstWhere((s) => s.id == 'carol');
            expect(extCarol.start, equals(h(11)));

          case FrontingDeleteStrategy.splitBetweenNeighbors:
            // Alice and Carol each take half of Bob's hour, Bob deleted — 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);
            final extAlice = result.firstWhere((s) => s.id == 'alice');
            final extCarol = result.firstWhere((s) => s.id == 'carol');
            // Midpoint of 11:00–12:00 = 11:30
            final midpoint = h(11).add(const Duration(minutes: 30));
            expect(extAlice.end, equals(midpoint));
            expect(extCarol.start, equals(midpoint));
        }

        // Final check: no overlaps in the resulting timeline
        final issues = validator.validate(result);
        final overlaps = issues.where((i) => i.type == FrontingIssueType.overlap).toList();
        expect(overlaps, isEmpty,
            reason: 'No overlaps after delete with $strategy');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Test 4: Sanitization scan → fix → rescan is clean
  // ---------------------------------------------------------------------------

  group('sanitization: scan finds issues, fix resolves them, rescan is clean', () {
    test('overlap issue detected, first fix plan applied, rescan shows no overlaps', () {
      // Create timeline with known overlap: Alice 10–13, Bob 12–14
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(13), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      var timeline = [alice, bob];

      // Scan via validator
      final scanIssues = validator.validate(timeline);
      final overlapIssues = scanIssues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(overlapIssues, isNotEmpty, reason: 'Should detect the overlap');

      // Generate fix plan via planner (use first available plan)
      final issue = overlapIssues.first;
      final plans = planner.plansForIssue(issue, timeline);
      expect(plans, isNotEmpty, reason: 'Planner should offer at least one fix');

      final chosenPlan = plans.first;
      expect(chosenPlan.changes, isNotEmpty);

      // Apply fix
      timeline = applyChanges(timeline, chosenPlan.changes);

      // Rescan — no overlap issues
      final rescanIssues = validator.validate(timeline);
      final remainingOverlaps = rescanIssues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(remainingOverlaps, isEmpty,
          reason: 'No overlaps should remain after applying fix plan');
    });
  });

  // ---------------------------------------------------------------------------
  // Test 5: Edit guard validates correctly
  // ---------------------------------------------------------------------------

  group('edit guard validates correctly', () {
    test('edit guard blocks overlapping edit', () {
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      final timeline = [alice, bob];

      // Extend Alice into Bob's range
      final result = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(result.canSaveDirectly, isFalse);
      expect(result.overlappingSessions, isNotEmpty);
      expect(result.overlappingSessions.map((s) => s.id), contains('bob'));
    });

    test('edit guard allows clean edit', () {
      // Alice 10–12 is the only session — shrinking her end to 11 creates no
      // overlap and no reportable gap (there is no neighboring session).
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final timeline = [alice];

      // Shrink Alice slightly — no overlap, no gap (no neighbors)
      final result = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(11)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(result.canSaveDirectly, isTrue);
      expect(result.overlappingSessions, isEmpty);
    });

    test('edit guard allows edit that exactly touches neighbor boundary', () {
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      final timeline = [alice, bob];

      // Alice end exactly at Bob start — touching, not overlapping
      final result = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(12)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(result.canSaveDirectly, isTrue);
      expect(result.overlappingSessions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Test 6: Multiple overlaps resolved in sequence
  // ---------------------------------------------------------------------------

  group('multiple overlaps resolved with boundary tracking', () {
    test('resolveAllOverlaps with trim handles two neighbors', () {
      // Alice 10–15 (extended), Bob 13–14, Carol 14–16
      // Alice overlaps both Bob and Carol
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(15), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(13), end: h(14), memberId: 'bob');
      final carol = makeSnapshot(id: 'carol', start: h(14), end: h(16), memberId: 'carol');
      var timeline = [alice, bob, carol];

      // Detect overlaps against alice
      final overlaps = [bob, carol];

      final changes = service.resolveAllOverlaps(
        edited: alice,
        overlaps: overlaps,
        resolution: OverlapResolution.trim,
      );

      expect(changes, isNotEmpty);

      timeline = applyChanges(timeline, changes);

      // No overlaps remain
      final issues = validator.validate(timeline);
      final remainingOverlaps = issues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(remainingOverlaps, isEmpty,
          reason: 'No overlaps after resolving two neighbors with trim');
    });

    test('resolveAllOverlaps with makeCoFronting handles a single neighbor', () {
      // Alice 10–13, Bob 12–14 (single partial overlap)
      // resolveAllOverlaps with makeCoFronting produces no overlaps.
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(13), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      var timeline = [alice, bob];

      final changes = service.resolveAllOverlaps(
        edited: alice,
        overlaps: [bob],
        resolution: OverlapResolution.makeCoFronting,
      );

      expect(changes, isNotEmpty);

      timeline = applyChanges(timeline, changes);

      // No overlaps remain
      final issues = validator.validate(timeline);
      final remainingOverlaps = issues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(remainingOverlaps, isEmpty,
          reason: 'No overlaps after co-fronting resolution of one neighbor');

      // Timeline should have at least 2 segments (pre-overlap + co-front, or co-front + post)
      expect(timeline.length, greaterThanOrEqualTo(2));
    });

    test('resolveAllOverlaps with cancel returns empty changes', () {
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(15), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(13), end: h(14), memberId: 'bob');

      final changes = service.resolveAllOverlaps(
        edited: alice,
        overlaps: [bob],
        resolution: OverlapResolution.cancel,
      );

      expect(changes, isEmpty);
    });
  });
}
