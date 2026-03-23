import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

void main() {
  group('FrontingTimingMode', () {
    test('flexible mode has 5-minute gap threshold', () {
      expect(
        FrontingTimingMode.flexible.gapThreshold,
        const Duration(minutes: 5),
      );
    });

    test('strict mode has zero gap threshold', () {
      expect(
        FrontingTimingMode.strict.gapThreshold,
        Duration.zero,
      );
    });

    test('flexible mode has 60-second adjacent merge threshold', () {
      expect(
        FrontingTimingMode.flexible.adjacentMergeThreshold,
        const Duration(seconds: 60),
      );
    });

    test('strict mode has 60-second adjacent merge threshold', () {
      expect(
        FrontingTimingMode.strict.adjacentMergeThreshold,
        const Duration(seconds: 60),
      );
    });
  });

  group('FrontingValidationConfig', () {
    test('default values are correct', () {
      const config = FrontingValidationConfig();

      expect(config.timingMode, FrontingTimingMode.flexible);
      expect(config.duplicateTolerance, const Duration(seconds: 60));
      expect(config.futureTolerance, Duration.zero);
      expect(config.detectGaps, isTrue);
      expect(config.detectDuplicates, isTrue);
      expect(config.detectMergeableAdjacent, isTrue);
      expect(config.detectFutureSessions, isTrue);
    });

    test('reportableGapThreshold delegates to timingMode', () {
      const flexibleConfig = FrontingValidationConfig(
        timingMode: FrontingTimingMode.flexible,
      );
      const strictConfig = FrontingValidationConfig(
        timingMode: FrontingTimingMode.strict,
      );

      expect(flexibleConfig.reportableGapThreshold, const Duration(minutes: 5));
      expect(strictConfig.reportableGapThreshold, Duration.zero);
    });

    test('mergeableGapThreshold is always 60 seconds', () {
      const flexibleConfig = FrontingValidationConfig(
        timingMode: FrontingTimingMode.flexible,
      );
      const strictConfig = FrontingValidationConfig(
        timingMode: FrontingTimingMode.strict,
      );

      expect(flexibleConfig.mergeableGapThreshold, const Duration(seconds: 60));
      expect(strictConfig.mergeableGapThreshold, const Duration(seconds: 60));
    });

    test('custom config values are applied', () {
      const config = FrontingValidationConfig(
        timingMode: FrontingTimingMode.strict,
        duplicateTolerance: Duration(seconds: 30),
        futureTolerance: Duration(minutes: 1),
        detectGaps: false,
        detectDuplicates: false,
        detectMergeableAdjacent: false,
        detectFutureSessions: false,
      );

      expect(config.timingMode, FrontingTimingMode.strict);
      expect(config.duplicateTolerance, const Duration(seconds: 30));
      expect(config.futureTolerance, const Duration(minutes: 1));
      expect(config.detectGaps, isFalse);
      expect(config.detectDuplicates, isFalse);
      expect(config.detectMergeableAdjacent, isFalse);
      expect(config.detectFutureSessions, isFalse);
    });
  });

  group('FrontingValidationIssue', () {
    final now = DateTime(2026, 3, 15, 12, 0, 0);
    final later = DateTime(2026, 3, 15, 13, 0, 0);

    test('constructs with required fields', () {
      final issue = FrontingValidationIssue(
        id: 'issue-1',
        type: FrontingIssueType.overlap,
        severity: FrontingIssueSeverity.error,
        sessionIds: ['session-a', 'session-b'],
        memberIds: ['member-1'],
        rangeStart: now,
        rangeEnd: later,
        summary: 'Sessions overlap',
      );

      expect(issue.id, 'issue-1');
      expect(issue.type, FrontingIssueType.overlap);
      expect(issue.severity, FrontingIssueSeverity.error);
      expect(issue.sessionIds, ['session-a', 'session-b']);
      expect(issue.memberIds, ['member-1']);
      expect(issue.rangeStart, now);
      expect(issue.rangeEnd, later);
      expect(issue.summary, 'Sessions overlap');
      expect(issue.details, isNull);
    });

    test('constructs with optional details', () {
      final issue = FrontingValidationIssue(
        id: 'issue-2',
        type: FrontingIssueType.gap,
        severity: FrontingIssueSeverity.info,
        sessionIds: ['session-c'],
        memberIds: [],
        rangeStart: now,
        rangeEnd: later,
        summary: 'Gap detected',
        details: 'A 30-minute gap was found between sessions.',
      );

      expect(issue.details, 'A 30-minute gap was found between sessions.');
    });

    test('all FrontingIssueType values exist', () {
      expect(FrontingIssueType.values, containsAll([
        FrontingIssueType.overlap,
        FrontingIssueType.gap,
        FrontingIssueType.duplicate,
        FrontingIssueType.mergeableAdjacent,
        FrontingIssueType.invalidRange,
        FrontingIssueType.futureSession,
      ]));
    });

    test('all FrontingIssueSeverity values exist', () {
      expect(FrontingIssueSeverity.values, containsAll([
        FrontingIssueSeverity.info,
        FrontingIssueSeverity.warning,
        FrontingIssueSeverity.error,
      ]));
    });
  });

  group('FrontingSessionSnapshot', () {
    final now = DateTime(2026, 3, 15, 10, 0, 0);
    final end = DateTime(2026, 3, 15, 11, 0, 0);

    test('constructs with required fields and defaults', () {
      final snapshot = FrontingSessionSnapshot(
        id: 'snap-1',
        memberId: 'member-1',
        start: now,
      );

      expect(snapshot.id, 'snap-1');
      expect(snapshot.memberId, 'member-1');
      expect(snapshot.start, now);
      expect(snapshot.end, isNull);
      expect(snapshot.coFronterIds, isEmpty);
      expect(snapshot.notes, isNull);
      expect(snapshot.confidenceIndex, isNull);
      expect(snapshot.isDeleted, isFalse);
    });

    test('constructs active session (null end)', () {
      final snapshot = FrontingSessionSnapshot(
        id: 'snap-active',
        memberId: 'member-2',
        start: now,
      );

      expect(snapshot.end, isNull);
    });

    test('constructs completed session with end time', () {
      final snapshot = FrontingSessionSnapshot(
        id: 'snap-2',
        memberId: 'member-1',
        start: now,
        end: end,
        coFronterIds: ['member-2', 'member-3'],
        notes: 'Test notes',
        confidenceIndex: 3,
        isDeleted: false,
      );

      expect(snapshot.end, end);
      expect(snapshot.coFronterIds, ['member-2', 'member-3']);
      expect(snapshot.notes, 'Test notes');
      expect(snapshot.confidenceIndex, 3);
    });

    test('constructs with null memberId (unknown fronter)', () {
      final snapshot = FrontingSessionSnapshot(
        id: 'snap-unknown',
        memberId: null,
        start: now,
        end: end,
      );

      expect(snapshot.memberId, isNull);
    });

    test('constructs deleted session', () {
      final snapshot = FrontingSessionSnapshot(
        id: 'snap-deleted',
        memberId: 'member-1',
        start: now,
        isDeleted: true,
      );

      expect(snapshot.isDeleted, isTrue);
    });
  });
}
