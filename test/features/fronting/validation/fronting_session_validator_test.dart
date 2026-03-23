import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_session_validator.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  FrontingSessionSnapshot session({
    required String id,
    required DateTime start,
    DateTime? end,
    String? memberId,
    bool isDeleted = false,
  }) =>
      FrontingSessionSnapshot(
        id: id,
        memberId: memberId ?? 'member-$id',
        start: start,
        end: end,
        isDeleted: isDeleted,
      );

  final t0 = DateTime(2025, 1, 1, 10, 0, 0);

  // ---------------------------------------------------------------------------
  // Clean timeline
  // ---------------------------------------------------------------------------

  group('clean timeline', () {
    test('returns empty list when there are no sessions', () {
      const validator = FrontingSessionValidator();
      final issues = validator.validate([]);
      expect(issues, isEmpty);
    });

    test('returns empty list for a single valid completed session', () {
      const validator = FrontingSessionValidator();
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 2)));
      expect(issues, isEmpty);
    });

    test('returns empty list for non-overlapping sequential sessions', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectMergeableAdjacent: false,
        ),
      );
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 2)),
          end: t0.add(const Duration(hours: 3)),
        ),
      ];
      final now = t0.add(const Duration(hours: 4));
      final issues = validator.validate(sessions, now: now);
      expect(issues, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Orchestration — all rules fire by default
  // ---------------------------------------------------------------------------

  group('orchestration', () {
    test('detects invalidRange issues', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // end == start → invalid
      final sessions = [
        session(id: 'a', start: t0, end: t0),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 1)));
      expect(issues.length, 1);
      expect(issues.first.type, FrontingIssueType.invalidRange);
    });

    test('detects overlap issues', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 2)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 1)),
          end: t0.add(const Duration(hours: 3)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 4)));
      expect(issues.any((i) => i.type == FrontingIssueType.overlap), isTrue);
    });

    test('detects duplicate issues by default', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'alice',
          start: t0.add(const Duration(seconds: 10)),
          end: t0.add(const Duration(hours: 1, seconds: 10)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 2)));
      expect(issues.any((i) => i.type == FrontingIssueType.duplicate), isTrue);
    });

    test('detects mergeableAdjacent issues by default', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectFutureSessions: false,
        ),
      );
      // Gap of 30 seconds — within the 60s merge threshold
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'alice',
          start: t0.add(const Duration(hours: 1, seconds: 30)),
          end: t0.add(const Duration(hours: 2)),
        ),
      ];
      final now = t0.add(const Duration(hours: 3));
      final issues = validator.validate(sessions, now: now);
      expect(issues.any((i) => i.type == FrontingIssueType.mergeableAdjacent), isTrue);
    });

    test('detects gap issues by default', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          timingMode: FrontingTimingMode.strict,
        ),
      );
      // 1-hour gap in strict mode (threshold = 0) → gap reported
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 2)),
          end: t0.add(const Duration(hours: 3)),
        ),
      ];
      final now = t0.add(const Duration(hours: 4));
      final issues = validator.validate(sessions, now: now);
      expect(issues.any((i) => i.type == FrontingIssueType.gap), isTrue);
    });

    test('detects futureSession issues by default', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
        ),
      );
      final futureStart = t0.add(const Duration(hours: 5));
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: futureStart,
          end: futureStart.add(const Duration(hours: 1)),
        ),
      ];
      // now is before the session start
      final issues = validator.validate(sessions, now: t0);
      expect(issues.any((i) => i.type == FrontingIssueType.futureSession), isTrue);
    });

    test('combines issues from multiple rules in one call', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // invalid range + overlap
      final sessions = [
        session(id: 'bad', start: t0, end: t0), // invalid range
        session(
          id: 'a',
          memberId: 'alice',
          start: t0.add(const Duration(hours: 1)),
          end: t0.add(const Duration(hours: 3)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 2)),
          end: t0.add(const Duration(hours: 4)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 5)));
      final types = issues.map((i) => i.type).toSet();
      expect(types, containsAll([FrontingIssueType.invalidRange, FrontingIssueType.overlap]));
    });
  });

  // ---------------------------------------------------------------------------
  // Config toggles
  // ---------------------------------------------------------------------------

  group('config toggles', () {
    test('detectGaps: false suppresses gap detection', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
          timingMode: FrontingTimingMode.strict,
        ),
      );
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 2)),
          end: t0.add(const Duration(hours: 3)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 4)));
      expect(issues.any((i) => i.type == FrontingIssueType.gap), isFalse);
    });

    test('detectDuplicates: false suppresses duplicate detection', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'alice',
          start: t0.add(const Duration(seconds: 10)),
          end: t0.add(const Duration(hours: 1, seconds: 10)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 2)));
      expect(issues.any((i) => i.type == FrontingIssueType.duplicate), isFalse);
    });

    test('detectMergeableAdjacent: false suppresses mergeableAdjacent detection', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
        ),
        session(
          id: 'b',
          memberId: 'alice',
          start: t0.add(const Duration(hours: 1, seconds: 30)),
          end: t0.add(const Duration(hours: 2)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 3)));
      expect(issues.any((i) => i.type == FrontingIssueType.mergeableAdjacent), isFalse);
    });

    test('detectFutureSessions: false suppresses future session detection', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      final futureStart = t0.add(const Duration(hours: 5));
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: futureStart,
          end: futureStart.add(const Duration(hours: 1)),
        ),
      ];
      final issues = validator.validate(sessions, now: t0);
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

  group('sorting', () {
    test('issues are sorted by rangeStart ascending', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // Two overlapping pairs at different times
      final t1 = t0.add(const Duration(hours: 3));
      final sessions = [
        // Later pair (overlapping around t1)
        session(
          id: 'c',
          memberId: 'charlie',
          start: t1,
          end: t1.add(const Duration(hours: 2)),
        ),
        session(
          id: 'd',
          memberId: 'dan',
          start: t1.add(const Duration(hours: 1)),
          end: t1.add(const Duration(hours: 3)),
        ),
        // Earlier pair (overlapping around t0)
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 2)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 1)),
          end: t0.add(const Duration(hours: 3)),
        ),
      ];
      final issues = validator.validate(sessions, now: t1.add(const Duration(hours: 4)));
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

  group('filtering', () {
    test('deleted sessions are excluded from validation', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
          detectFutureSessions: false,
        ),
      );
      // Two sessions that would overlap, but one is deleted
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: t0,
          end: t0.add(const Duration(hours: 2)),
        ),
        session(
          id: 'b',
          memberId: 'bob',
          start: t0.add(const Duration(hours: 1)),
          end: t0.add(const Duration(hours: 3)),
          isDeleted: true,
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 4)));
      expect(issues.any((i) => i.type == FrontingIssueType.overlap), isFalse);
    });

    test('all-deleted list returns empty', () {
      const validator = FrontingSessionValidator();
      final sessions = [
        session(id: 'a', start: t0, isDeleted: true),
        session(id: 'b', start: t0.add(const Duration(hours: 1)), isDeleted: true),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 3)));
      expect(issues, isEmpty);
    });

    test('invalidRange not flagged for deleted session', () {
      const validator = FrontingSessionValidator(
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
          start: t0,
          end: t0, // invalid
          isDeleted: true,
        ),
      ];
      final issues = validator.validate(sessions, now: t0.add(const Duration(hours: 1)));
      expect(issues, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Custom now parameter
  // ---------------------------------------------------------------------------

  group('custom now parameter', () {
    test('now parameter is forwarded to future session detection', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
        ),
      );
      final sessionStart = t0.add(const Duration(hours: 5));
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: sessionStart,
          end: sessionStart.add(const Duration(hours: 1)),
        ),
      ];

      // When now is before the session → future session issue expected
      final issuesBefore = validator.validate(sessions, now: t0);
      expect(issuesBefore.any((i) => i.type == FrontingIssueType.futureSession), isTrue);

      // When now is after the session → no future session issue
      final issuesAfter = validator.validate(
        sessions,
        now: sessionStart.add(const Duration(hours: 2)),
      );
      expect(issuesAfter.any((i) => i.type == FrontingIssueType.futureSession), isFalse);
    });

    test('different now values produce different future-session results', () {
      const validator = FrontingSessionValidator(
        config: FrontingValidationConfig(
          detectGaps: false,
          detectDuplicates: false,
          detectMergeableAdjacent: false,
        ),
      );
      final sessionStart = t0.add(const Duration(hours: 2));
      final sessions = [
        session(
          id: 'a',
          memberId: 'alice',
          start: sessionStart,
          end: sessionStart.add(const Duration(hours: 1)),
        ),
      ];

      // now = 1h before session start → issue
      final issuesEarly = validator.validate(
        sessions,
        now: sessionStart.subtract(const Duration(hours: 1)),
      );
      expect(issuesEarly.any((i) => i.type == FrontingIssueType.futureSession), isTrue);

      // now = 1h after session end → no issue
      final issuesLate = validator.validate(
        sessions,
        now: sessionStart.add(const Duration(hours: 2)),
      );
      expect(issuesLate.any((i) => i.type == FrontingIssueType.futureSession), isFalse);
    });
  });
}
