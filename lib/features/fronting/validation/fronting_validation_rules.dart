import 'fronting_validation_config.dart';
import 'fronting_validation_models.dart';

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Far-future sentinel used as effective end for active sessions.
final _farFuture = DateTime.utc(9999, 12, 31, 23, 59, 59);

/// Builds a deterministic issue ID from a type and the session IDs involved.
String _buildIssueId(FrontingIssueType type, List<String> sessionIds) {
  final sorted = [...sessionIds]..sort();
  return '${type.name}:${sorted.join(',')}';
}

/// Returns sessions that are not deleted, sorted by (start, end ?? farFuture, id).
List<FrontingSessionSnapshot> _activeSorted(
    List<FrontingSessionSnapshot> sessions) {
  final filtered = sessions.where((s) => !s.isDeleted).toList();
  filtered.sort((a, b) {
    final startCmp = a.start.compareTo(b.start);
    if (startCmp != 0) return startCmp;
    final aEnd = a.end ?? _farFuture;
    final bEnd = b.end ?? _farFuture;
    final endCmp = aEnd.compareTo(bEnd);
    if (endCmp != 0) return endCmp;
    return a.id.compareTo(b.id);
  });
  return filtered;
}

/// Returns true if two sessions have the same fronting configuration
/// (same primary member AND same co-fronters).
bool _sameFrontingConfig(
    FrontingSessionSnapshot a, FrontingSessionSnapshot b) {
  if (a.memberId != b.memberId) return false;
  final aCoFronters = [...a.coFronterIds]..sort();
  final bCoFronters = [...b.coFronterIds]..sort();
  if (aCoFronters.length != bCoFronters.length) return false;
  for (int i = 0; i < aCoFronters.length; i++) {
    if (aCoFronters[i] != bCoFronters[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// 1. detectInvalidRanges
// ---------------------------------------------------------------------------

/// Detects sessions where the end time is not strictly after the start time.
List<FrontingValidationIssue> detectInvalidRanges(
    List<FrontingSessionSnapshot> sessions) {
  final issues = <FrontingValidationIssue>[];

  for (final s in sessions) {
    if (s.isDeleted) continue;
    final end = s.end;
    if (end == null) continue; // active sessions are fine
    if (!end.isAfter(s.start)) {
      issues.add(FrontingValidationIssue(
        id: _buildIssueId(FrontingIssueType.invalidRange, [s.id]),
        type: FrontingIssueType.invalidRange,
        severity: FrontingIssueSeverity.error,
        sessionIds: [s.id],
        memberIds: [if (s.memberId != null) s.memberId!],
        rangeStart: s.start,
        rangeEnd: end,
        summary: 'Session end is not after its start',
        details: 'Start: ${s.start}, End: $end',
      ));
    }
  }

  return issues;
}

// ---------------------------------------------------------------------------
// 2. detectOverlaps
// ---------------------------------------------------------------------------

/// Detects sessions whose time ranges overlap.
///
/// Touching boundaries (A.end == B.start) are NOT considered overlaps.
/// Active sessions use a far-future sentinel for their effective end time.
List<FrontingValidationIssue> detectOverlaps(
    List<FrontingSessionSnapshot> sessions) {
  final sorted = _activeSorted(sessions);
  final issues = <FrontingValidationIssue>[];

  for (int i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    final aEnd = a.end ?? _farFuture;

    for (int j = i + 1; j < sorted.length; j++) {
      final b = sorted[j];
      // Because sessions are sorted by start, if B starts at or after A's end
      // there can be no overlap with A or any later session for this i.
      if (!b.start.isBefore(aEnd)) break;

      final bEnd = b.end ?? _farFuture;

      // Overlap: A.start < B.endEffective AND B.start < A.endEffective
      // Touching (A.end == B.start) means !B.start.isBefore(aEnd) → already
      // handled by the break above (equal also breaks). So here B.start < aEnd.
      if (a.start.isBefore(bEnd)) {
        final overlapStart =
            a.start.isAfter(b.start) ? a.start : b.start;
        final overlapEnd = aEnd.isBefore(bEnd) ? aEnd : bEnd;

        issues.add(FrontingValidationIssue(
          id: _buildIssueId(FrontingIssueType.overlap, [a.id, b.id]),
          type: FrontingIssueType.overlap,
          severity: FrontingIssueSeverity.error,
          sessionIds: [a.id, b.id],
          memberIds: [
            if (a.memberId != null) a.memberId!,
            if (b.memberId != null) b.memberId!,
          ],
          rangeStart: overlapStart,
          rangeEnd: overlapEnd == _farFuture ? overlapStart : overlapEnd,
          summary: 'Sessions overlap',
        ));
      }
    }
  }

  return issues;
}

// ---------------------------------------------------------------------------
// 3. detectDuplicates
// ---------------------------------------------------------------------------

/// Detects probable duplicate sessions for the same member.
///
/// Two sessions with the same non-null memberId are considered duplicates when:
/// - Both have end times: starts within [config.duplicateTolerance] AND
///   ends within [config.duplicateTolerance].
/// - Both are active (end == null): starts within [config.duplicateTolerance].
/// - One active + one closed: NOT a duplicate (the state differs meaningfully).
List<FrontingValidationIssue> detectDuplicates(
    List<FrontingSessionSnapshot> sessions, FrontingValidationConfig config) {
  final sorted = _activeSorted(sessions);
  final issues = <FrontingValidationIssue>[];
  final tolerance = config.duplicateTolerance;

  for (int i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    if (a.memberId == null) continue;

    for (int j = i + 1; j < sorted.length; j++) {
      final b = sorted[j];
      if (b.memberId == null) continue;
      if (!_sameFrontingConfig(a, b)) continue;

      // Sorted by start: if B starts more than tolerance after A, no more
      // duplicates possible for A (all later B will also exceed tolerance).
      if (b.start.difference(a.start).abs() > tolerance) break;

      final bothActive = a.end == null && b.end == null;
      final bothClosed = a.end != null && b.end != null;

      if (bothActive) {
        // Active + Active: starts within tolerance → duplicate
        issues.add(FrontingValidationIssue(
          id: _buildIssueId(FrontingIssueType.duplicate, [a.id, b.id]),
          type: FrontingIssueType.duplicate,
          severity: FrontingIssueSeverity.warning,
          sessionIds: [a.id, b.id],
          memberIds: [a.memberId!],
          rangeStart: a.start.isBefore(b.start) ? a.start : b.start,
          rangeEnd: a.start.isAfter(b.start) ? a.start : b.start,
          summary: 'Possible duplicate active sessions for same member',
        ));
      } else if (bothClosed) {
        // Closed + Closed: both start and end within tolerance → duplicate
        final endDiff = a.end!.difference(b.end!).abs();
        if (endDiff <= tolerance) {
          issues.add(FrontingValidationIssue(
            id: _buildIssueId(FrontingIssueType.duplicate, [a.id, b.id]),
            type: FrontingIssueType.duplicate,
            severity: FrontingIssueSeverity.warning,
            sessionIds: [a.id, b.id],
            memberIds: [a.memberId!],
            rangeStart: a.start.isBefore(b.start) ? a.start : b.start,
            rangeEnd: a.end!.isAfter(b.end!) ? a.end! : b.end!,
            summary: 'Possible duplicate sessions for same member',
          ));
        }
      }
      // One active + one closed → not a duplicate; skip.
    }
  }

  return issues;
}

// ---------------------------------------------------------------------------
// 4. detectMergeableAdjacent
// ---------------------------------------------------------------------------

/// Detects consecutive sessions for the same member that could be merged.
///
/// The gap between the end of session A and the start of session B must be
/// ≤ [config.mergeableGapThreshold]. Overlapping sessions are excluded
/// (those are a separate issue type).
List<FrontingValidationIssue> detectMergeableAdjacent(
    List<FrontingSessionSnapshot> sessions, FrontingValidationConfig config) {
  final sorted = _activeSorted(sessions);
  final issues = <FrontingValidationIssue>[];
  final threshold = config.mergeableGapThreshold;

  for (int i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    if (a.memberId == null) continue;
    final aEnd = a.end;
    if (aEnd == null) continue; // active sessions have no defined end

    for (int j = i + 1; j < sorted.length; j++) {
      final b = sorted[j];
      if (b.memberId == null) continue;
      if (!_sameFrontingConfig(a, b)) continue;

      // If B starts strictly before A's end they overlap — skip (different issue).
      if (b.start.isBefore(aEnd)) continue;

      // Gap = B.start - A.end
      final gap = b.start.difference(aEnd);

      // Sessions sorted by start: once gap exceeds threshold, later B will
      // only have bigger gaps for this A (same member).
      if (gap > threshold) break;

      issues.add(FrontingValidationIssue(
        id: _buildIssueId(FrontingIssueType.mergeableAdjacent, [a.id, b.id]),
        type: FrontingIssueType.mergeableAdjacent,
        severity: FrontingIssueSeverity.info,
        sessionIds: [a.id, b.id],
        memberIds: [a.memberId!],
        rangeStart: aEnd,
        rangeEnd: b.start,
        summary: 'Adjacent sessions for same member could be merged',
        details: 'Gap: ${gap.inSeconds}s',
      ));
    }
  }

  return issues;
}

// ---------------------------------------------------------------------------
// 5. detectGaps
// ---------------------------------------------------------------------------

/// Detects gaps between consecutive sessions (any members) larger than the
/// configured threshold.
///
/// Only sessions with a defined end time can produce a gap. The gap is
/// measured from the end of one session to the start of the next session
/// that begins after it.
List<FrontingValidationIssue> detectGaps(
    List<FrontingSessionSnapshot> sessions, FrontingValidationConfig config) {
  final sorted = _activeSorted(sessions);
  final threshold = config.reportableGapThreshold;
  final issues = <FrontingValidationIssue>[];

  // We sweep sessions left to right, tracking the furthest end seen so far
  // among sessions that have a defined end.
  DateTime? maxEnd;
  FrontingSessionSnapshot? maxEndSession;

  for (final s in sorted) {
    if (maxEnd != null && maxEndSession != null) {
      // Only measure gap if s starts after maxEnd (no overlap territory).
      if (s.start.isAfter(maxEnd)) {
        final gap = s.start.difference(maxEnd);
        if (gap > threshold) {
          issues.add(FrontingValidationIssue(
            id: _buildIssueId(
                FrontingIssueType.gap, [maxEndSession.id, s.id]),
            type: FrontingIssueType.gap,
            severity: FrontingIssueSeverity.warning,
            sessionIds: [maxEndSession.id, s.id],
            memberIds: [
              if (maxEndSession.memberId != null) maxEndSession.memberId!,
              if (s.memberId != null) s.memberId!,
            ],
            rangeStart: maxEnd,
            rangeEnd: s.start,
            summary: 'Gap in fronting coverage',
            details: 'Gap duration: ${gap.inMinutes}m ${gap.inSeconds % 60}s',
          ));
        }
      }
    }

    // Update maxEnd to track the furthest closed end seen so far.
    if (s.end != null) {
      if (maxEnd == null || s.end!.isAfter(maxEnd)) {
        maxEnd = s.end;
        maxEndSession = s;
      }
    }
  }

  return issues;
}

// ---------------------------------------------------------------------------
// 6. detectFutureSessions
// ---------------------------------------------------------------------------

/// Detects sessions whose start or end time is in the future relative to [now].
///
/// - Start > now + futureTolerance → error (entire session is in the future)
/// - End > now + futureTolerance, start ≤ now + futureTolerance → warning
///   (session started in the past but ends in the future)
List<FrontingValidationIssue> detectFutureSessions(
    List<FrontingSessionSnapshot> sessions,
    DateTime now,
    FrontingValidationConfig config) {
  final issues = <FrontingValidationIssue>[];
  final cutoff = now.add(config.futureTolerance);

  for (final s in sessions) {
    if (s.isDeleted) continue;

    final startIsFuture = s.start.isAfter(cutoff);
    // "End in future" warning: only applies when start is strictly in the past
    // (before now, not just before cutoff). The end must also be after cutoff.
    final startIsInPast = s.start.isBefore(now);
    final endIsFuture =
        startIsInPast && s.end != null && s.end!.isAfter(cutoff);

    if (startIsFuture) {
      // Entire session is in the future.
      issues.add(FrontingValidationIssue(
        id: _buildIssueId(FrontingIssueType.futureSession, [s.id]),
        type: FrontingIssueType.futureSession,
        severity: FrontingIssueSeverity.error,
        sessionIds: [s.id],
        memberIds: [if (s.memberId != null) s.memberId!],
        rangeStart: s.start,
        rangeEnd: s.end ?? s.start,
        summary: 'Session starts in the future',
        details: 'Start: ${s.start}, now: $now',
      ));
    } else if (endIsFuture) {
      // Session started in the past but ends in the future.
      issues.add(FrontingValidationIssue(
        id: _buildIssueId(FrontingIssueType.futureSession, [s.id]),
        type: FrontingIssueType.futureSession,
        severity: FrontingIssueSeverity.warning,
        sessionIds: [s.id],
        memberIds: [if (s.memberId != null) s.memberId!],
        rangeStart: s.start,
        rangeEnd: s.end!,
        summary: 'Session ends in the future',
        details: 'End: ${s.end}, now: $now',
      ));
    }
  }

  return issues;
}
