import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
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
  bool isDeleted = false,
  SessionType sessionType = SessionType.normal,
}) =>
    FrontingSessionSnapshot(
      id: id,
      memberId: memberId,
      start: start,
      end: end,
      isDeleted: isDeleted,
      sessionType: sessionType,
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

    test('different members, same times → no issue (cross-member is valid)', () {
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
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
        session(id: 'b', memberId: 'm1', start: t(0), end: t(60)),
      ];
      final issues = detectDuplicates(sessions, config);
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

    test('same member, same start and end → duplicate', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(60)),
        session(id: 'b', memberId: 'm1', start: t(0), end: t(60)),
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

    test('different members, small gap → no issue (cross-member not mergeable)', () {
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

  // -------------------------------------------------------------------------
  // detectSelfOverlap
  // -------------------------------------------------------------------------

  group('detectSelfOverlap', () {
    test('same member, overlapping closed sessions → warning', () {
      // A: 0–20, B: 10–30 → same member → soft warning
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(20)),
        session(id: 'b', memberId: 'm1', start: t(10), end: t(30)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.selfOverlap);
      expect(issues.first.severity, FrontingIssueSeverity.warning);
      expect(issues.first.sessionIds, containsAll(['a', 'b']));
    });

    test('same member, both active (open-ended) → error (hard-block)', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
        session(id: 'b', memberId: 'm1', start: t(10)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.selfOverlap);
      expect(issues.first.severity, FrontingIssueSeverity.error);
    });

    test('different members, overlapping → NO issue (cross-member is valid)', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(20)),
        session(id: 'b', memberId: 'm2', start: t(10), end: t(30)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, isEmpty);
    });

    test('different members, both active → NO issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0)),
        session(id: 'b', memberId: 'm2', start: t(10)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, isEmpty);
    });

    test('same member, full containment → warning', () {
      // A: 0–60, B: 10–30 (B inside A)
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(60)),
        session(id: 'b', memberId: 'm1', start: t(10), end: t(30)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.severity, FrontingIssueSeverity.warning);
    });

    test('touching boundaries → no issue', () {
      // A ends at t(30), B starts at t(30) — touching, not overlapping
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm1', start: t(30), end: t(60)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, isEmpty);
    });

    test('null memberId sessions are not flagged', () {
      final sessions = [
        session(id: 'a', memberId: null, start: t(0), end: t(20)),
        session(id: 'b', memberId: null, start: t(10), end: t(30)),
      ];
      final issues = detectSelfOverlap(sessions);
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
        session(id: 'b', memberId: 'm1', start: t(10), end: t(30)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, isEmpty);
    });

    test('single session → no issue', () {
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(30)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, isEmpty);
    });

    test('multiple members, only same-member overlaps flagged', () {
      // m1: a=0–20, b=10–30 → overlap (warning)
      // m2: c=0–20, d=25–45 → no overlap
      final sessions = [
        session(id: 'a', memberId: 'm1', start: t(0), end: t(20)),
        session(id: 'b', memberId: 'm1', start: t(10), end: t(30)),
        session(id: 'c', memberId: 'm2', start: t(0), end: t(20)),
        session(id: 'd', memberId: 'm2', start: t(25), end: t(45)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.memberIds, contains('m1'));
    });

    test('issue carries correct memberIds', () {
      final sessions = [
        session(id: 'a', memberId: 'm42', start: t(0), end: t(30)),
        session(id: 'b', memberId: 'm42', start: t(15), end: t(45)),
      ];
      final issues = detectSelfOverlap(sessions);
      expect(issues, hasLength(1));
      expect(issues.first.memberIds, ['m42']);
    });
  });

  // ---------------------------------------------------------------------------
  // Sleep-vs-Unknown-sentinel skip semantics (Bug 3)
  //
  // Pre-fix, validation rules used `memberId == null` as an implicit "skip
  // this row, it's sleep" marker.  Post-Fix-K + audit batch L the only rows
  // that legitimately carry memberId == null are sleep rows (they're filtered
  // upstream by the snapshot builder), and Unknown-fronting rows now write the
  // sentinel id.  These tests pin down the new contract:
  //   - sleep rows are skipped REGARDLESS of memberId
  //   - normal rows carrying the Unknown-sentinel id ARE checked (not skipped)
  // ---------------------------------------------------------------------------

  group('sleep skipping (Bug 3)', () {
    final sentinel = unknownSentinelMemberId;

    test('detectDuplicates skips sleep rows but checks Unknown-sentinel rows',
        () {
      // Two Unknown-sentinel fronting rows starting close together — should
      // be flagged as duplicates now that sentinel rows are first-class.
      final sessions = [
        session(id: 'u1', memberId: sentinel, start: t(0), end: t(30)),
        session(id: 'u2', memberId: sentinel, start: t(1), end: t(31)),
        // Two sleep rows, also close together — sleep is NOT subject to
        // duplicate detection (different concept).  These intentionally
        // carry a non-null memberId to prove the skip is sessionType-driven,
        // not memberId-driven.
        session(
          id: 's1',
          memberId: sentinel,
          start: t(0),
          end: t(30),
          sessionType: SessionType.sleep,
        ),
        session(
          id: 's2',
          memberId: sentinel,
          start: t(1),
          end: t(31),
          sessionType: SessionType.sleep,
        ),
      ];
      const config = FrontingValidationConfig();
      final issues = detectDuplicates(sessions, config);

      // Exactly one duplicate pair — the two Unknown-sentinel fronting rows.
      expect(issues, hasLength(1));
      expect(issues.first.sessionIds.toSet(), {'u1', 'u2'});
    });

    test(
        'detectMergeableAdjacent skips sleep rows but checks Unknown-sentinel '
        'rows', () {
      final sessions = [
        // Two adjacent Unknown-sentinel fronting rows — should be flagged.
        session(id: 'u1', memberId: sentinel, start: t(0), end: t(30)),
        session(id: 'u2', memberId: sentinel, start: t(31), end: t(60)),
        // Two adjacent sleep rows — should NOT be flagged regardless of memberId.
        session(
          id: 's1',
          memberId: sentinel,
          start: t(0),
          end: t(30),
          sessionType: SessionType.sleep,
        ),
        session(
          id: 's2',
          memberId: sentinel,
          start: t(31),
          end: t(60),
          sessionType: SessionType.sleep,
        ),
      ];
      const config = FrontingValidationConfig();
      final issues = detectMergeableAdjacent(sessions, config);

      expect(issues, hasLength(1));
      expect(issues.first.sessionIds.toSet(), {'u1', 'u2'});
    });

    test('detectSelfOverlap skips sleep rows but checks Unknown-sentinel rows',
        () {
      final sessions = [
        // Two overlapping Unknown-sentinel fronting rows — flagged.
        session(id: 'u1', memberId: sentinel, start: t(0), end: t(30)),
        session(id: 'u2', memberId: sentinel, start: t(15), end: t(45)),
        // Two overlapping sleep rows — NOT flagged (sleep is not a self-
        // overlap concept; sleep can also legitimately overlap fronting).
        session(
          id: 's1',
          memberId: sentinel,
          start: t(0),
          end: t(30),
          sessionType: SessionType.sleep,
        ),
        session(
          id: 's2',
          memberId: sentinel,
          start: t(15),
          end: t(45),
          sessionType: SessionType.sleep,
        ),
      ];
      final issues = detectSelfOverlap(sessions);

      expect(issues, hasLength(1));
      expect(issues.first.sessionIds.toSet(), {'u1', 'u2'});
    });
  });
}
