import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SessionType;
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_rules.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/utils/session_time_bounds.dart';

class FrontingEditGuard {
  const FrontingEditGuard();

  /// Validate basic time constraints.
  List<FrontingValidationIssue> validateTimeRange(
    DateTime start,
    DateTime? end,
  ) {
    final issues = <FrontingValidationIssue>[];
    if (end != null && !end.isAfter(start)) {
      issues.add(
        FrontingValidationIssue(
          id: 'time_range:invalid',
          type: FrontingIssueType.invalidRange,
          severity: FrontingIssueSeverity.error,
          sessionIds: [],
          memberIds: [],
          rangeStart: start,
          rangeEnd: end,
          summary: 'End time must be after start time',
        ),
      );
    }
    final now = DateTime.now();
    if (start.isAfter(now.add(const Duration(minutes: 1)))) {
      issues.add(
        FrontingValidationIssue(
          id: 'time_range:future_start',
          type: FrontingIssueType.futureSession,
          severity: FrontingIssueSeverity.error,
          sessionIds: [],
          memberIds: [],
          rangeStart: start,
          rangeEnd: end ?? start,
          summary: 'Session cannot start in the future',
        ),
      );
    }
    if (end != null && end.isAfter(now.add(const Duration(minutes: 1)))) {
      issues.add(
        FrontingValidationIssue(
          id: 'time_range:future_end',
          type: FrontingIssueType.futureSession,
          severity: FrontingIssueSeverity.error,
          sessionIds: [],
          memberIds: [],
          rangeStart: start,
          rangeEnd: end,
          summary: 'Session cannot end in the future',
        ),
      );
    }
    return issues;
  }

