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
  bool isDeleted = false,
}) {
  return FrontingSessionSnapshot(
    id: id,
    memberId: memberId,
    start: start,
    end: end,
    coFronterIds: coFronterIds,
    isDeleted: isDeleted,
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

  // ===========================================================================
  // FrontingSessionValidator — orchestration tests
  // (merged from fronting_session_validator_test.dart)
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Clean timeline
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — clean timeline', () {
    test('returns empty list when there are no sessions', () {
      const v = FrontingSessionValidator();
      final issues = v.validate([]);
      expect(issues, isEmpty);
    });

    test('returns empty list for a single valid completed session', () {
      const v = FrontingSessionValidator();
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
      ];
      final issues = v.validate(sessions, now: h(13));
      expect(issues, isEmpty);
    });

    test('returns empty list for non-overlapping sequential sessions', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectMergeableAdjacent: false,
        ),
      );
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(12),
          end: h(13),
        ),
      ];
      final now = h(14);
      final issues = v.validate(sessions, now: now);
      expect(issues, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Orchestration — all rules fire by default
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — orchestration', () {
    test('detects invalidRange issues', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // end == start -> invalid
      final sessions = [
        makeSnapshot(id: 'a', start: h(10), end: h(10)),
      ];
      final issues = v.validate(sessions, now: h(11));
      expect(issues.length, 1);
      expect(issues.first.type, FrontingIssueType.invalidRange);
    });

    test('detects overlap issues', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(12),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(11),
          end: h(13),
        ),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues.any((i) => i.type == FrontingIssueType.overlap), isTrue);
    });

    test('detects duplicate issues by default', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'alice',
          start: h(10).add(const Duration(seconds: 10)),
          end: h(11).add(const Duration(seconds: 10)),
        ),
      ];
      final issues = v.validate(sessions, now: h(12));
      expect(issues.any((i) => i.type == FrontingIssueType.duplicate), isTrue);
    });

    test('detects mergeableAdjacent issues by default', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectFutureSessions: false,
        ),
      );
      // Gap of 30 seconds -- within the 60s merge threshold
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'alice',
          start: h(11).add(const Duration(seconds: 30)),
          end: h(12),
        ),
      ];
      final now = h(13);
      final issues = v.validate(sessions, now: now);
      expect(issues.any((i) => i.type == FrontingIssueType.mergeableAdjacent), isTrue);
    });

    test('detects gap issues by default', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          timingMode: FrontingTimingMode.strict,
        ),
      );
      // 1-hour gap in strict mode (threshold = 0) -> gap reported
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(12),
          end: h(13),
        ),
      ];
      final now = h(14);
      final issues = v.validate(sessions, now: now);
      expect(issues.any((i) => i.type == FrontingIssueType.gap), isTrue);
    });

    test('detects futureSession issues by default', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
        ),
      );
      final futureStart = h(15);
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: futureStart,
          end: futureStart.add(const Duration(hours: 1)),
        ),
      ];
      // now is before the session start
      final issues = v.validate(sessions, now: h(10));
      expect(issues.any((i) => i.type == FrontingIssueType.futureSession), isTrue);
    });

    test('combines issues from multiple rules in one call', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // invalid range + overlap
      final sessions = [
        makeSnapshot(id: 'bad', start: h(10), end: h(10)), // invalid range
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(11),
          end: h(13),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(12),
          end: h(14),
        ),
      ];
      final issues = v.validate(sessions, now: h(15));
      final types = issues.map((i) => i.type).toSet();
      expect(types, containsAll([FrontingIssueType.invalidRange, FrontingIssueType.overlap]));
    });
  });

  // ---------------------------------------------------------------------------
  // Config toggles
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — config toggles', () {
    test('detectGaps: false suppresses gap detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          timingMode: FrontingTimingMode.strict,
        ),
      );
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(12),
          end: h(13),
        ),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues.any((i) => i.type == FrontingIssueType.gap), isFalse);
    });

    test('detectDuplicates: false suppresses duplicate detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'alice',
          start: h(10).add(const Duration(seconds: 10)),
          end: h(11).add(const Duration(seconds: 10)),
        ),
      ];
      final issues = v.validate(sessions, now: h(12));
      expect(issues.any((i) => i.type == FrontingIssueType.duplicate), isFalse);
    });

    test('detectMergeableAdjacent: false suppresses mergeableAdjacent detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(11),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'alice',
          start: h(11).add(const Duration(seconds: 30)),
          end: h(12),
        ),
      ];
      final issues = v.validate(sessions, now: h(13));
      expect(issues.any((i) => i.type == FrontingIssueType.mergeableAdjacent), isFalse);
    });

    test('detectFutureSessions: false suppresses future session detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final futureStart = h(15);
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: futureStart,
          end: futureStart.add(const Duration(hours: 1)),
        ),
      ];
      final issues = v.validate(sessions, now: h(10));
      expect(issues.any((i) => i.type == FrontingIssueType.futureSession), isFalse);
    });

    test('all optional detections enabled by default (default config)', () {
      // Verify that the default config has all detections enabled
      const config = FrontingValidationConfig();
      expect(config.detectGaps, isTrue);
      expect(config.detectDuplicates, isTrue);
      expect(config.detectMergeableAdjacent, isTrue);
      expect(config.detectFutureSessions, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — sorting', () {
    test('issues are sorted by rangeStart ascending', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // Two overlapping pairs at different times
      final sessions = [
        // Later pair (overlapping around h(13))
        makeSnapshot(
          id: 'c',
          memberId: 'charlie',
          start: h(13),
          end: h(15),
        ),
        makeSnapshot(
          id: 'd',
          memberId: 'dan',
          start: h(14),
          end: h(16),
        ),
        // Earlier pair (overlapping around h(10))
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(12),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(11),
          end: h(13),
        ),
      ];
      final issues = v.validate(sessions, now: h(20));
      expect(issues.length, greaterThanOrEqualTo(2));
      for (int i = 0; i < issues.length - 1; i++) {
        expect(
          issues[i].rangeStart.isAfter(issues[i + 1].rangeStart),
          isFalse,
          reason:
              'Issue at index $i (rangeStart=${issues[i].rangeStart}) should not be after issue at index ${i + 1} (rangeStart=${issues[i + 1].rangeStart})',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Filtering — deleted sessions excluded
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — filtering', () {
    test('deleted sessions are excluded from validation', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // Two sessions that would overlap, but one is deleted
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: h(10),
          end: h(12),
        ),
        makeSnapshot(
          id: 'b',
          memberId: 'bob',
          start: h(11),
          end: h(13),
          isDeleted: true,
        ),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues.any((i) => i.type == FrontingIssueType.overlap), isFalse);
    });

    test('all-deleted list returns empty', () {
      const v = FrontingSessionValidator();
      final sessions = [
        makeSnapshot(id: 'a', start: h(10), isDeleted: true),
        makeSnapshot(id: 'b', start: h(11), isDeleted: true),
      ];
      final issues = v.validate(sessions, now: h(13));
      expect(issues, isEmpty);
    });

    test('invalidRange not flagged for deleted session', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // This would be an invalid range but is deleted
      final sessions = [
        FrontingSessionSnapshot(
          id: 'bad',
          memberId: 'alice',
          start: h(10),
          end: h(10), // invalid
          isDeleted: true,
        ),
      ];
      final issues = v.validate(sessions, now: h(11));
      expect(issues, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Custom now parameter
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — custom now parameter', () {
    test('now parameter is forwarded to future session detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
        ),
      );
      final sessionStart = h(15);
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: sessionStart,
          end: sessionStart.add(const Duration(hours: 1)),
        ),
      ];

      // When now is before the session -> future session issue expected
      final issuesBefore = v.validate(sessions, now: h(10));
      expect(issuesBefore.any((i) => i.type == FrontingIssueType.futureSession), isTrue);

      // When now is after the session -> no future session issue
      final issuesAfter = v.validate(
        sessions,
        now: sessionStart.add(const Duration(hours: 2)),
      );
      expect(issuesAfter.any((i) => i.type == FrontingIssueType.futureSession), isFalse);
    });

    test('different now values produce different future-session results', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
        ),
      );
      final sessionStart = h(12);
      final sessions = [
        makeSnapshot(
          id: 'a',
          memberId: 'alice',
          start: sessionStart,
          end: sessionStart.add(const Duration(hours: 1)),
        ),
      ];

      // now = 1h before session start -> issue
      final issuesEarly = v.validate(
        sessions,
        now: sessionStart.subtract(const Duration(hours: 1)),
      );
      expect(issuesEarly.any((i) => i.type == FrontingIssueType.futureSession), isTrue);

      // now = 1h after session end -> no issue
      final issuesLate = v.validate(
        sessions,
        now: sessionStart.add(const Duration(hours: 2)),
      );
      expect(issuesLate.any((i) => i.type == FrontingIssueType.futureSession), isFalse);
    });
  });

  // ===========================================================================
  // End-to-end integration tests
  // (originally in fronting_validation_integration_test.dart)
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Edit creates overlap -> resolve as co-fronting -> timeline is clean
  // ---------------------------------------------------------------------------

  group('edit creates overlap -> resolve as co-fronting -> timeline is clean', () {
    test('three segments with no overlap issues after co-fronting resolution', () {
      // Initial timeline: Alice 10:00-12:00, Bob 12:00-14:00
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
  // Edit creates overlap -> resolve as trim -> timeline is clean
  // ---------------------------------------------------------------------------

  group('edit creates overlap -> resolve as trim -> timeline is clean', () {
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
  // Delete with each of the 5 strategies
  // ---------------------------------------------------------------------------

  group('delete with each strategy produces valid timeline', () {
    // 3-session timeline: Alice 10-11, Bob 11-12, Carol 12-13
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

        // Skip strategies that require a neighbor that doesn't exist --
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
            // Bob deleted, gap remains -- 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);

          case FrontingDeleteStrategy.convertToUnknown:
            // Bob kept but memberId cleared -- still 3 sessions
            expect(result.length, equals(3));
            final unknown = result.firstWhere((s) => s.id == 'bob');
            expect(unknown.memberId, isNull);

          case FrontingDeleteStrategy.extendPrevious:
            // Alice extended to cover Bob's time, Bob deleted -- 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);
            final extAlice = result.firstWhere((s) => s.id == 'alice');
            expect(extAlice.end, equals(h(12)));

          case FrontingDeleteStrategy.extendNext:
            // Carol pulled back to cover Bob's time, Bob deleted -- 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);
            final extCarol = result.firstWhere((s) => s.id == 'carol');
            expect(extCarol.start, equals(h(11)));

          case FrontingDeleteStrategy.splitBetweenNeighbors:
            // Alice and Carol each take half of Bob's hour, Bob deleted -- 2 sessions
            expect(result.length, equals(2));
            expect(result.any((s) => s.id == 'bob'), isFalse);
            final extAlice = result.firstWhere((s) => s.id == 'alice');
            final extCarol = result.firstWhere((s) => s.id == 'carol');
            // Midpoint of 11:00-12:00 = 11:30
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
  // Sanitization scan -> fix -> rescan is clean
  // ---------------------------------------------------------------------------

  group('sanitization: scan finds issues, fix resolves them, rescan is clean', () {
    test('overlap issue detected, first fix plan applied, rescan shows no overlaps', () {
      // Create timeline with known overlap: Alice 10-13, Bob 12-14
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

      // Rescan -- no overlap issues
      final rescanIssues = validator.validate(timeline);
      final remainingOverlaps = rescanIssues.where((i) => i.type == FrontingIssueType.overlap).toList();
      expect(remainingOverlaps, isEmpty,
          reason: 'No overlaps should remain after applying fix plan');
    });
  });

  // ---------------------------------------------------------------------------
  // Edit guard integration (pipeline-level tests)
  // Note: Unit-level edit guard tests are in fronting_edit_guard_test.dart.
  // ---------------------------------------------------------------------------

  group('edit guard integration', () {
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

    // Note: "clean edit" and "touching boundary" tests are covered by
    // fronting_edit_guard_test.dart (validateEdit group). Removed here
    // to avoid duplication.
  });

  // ---------------------------------------------------------------------------
  // Multiple overlaps resolved in sequence
  // ---------------------------------------------------------------------------

  group('multiple overlaps resolved with boundary tracking', () {
    test('resolveAllOverlaps with trim handles two neighbors', () {
      // Alice 10-15 (extended), Bob 13-14, Carol 14-16
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
      // Alice 10-13, Bob 12-14 (single partial overlap)
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
