import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_rules.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Base "now" used throughout tests so relative offsets are readable.
final _base = DateTime(2026, 1, 15, 12, 0, 0);

DateTime t(int offsetMinutes) =>
    _base.add(Duration(minutes: offsetMinutes));

FrontingSessionSnapshot session({
  required String id,
  String? memberId,
  required DateTime start,
  DateTime? end,
  List<String> coFronterIds = const [],
  bool isDeleted = false,
}) =>
    FrontingSessionSnapshot(
      id: id,
      memberId: memberId,
      start: start,
      coFronterIds: coFronterIds,
      end: end,
      isDeleted: isDeleted,
    );

// ---------------------------------------------------------------------------
// detectInvalidRanges
// ---------------------------------------------------------------------------

void main() {
  group('detectInvalidRanges', () {
    test('end before start → error issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(10), end: t(5)),
      ];
      final issues = detectInvalidRanges(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.invalidRange);
      expect(issues.first.severity, FrontingIssueSeverity.error);
      expect(issues.first.sessionIds, contains('a'));
    });

    test('end equals start → error issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(10), end: t(10)),
      ];
      final issues = detectInvalidRanges(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.invalidRange);
    });

    test('valid closed session → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
      ];
      final issues = detectInvalidRanges(sessions);
      expect(issues, isEmpty);
    });

    test('active session (end == null) → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
      ];
      final issues = detectInvalidRanges(sessions);
      expect(issues, isEmpty);
    });

    test('deleted sessions are ignored', () {
      final sessions = [
        session(
            id: 'a', memberId: 'm1', start: t(10), end: t(5), isDeleted: true),
      ];
      final issues = detectInvalidRanges(sessions);
      expect(issues, isEmpty);
    });

    test('multiple invalid sessions → one issue per bad session', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(10), end: t(5)),
        session(id: 'b', memberId: 'm2', start: t(20), end: t(20)),
        session(id: 'c', memberId: 'm1', start: t(0), end: t(30)),
      ];
      final issues = detectInvalidRanges(sessions);
      expect(issues, hasLength(2));
      final ids = issues.map((i) => i.sessionIds.first).toSet();
      expect(ids, containsAll(['a', 'b']));
    });
  });

  // -------------------------------------------------------------------------
  // detectOverlaps
  // -------------------------------------------------------------------------

  group('detectOverlaps', () {
    test('partial overlap → issue', () {
      // A: 0–20, B: 10–30 → overlap 10–20
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(20)),
        session(id: 'b', memberId: 'm2', start: t(10), end: t(30)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.overlap);
      expect(issues.first.severity, FrontingIssueSeverity.error);
      expect(issues.first.sessionIds, containsAll(['a', 'b']));
    });

    test('full containment → issue', () {
      // A: 0–60, B: 10–30 — B is inside A
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(60)),
        session(id: 'b', memberId: 'm2', start: t(10), end: t(30)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.sessionIds, containsAll(['a', 'b']));
    });

    test('touching boundaries (A ends at 11:00, B starts at 11:00) → NO issue',
        () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(60)),
        session(id: 'b', memberId: 'm2', start: t(60), end: t(120)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, isEmpty);
    });

    test('two active sessions (end == null) → issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
        session(id: 'b', memberId: 'm2', start: t(10)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.sessionIds, containsAll(['a', 'b']));
    });

    test('non-overlapping sessions → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm2', start: t(60), end: t(90)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, isEmpty);
    });

    test('deleted sessions are ignored', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: t(0),
            end: t(20),
            isDeleted: true),
        session(id: 'b', memberId: 'm2', start: t(10), end: t(30)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, isEmpty);
    });

    test('single session → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
      ];
      final issues = detectOverlaps(sessions);
      expect(issues, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // detectDuplicates
  // -------------------------------------------------------------------------

  group('detectDuplicates', () {
    const config = FrontingValidationConfig(
      duplicateTolerance: Duration(seconds: 60),
    );

    test('same member, start within 60s, end within 60s → issue', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: t(0),
            end: t(60)),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 30)),
            end: t(60).add(const Duration(seconds: 30))),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.duplicate);
      expect(issues.first.severity, FrontingIssueSeverity.warning);
      expect(issues.first.sessionIds, containsAll(['a', 'b']));
    });

    test('same member, both active, start within 60s → issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 30))),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.duplicate);
    });

    test('different members, same times → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(60)),
        session(id: 'b', memberId: 'm2', start: t(0), end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member, start > 60s apart → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(60)),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 90)),
            end: t(60).add(const Duration(seconds: 90))),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member, same start, one active one closed → no duplicate', () {
      // One has an end (closed), one is active — ends differ (null vs non-null)
      // The null-vs-non-null should NOT be within tolerance unless they match.
      // Two active → duplicate was already tested. One active one closed with
      // matching start: ends are null vs defined, so NOT a duplicate by spec.
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
        session(id: 'b', memberId: 'm1', start: t(0), end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
      // One is active (end=null), one is closed — not duplicates
      expect(issues, isEmpty);
    });

    test('null memberId sessions are not compared', () {
      final sessions = [
        session(id: 'a', memberId: null, start: t(0), end: t(60)),
        session(id: 'b', memberId: null, start: t(0), end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, isEmpty);
    });

    test('deleted sessions are ignored', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: t(0),
            end: t(60),
            isDeleted: true),
        session(id: 'b', memberId: 'm1', start: t(0), end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member but different co-fronters are NOT duplicates', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            coFronterIds: ['m2'],
            start: t(0),
            end: t(60)),
        session(id: 'b', memberId: 'm1', start: t(0), end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member and same co-fronters ARE duplicates', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            coFronterIds: ['m2'],
            start: t(0),
            end: t(60)),
        session(
            id: 'b',
            memberId: 'm1',
            coFronterIds: ['m2'],
            start: t(0),
            end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
      expect(issues, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // detectMergeableAdjacent
  // -------------------------------------------------------------------------

  group('detectMergeableAdjacent', () {
    const config = FrontingValidationConfig(
      timingMode: FrontingTimingMode.flexible, // mergeableGapThreshold = 60s
    );

    test('same member, gap ≤ 60s → issue', () {
      // A ends at t(0), B starts at t(0)+30s → gap = 30s ≤ 60s
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(-60), end: t(0)),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 30)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.mergeableAdjacent);
      expect(issues.first.severity, FrontingIssueSeverity.info);
      expect(issues.first.sessionIds, containsAll(['a', 'b']));
    });

    test('same member, gap > 60s → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(-120), end: t(0)),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 90)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, isEmpty);
    });

    test('different members, small gap → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(-60), end: t(0)),
        session(
            id: 'b',
            memberId: 'm2',
            start: t(0).add(const Duration(seconds: 10)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member touching (gap = 0) → issue (gap ≤ 60s)', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(-60), end: t(0)),
        session(id: 'b', memberId: 'm1', start: t(0), end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, hasLength(1));
    });

    test('deleted sessions are ignored', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: t(-60),
            end: t(0),
            isDeleted: true),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 10)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, isEmpty);
    });

    test('null memberId sessions are not compared', () {
      final sessions = [
        session(id: 'a', memberId: null, start: t(-60), end: t(0)),
        session(
            id: 'b',
            memberId: null,
            start: t(0).add(const Duration(seconds: 10)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member but different co-fronters are NOT mergeable', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            coFronterIds: ['m2'],
            start: t(-60),
            end: t(0)),
        session(
            id: 'b',
            memberId: 'm1',
            start: t(0).add(const Duration(seconds: 10)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, isEmpty);
    });

    test('same member and same co-fronters ARE mergeable', () {
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            coFronterIds: ['m2'],
            start: t(-60),
            end: t(0)),
        session(
            id: 'b',
            memberId: 'm1',
            coFronterIds: ['m2'],
            start: t(0).add(const Duration(seconds: 10)),
            end: t(60)),
      ];
      final issues = detectMergeableAdjacent(sessions, config);
      expect(issues, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // detectGaps
  // -------------------------------------------------------------------------

  group('detectGaps', () {
    test('gap > 5min (flexible) → issue', () {
      const config =
          FrontingValidationConfig(timingMode: FrontingTimingMode.flexible);
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm2', start: t(40), end: t(70)),
      ];
      // Gap = 10 min > 5 min threshold
      final issues = detectGaps(sessions, config);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.gap);
      expect(issues.first.severity, FrontingIssueSeverity.warning);
    });

    test('gap ≤ 5min (flexible) → no issue', () {
      const config =
          FrontingValidationConfig(timingMode: FrontingTimingMode.flexible);
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm2', start: t(33), end: t(60)),
      ];
      // Gap = 3 min ≤ 5 min threshold
      final issues = detectGaps(sessions, config);
      expect(issues, isEmpty);
    });

    test('gap > 0 (strict) → issue', () {
      const config =
          FrontingValidationConfig(timingMode: FrontingTimingMode.strict);
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm2', start: t(31), end: t(60)),
      ];
      // Gap = 1 min > 0 (zero tolerance)
      final issues = detectGaps(sessions, config);
      expect(issues, hasLength(1));
    });

    test('touching sessions (strict) → no issue', () {
      const config =
          FrontingValidationConfig(timingMode: FrontingTimingMode.strict);
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm2', start: t(30), end: t(60)),
      ];
      final issues = detectGaps(sessions, config);
      expect(issues, isEmpty);
    });

    test('active session does not create gap with next (only closed end used)',
        () {
      const config =
          FrontingValidationConfig(timingMode: FrontingTimingMode.flexible);
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)), // active
        session(id: 'b', memberId: 'm2', start: t(60), end: t(90)),
      ];
      final issues = detectGaps(sessions, config);
      // Active session has no end, so no gap can be measured from it
      expect(issues, isEmpty);
    });

    test('deleted sessions are ignored', () {
      const config =
          FrontingValidationConfig(timingMode: FrontingTimingMode.flexible);
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: t(0),
            end: t(30),
            isDeleted: true),
        session(id: 'b', memberId: 'm2', start: t(60), end: t(90)),
      ];
      final issues = detectGaps(sessions, config);
      expect(issues, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // detectFutureSessions
  // -------------------------------------------------------------------------

  group('detectFutureSessions', () {
    const config = FrontingValidationConfig(futureTolerance: Duration.zero);

    test('start in future → error issue', () {
      final now = _base;
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now.add(const Duration(minutes: 10)),
            end: now.add(const Duration(minutes: 30))),
      ];
      final issues = detectFutureSessions(sessions, now, config);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.futureSession);
      expect(issues.first.severity, FrontingIssueSeverity.error);
      expect(issues.first.sessionIds, contains('a'));
    });

    test('end in future, start in past → warning issue', () {
      final now = _base;
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now.subtract(const Duration(minutes: 30)),
            end: now.add(const Duration(minutes: 10))),
      ];
      final issues = detectFutureSessions(sessions, now, config);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.futureSession);
      expect(issues.first.severity, FrontingIssueSeverity.warning);
    });

    test('all in past → no issue', () {
      final now = _base;
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now.subtract(const Duration(hours: 2)),
            end: now.subtract(const Duration(hours: 1))),
      ];
      final issues = detectFutureSessions(sessions, now, config);
      expect(issues, isEmpty);
    });

    test('active session (no end) in past → no issue', () {
      final now = _base;
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now.subtract(const Duration(minutes: 10))),
      ];
      final issues = detectFutureSessions(sessions, now, config);
      expect(issues, isEmpty);
    });

    test('start exactly at now (futureTolerance = 0) → no issue', () {
      final now = _base;
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now,
            end: now.add(const Duration(minutes: 30))),
      ];
      final issues = detectFutureSessions(sessions, now, config);
      expect(issues, isEmpty);
    });

    test('within futureTolerance → no issue', () {
      final now = _base;
      const toleranceConfig = FrontingValidationConfig(
        futureTolerance: Duration(minutes: 5),
      );
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now.add(const Duration(minutes: 3)),
            end: now.add(const Duration(minutes: 30))),
      ];
      final issues = detectFutureSessions(sessions, now, toleranceConfig);
      expect(issues, isEmpty);
    });

    test('deleted sessions are ignored', () {
      final now = _base;
      final sessions = [
        session(
            id: 'a',
            memberId: 'm1',
            start: now.add(const Duration(minutes: 10)),
            end: now.add(const Duration(minutes: 30)),
            isDeleted: true),
      ];
      final issues = detectFutureSessions(sessions, now, config);
      expect(issues, isEmpty);
    });
  });
}
