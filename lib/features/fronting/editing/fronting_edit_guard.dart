import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_rules.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';

class FrontingEditGuard {
  const FrontingEditGuard();

  /// Validate basic time constraints.
  List<FrontingValidationIssue> validateTimeRange(DateTime start, DateTime? end) {
    final issues = <FrontingValidationIssue>[];
    if (end != null && !end.isAfter(start)) {
      issues.add(FrontingValidationIssue(
        id: 'time_range:invalid',
        type: FrontingIssueType.invalidRange,
        severity: FrontingIssueSeverity.error,
        sessionIds: [],
        memberIds: [],
        rangeStart: start,
        rangeEnd: end,
        summary: 'End time must be after start time',
      ));
    }
    final now = DateTime.now();
    if (start.isAfter(now.add(const Duration(minutes: 1)))) {
      issues.add(FrontingValidationIssue(
        id: 'time_range:future_start',
        type: FrontingIssueType.futureSession,
        severity: FrontingIssueSeverity.error,
        sessionIds: [],
        memberIds: [],
        rangeStart: start,
        rangeEnd: end ?? start,
        summary: 'Session cannot start in the future',
      ));
    }
    if (end != null && end.isAfter(now.add(const Duration(minutes: 1)))) {
      issues.add(FrontingValidationIssue(
        id: 'time_range:future_end',
        type: FrontingIssueType.futureSession,
        severity: FrontingIssueSeverity.error,
        sessionIds: [],
        memberIds: [],
        rangeStart: start,
        rangeEnd: end,
        summary: 'Session cannot end in the future',
      ));
    }
    return issues;
  }

  /// Validate a session edit before saving.
  FrontingEditValidationResult validateEdit({
    required FrontingSessionSnapshot original,
    required FrontingSessionPatch patch,
    required List<FrontingSessionSnapshot> nearbySessions,
    required FrontingTimingMode timingMode,
  }) {
    // Apply patch to get proposed state
    final proposed = _applyPatch(original, patch);

    // Check overlaps (exclude self)
    final others = nearbySessions.where((s) => s.id != original.id && !s.isDeleted).toList();
    final overlapping = <FrontingSessionSnapshot>[];
    for (final other in others) {
      final otherEnd = other.end;
      final proposedEnd = proposed.end;
      // Overlap: A.start < B.end AND B.start < A.end
      // Active sessions use far-future for effective end
      final aEnd = proposedEnd ?? DateTime(9999);
      final bEnd = otherEnd ?? DateTime(9999);
      // Touching boundaries (proposed.start == bEnd or other.start == aEnd) are NOT overlaps
      if (proposed.start.isBefore(bEnd) && other.start.isBefore(aEnd) &&
          proposed.start != bEnd && other.start != aEnd) {
        overlapping.add(other);
      }
    }

    // Check gaps created by shrinking
    final gaps = <GapInfo>[];
    final config = FrontingValidationConfig(timingMode: timingMode);
    final threshold = config.reportableGapThreshold;

    // If start moved later, check gap before
    if (proposed.start.isAfter(original.start)) {
      // Find session that ended at or before original.start (closest previous)
      final sorted = [...others]..sort((a, b) => a.start.compareTo(b.start));
      final prev = sorted.where((s) =>
          s.end != null && !s.end!.isAfter(original.start)).lastOrNull;
      if (prev != null && prev.end != null) {
        final gapDuration = proposed.start.difference(prev.end!);
        if (gapDuration > threshold) {
          gaps.add(GapInfo(
            start: prev.end!,
            end: proposed.start,
            beforeSessionId: prev.id,
            afterSessionId: original.id,
          ));
        }
      }
    }

    // If end moved earlier, check gap after
    if (original.end != null && proposed.end != null &&
        proposed.end!.isBefore(original.end!)) {
      final sorted = [...others]..sort((a, b) => a.start.compareTo(b.start));
      final next = sorted.where((s) => !s.start.isBefore(original.end!)).firstOrNull;
      if (next != null) {
        final gapDuration = next.start.difference(proposed.end!);
        if (gapDuration > threshold) {
          gaps.add(GapInfo(
            start: proposed.end!,
            end: next.start,
            beforeSessionId: original.id,
            afterSessionId: next.id,
          ));
        }
      }
    }

    // Check duplicates
    final duplicateConfig = FrontingValidationConfig(timingMode: timingMode);
    final duplicateIssues = detectDuplicates(
      [proposed, ...others], duplicateConfig,
    );
    final duplicates = <FrontingSessionSnapshot>[];
    for (final issue in duplicateIssues) {
      if (issue.sessionIds.contains(proposed.id)) {
        for (final id in issue.sessionIds) {
          if (id != proposed.id) {
            final dup = others.where((s) => s.id == id).firstOrNull;
            if (dup != null) duplicates.add(dup);
          }
        }
      }
    }

    final canSave = overlapping.isEmpty && gaps.isEmpty && duplicates.isEmpty;

    return FrontingEditValidationResult(
      canSaveDirectly: canSave,
      overlappingSessions: overlapping,
      gapsCreated: gaps,
      duplicates: duplicates,
    );
  }

  /// Build delete context for a session.
  FrontingDeleteContext getDeleteContext(
    FrontingSessionSnapshot session,
    List<FrontingSessionSnapshot> allSessions,
  ) {
    final active = allSessions.where((s) => !s.isDeleted && s.id != session.id).toList();
    active.sort((a, b) => a.start.compareTo(b.start));

    FrontingSessionSnapshot? previous;
    FrontingSessionSnapshot? next;

    for (final s in active) {
      if (s.end != null && !s.end!.isAfter(session.start)) {
        previous = s; // keep updating to get the closest previous
      }
    }
    for (final s in active) {
      if (!s.start.isBefore(session.end ?? DateTime(9999))) {
        next = s;
        break; // first one is closest
      }
    }

    return FrontingDeleteContext(
      session: session,
      previous: previous,
      next: next,
    );
  }

  FrontingSessionSnapshot _applyPatch(
    FrontingSessionSnapshot original,
    FrontingSessionPatch patch,
  ) {
    return FrontingSessionSnapshot(
      id: original.id,
      memberId: patch.clearMemberId ? null : (patch.memberId ?? original.memberId),
      start: patch.start ?? original.start,
      end: patch.clearEnd ? null : (patch.end ?? original.end),
      coFronterIds: patch.coFronterIds ?? original.coFronterIds,
      notes: patch.notes ?? original.notes,
      confidenceIndex: patch.confidenceIndex ?? original.confidenceIndex,
    );
  }
}
