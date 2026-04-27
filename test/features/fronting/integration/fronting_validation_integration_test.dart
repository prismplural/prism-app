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
  bool isDeleted = false,
}) {
  return FrontingSessionSnapshot(
    id: id,
    memberId: memberId,
    start: start,
    end: end,
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

  // ===========================================================================
  // FrontingSessionValidator — orchestration tests
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

    test('returns empty list for non-overlapping sequential sessions (different members)', () {
      // In per-member model, different-member overlaps are valid and different-member
      // non-overlapping sessions are certainly valid.
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
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

    test('cross-member overlapping sessions produce no issues', () {
      // Different members fronting simultaneously is valid in per-member model.
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: false,
        ),
      );
      final sessions = [
        makeSnapshot(id: 'a', memberId: 'alice', start: h(10), end: h(12)),
        makeSnapshot(id: 'b', memberId: 'bob', start: h(11), end: h(13)),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues, isEmpty, reason: 'Cross-member overlaps are valid');
    });
  });

  // ---------------------------------------------------------------------------
  // Orchestration — all rules fire by default
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — orchestration', () {
    test('detects invalidRange issues', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
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

    test('same-member self-overlap is detected', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );
      final sessions = [
        makeSnapshot(id: 'a', memberId: 'alice', start: h(10), end: h(12)),
        makeSnapshot(id: 'b', memberId: 'alice', start: h(11), end: h(13)),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues.any((i) => i.type == FrontingIssueType.selfOverlap), isTrue);
    });

    test('cross-member overlap is NOT detected as an issue', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        makeSnapshot(id: 'a', memberId: 'alice', start: h(10), end: h(12)),
        makeSnapshot(id: 'b', memberId: 'bob', start: h(11), end: h(13)),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues, isEmpty, reason: 'Cross-member overlap is valid in per-member model');
    });

    test('detects duplicate issues by default', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
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

    test('gaps between sessions are NOT reported (per-member model: gaps are valid)', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // 1-hour gap between two different-member sessions — valid, no issue
      final sessions = [
        makeSnapshot(id: 'a', memberId: 'alice', start: h(10), end: h(11)),
        makeSnapshot(id: 'b', memberId: 'bob', start: h(12), end: h(13)),
      ];
      final now = h(14);
      final issues = v.validate(sessions, now: now);
      expect(issues, isEmpty, reason: 'Gaps are valid in per-member model');
    });

    test('detects futureSession issues by default', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
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
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );
      // invalid range + same-member self-overlap
      final sessions = [
        makeSnapshot(id: 'bad', start: h(10), end: h(10)), // invalid range
        makeSnapshot(id: 'a', memberId: 'alice', start: h(11), end: h(13)),
        makeSnapshot(id: 'b', memberId: 'alice', start: h(12), end: h(14)), // self-overlap
      ];
      final issues = v.validate(sessions, now: h(15));
      final types = issues.map((i) => i.type).toSet();
      expect(types, containsAll([FrontingIssueType.invalidRange, FrontingIssueType.selfOverlap]));
    });
  });

  // ---------------------------------------------------------------------------
  // Config toggles
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — config toggles', () {
    test('detectSelfOverlaps: false suppresses self-overlap detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: false,
        ),
      );
      final sessions = [
        makeSnapshot(id: 'a', memberId: 'alice', start: h(10), end: h(12)),
        makeSnapshot(id: 'b', memberId: 'alice', start: h(11), end: h(13)),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues.any((i) => i.type == FrontingIssueType.selfOverlap), isFalse);
    });

    test('detectDuplicates: false suppresses duplicate detection', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
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
      expect(config.detectDuplicates, isTrue);
      expect(config.detectMergeableAdjacent, isTrue);
      expect(config.detectFutureSessions, isTrue);
      expect(config.detectSelfOverlaps, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------------

  group('FrontingSessionValidator — sorting', () {
    test('issues are sorted by rangeStart ascending', () {
      const v = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );
      // Two same-member self-overlapping pairs at different times
      final sessions = [
        // Later pair (alice overlaps around h(13))
        makeSnapshot(id: 'c', memberId: 'alice', start: h(13), end: h(15)),
        makeSnapshot(id: 'd', memberId: 'alice', start: h(14), end: h(16)),
        // Earlier pair (bob overlaps around h(10))
        makeSnapshot(id: 'a', memberId: 'bob', start: h(10), end: h(12)),
        makeSnapshot(id: 'b', memberId: 'bob', start: h(11), end: h(13)),
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
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );
      // Two sessions for same member that would self-overlap, but one is deleted
      final sessions = [
        makeSnapshot(id: 'a', memberId: 'alice', start: h(10), end: h(12)),
        makeSnapshot(id: 'b', memberId: 'alice', start: h(11), end: h(13), isDeleted: true),
      ];
      final issues = v.validate(sessions, now: h(14));
      expect(issues.any((i) => i.type == FrontingIssueType.selfOverlap), isFalse);
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
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Edit creates same-member self-overlap -> resolve as trim -> timeline is clean
  // ---------------------------------------------------------------------------

  group('edit creates self-overlap -> resolve as trim -> timeline is clean', () {
    test('same-member sessions: trim resolves self-overlap', () {
      // Alice already has 10:00-12:00. Create a second alice session 11:00-13:00
      // that overlaps (self-overlap). Resolve with trim.
      final alice1 = makeSnapshot(id: 'alice1', start: h(10), end: h(12), memberId: 'alice');
      final alice2 = makeSnapshot(id: 'alice2', start: h(11), end: h(13), memberId: 'alice');
      var timeline = [alice1, alice2];

      // Edit alice1 to extend to 13:00 (makes the overlap even larger, just to
      // demonstrate the resolution pipeline).
      final editedAlice = makeSnapshot(id: 'alice1', start: h(10), end: h(13), memberId: 'alice');

      // Detect self-overlap via the edit guard
      final validation = guard.validateEdit(
        original: alice1,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      // alice1 and alice2 are the same member → self-overlap surfaced
      expect(validation.canSaveDirectly, isFalse);
      expect(validation.overlappingSessions, hasLength(1));
      expect(validation.overlappingSessions.first.id, 'alice2');

      // Resolve as trim
      final changes = service.resolveAllOverlaps(
        edited: editedAlice,
        overlaps: validation.overlappingSessions,
        resolution: OverlapResolution.trim,
      );

      expect(changes, isNotEmpty);

      // Apply the extended alice1 then the trim changes
      timeline = applyChanges(timeline, [
        UpdateSessionChange(
          sessionId: 'alice1',
          patch: FrontingSessionPatch(end: h(13)),
        ),
      ]);
      timeline = applyChanges(timeline, changes);

      // Verify: self-overlaps resolved
      const selfOverlapValidator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );
      final issues = selfOverlapValidator.validate(timeline);
      final selfOverlaps = issues.where((i) => i.type == FrontingIssueType.selfOverlap).toList();
      expect(selfOverlaps, isEmpty, reason: 'No self-overlaps expected after trim resolution');
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-member overlap → NOT flagged, canSaveDirectly: true
  // ---------------------------------------------------------------------------

  group('cross-member overlap → valid, guard allows save', () {
    test('edit guard allows cross-member overlapping edit directly', () {
      // Alice 10-12, Bob 12-14; extend Alice to 13 → overlaps Bob by 1 hour.
      // In per-member model, this is VALID — guard must allow it.
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      final timeline = [alice, bob];

      final result = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      // Cross-member overlap is valid — save directly
      expect(result.canSaveDirectly, isTrue);
      expect(result.overlappingSessions, isEmpty);
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

        // Final check: no self-overlaps in the resulting timeline
        const selfOverlapValidator = FrontingSessionValidator(
          config: FrontingValidationConfig(
            detectDuplicates: false,
            detectMergeableAdjacent: false,
            detectFutureSessions: false,
            detectSelfOverlaps: true,
          ),
        );
        final issues = selfOverlapValidator.validate(result);
        final selfOverlaps = issues.where((i) => i.type == FrontingIssueType.selfOverlap).toList();
        expect(selfOverlaps, isEmpty,
            reason: 'No self-overlaps after delete with $strategy');
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Sanitization scan -> fix -> rescan is clean
  // ---------------------------------------------------------------------------

  group('sanitization: scan finds self-overlap issue, fix resolves it, rescan is clean', () {
    test('self-overlap issue detected, first fix plan applied, rescan shows no self-overlaps', () {
      // Create timeline with known self-overlap: Alice 10-13, Alice 12-14
      final alice1 = makeSnapshot(id: 'alice1', start: h(10), end: h(13), memberId: 'alice');
      final alice2 = makeSnapshot(id: 'alice2', start: h(12), end: h(14), memberId: 'alice');
      var timeline = [alice1, alice2];

      const selfOverlapValidator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );

      // Scan via validator
      final scanIssues = selfOverlapValidator.validate(timeline);
      final selfOverlapIssues = scanIssues.where((i) => i.type == FrontingIssueType.selfOverlap).toList();
      expect(selfOverlapIssues, isNotEmpty, reason: 'Should detect the self-overlap');

      // Generate fix plan via planner (use first available plan)
      final issue = selfOverlapIssues.first;
      final plans = planner.plansForIssue(issue, timeline);
      expect(plans, isNotEmpty, reason: 'Planner should offer at least one fix');

      final chosenPlan = plans.first;
      expect(chosenPlan.changes, isNotEmpty);

      // Apply fix
      timeline = applyChanges(timeline, chosenPlan.changes);

      // Rescan -- no self-overlap issues
      final rescanIssues = selfOverlapValidator.validate(timeline);
      final remainingSelfOverlaps = rescanIssues.where((i) => i.type == FrontingIssueType.selfOverlap).toList();
      expect(remainingSelfOverlaps, isEmpty,
          reason: 'No self-overlaps should remain after applying fix plan');
    });
  });

  // ---------------------------------------------------------------------------
  // Edit guard integration (pipeline-level tests)
  // ---------------------------------------------------------------------------

  group('edit guard integration', () {
    test('edit guard blocks same-member self-overlapping edit', () {
      final alice1 = makeSnapshot(id: 'alice1', start: h(10), end: h(12), memberId: 'alice');
      final alice2 = makeSnapshot(id: 'alice2', start: h(12), end: h(14), memberId: 'alice');
      final timeline = [alice1, alice2];

      // Extend alice1 into alice2's range — same-member self-overlap
      final result = guard.validateEdit(
        original: alice1,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(result.canSaveDirectly, isFalse);
      expect(result.overlappingSessions, isNotEmpty);
      expect(result.overlappingSessions.map((s) => s.id), contains('alice2'));
    });

    test('edit guard allows cross-member overlap — no block', () {
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(12), memberId: 'alice');
      final bob = makeSnapshot(id: 'bob', start: h(12), end: h(14), memberId: 'bob');
      final timeline = [alice, bob];

      // Extend alice into bob's range — cross-member overlap is valid
      final result = guard.validateEdit(
        original: alice,
        patch: FrontingSessionPatch(end: h(13)),
        nearbySessions: timeline,
        timingMode: FrontingTimingMode.strict,
      );

      expect(result.canSaveDirectly, isTrue);
      expect(result.overlappingSessions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Multiple overlaps resolved in sequence
  // ---------------------------------------------------------------------------

  group('multiple same-member overlaps resolved with boundary tracking', () {
    test('resolveAllOverlaps with trim handles two same-member neighbors', () {
      // Alice 10-15 (extended), alice2 13-14, alice3 14-16
      // alice overlaps both alice2 and alice3 (all same member)
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(15), memberId: 'alice');
      final alice2 = makeSnapshot(id: 'alice2', start: h(13), end: h(14), memberId: 'alice');
      final alice3 = makeSnapshot(id: 'alice3', start: h(14), end: h(16), memberId: 'alice');
      var timeline = [alice, alice2, alice3];

      final overlaps = [alice2, alice3];

      final changes = service.resolveAllOverlaps(
        edited: alice,
        overlaps: overlaps,
        resolution: OverlapResolution.trim,
      );

      expect(changes, isNotEmpty);

      timeline = applyChanges(timeline, changes);

      // No self-overlaps remain
      const selfOverlapValidator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          detectSelfOverlaps: true,
        ),
      );
      final issues = selfOverlapValidator.validate(timeline);
      final remainingSelfOverlaps = issues.where((i) => i.type == FrontingIssueType.selfOverlap).toList();
      expect(remainingSelfOverlaps, isEmpty,
          reason: 'No self-overlaps after resolving two neighbors with trim');
    });

    test('resolveAllOverlaps with cancel returns empty changes', () {
      final alice = makeSnapshot(id: 'alice', start: h(10), end: h(15), memberId: 'alice');
      final alice2 = makeSnapshot(id: 'alice2', start: h(13), end: h(14), memberId: 'alice');

      final changes = service.resolveAllOverlaps(
        edited: alice,
        overlaps: [alice2],
        resolution: OverlapResolution.cancel,
      );

      expect(changes, isEmpty);
    });
  });
}