  /// Validate a session edit before saving.
  ///
  /// In the per-member model, cross-member overlaps are valid by design.
  /// Only same-member, same-type self-overlaps surface as issues that block
  /// or warn — a member can't front (or sleep) twice concurrently.
  FrontingEditValidationResult validateEdit({
    required FrontingSessionSnapshot original,
    required FrontingSessionPatch patch,
    required List<FrontingSessionSnapshot> nearbySessions,
    required FrontingTimingMode timingMode,
  }) {
    // Apply patch to get proposed state
    final proposed = _applyPatch(original, patch);

    // Find sessions for the same member (self-overlap candidates).
    final others = nearbySessions
        .where((s) => s.id != original.id && !s.isDeleted)
        .toList();

    // Only same-member, same-type self-overlaps are conflicts (a member can't
    // front twice at once). Cross-member overlaps are valid co-fronting, and
    // cross-type overlaps are NOT conflicts — sleep is a parallel timeline.
    // Surfacing cross-type here is what let an edited open-ended front, whose
    // effective end is far-future, contain and silently delete every later
    // sleep row. Mirrors trimOverlap / getDeletePeriodContext, which skip it.
    final overlapping = <FrontingSessionSnapshot>[];
    for (final other in others) {
      if (other.sessionType != proposed.sessionType) continue;
      final otherEnd = other.end;
      final proposedEnd = proposed.end;
      // Active sessions use far-future for effective end
      final aEnd = proposedEnd ?? farFutureSessionEnd;
      final bEnd = otherEnd ?? farFutureSessionEnd;
      // Touching boundaries are NOT overlaps
      if (proposed.start.isBefore(bEnd) &&
          other.start.isBefore(aEnd) &&
          proposed.start != bEnd &&
          other.start != aEnd) {
        final isSameMember =
            proposed.memberId != null && proposed.memberId == other.memberId;
        if (isSameMember) {
          overlapping.add(other);
        }
      }
    }

    // Check gaps created by shrinking
    final gaps = <GapInfo>[];
    final config = FrontingValidationConfig(timingMode: timingMode);
    final threshold = config.mergeableGapThreshold;

    // If start moved later, check gap before
    if (proposed.start.isAfter(original.start)) {
      // Find session that ended at or before original.start (closest previous)
      final sorted = [...others]..sort((a, b) => a.start.compareTo(b.start));
      final prev = sorted
          .where((s) => s.end != null && !s.end!.isAfter(original.start))
          .lastOrNull;
      if (prev != null && prev.end != null) {
        final gapDuration = proposed.start.difference(prev.end!);
        if (gapDuration > threshold) {
          gaps.add(
            GapInfo(
              start: prev.end!,
              end: proposed.start,
              beforeSessionId: prev.id,
              afterSessionId: original.id,
            ),
          );
        }
      }
    }

    // If end moved earlier, check gap after
    if (original.end != null &&
        proposed.end != null &&
        proposed.end!.isBefore(original.end!)) {
      final sorted = [...others]..sort((a, b) => a.start.compareTo(b.start));
      final next = sorted
          .where((s) => !s.start.isBefore(original.end!))
          .firstOrNull;
      if (next != null) {
        final gapDuration = next.start.difference(proposed.end!);
        if (gapDuration > threshold) {
          gaps.add(
            GapInfo(
              start: proposed.end!,
              end: next.start,
              beforeSessionId: original.id,
              afterSessionId: next.id,
            ),
          );
        }
      }
    }

    // Check duplicates (same-member only)
    final duplicateConfig = FrontingValidationConfig(timingMode: timingMode);
    final duplicateIssues = detectDuplicates([
      proposed,
      ...others,
    ], duplicateConfig);
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
    final active =
        allSessions
            .where(
              (s) =>
                  !s.isDeleted &&
                  s.id != session.id &&
                  s.sessionType == session.sessionType,
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    FrontingSessionSnapshot? previous;
    FrontingSessionSnapshot? next;

    for (final s in active) {
      if (s.end != null && !s.end!.isAfter(session.start)) {
        previous = s; // keep updating to get the closest previous
      }
    }
    for (final s in active) {
      if (!s.start.isBefore(session.end ?? farFutureSessionEnd)) {
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

  /// Build delete context for a derived period.
  ///
  /// In-period membership comes from [periodSessionIds], not raw
  /// time-overlap: always-fronting background sessions overlap many
  /// periods but aren't claimed by any one of them, and deleting a
  /// visitor period must not trim or split a long-running host.
  ///
  /// Sleep sessions live on a parallel timeline and are skipped
  /// entirely.
  FrontingDeletePeriodContext getDeletePeriodContext({
    required DateTime periodStart,
    required DateTime periodEnd,
    required bool isOngoing,
    required Set<String> periodSessionIds,
    required List<FrontingSessionSnapshot> allSessions,
  }) {
    final inPeriod = <FrontingSessionSnapshot>[];
    final previous = <FrontingSessionSnapshot>[];
    final next = <FrontingSessionSnapshot>[];

    for (final s in allSessions) {
      if (s.isDeleted) continue;
      if (s.sessionType == SessionType.sleep) continue;

      if (periodSessionIds.contains(s.id)) {
        inPeriod.add(s);
        continue;
      }
      if (s.end != null && s.end!.isAtSameMomentAs(periodStart)) {
        previous.add(s);
      } else if (s.start.isAtSameMomentAs(periodEnd)) {
        next.add(s);
      }
    }

    return FrontingDeletePeriodContext(
      periodStart: periodStart,
      periodEnd: periodEnd,
      isOngoing: isOngoing,
      sessionsInPeriod: inPeriod,
      previousSessions: previous,
      nextSessions: next,
    );
  }

  FrontingSessionSnapshot _applyPatch(
    FrontingSessionSnapshot original,
    FrontingSessionPatch patch,
  ) {
    return FrontingSessionSnapshot(
      id: original.id,
      memberId: patch.clearMemberId
          ? null
          : (patch.memberId ?? original.memberId),
      start: patch.start ?? original.start,
      end: patch.clearEnd ? null : (patch.end ?? original.end),
      notes: patch.clearNotes ? null : (patch.notes ?? original.notes),
      confidenceIndex: patch.confidenceIndex ?? original.confidenceIndex,
      sessionType: original.sessionType,
      quality: original.quality,
      isHealthKitImport: original.isHealthKitImport,
      isDeleted: original.isDeleted,
    );
  }
}
