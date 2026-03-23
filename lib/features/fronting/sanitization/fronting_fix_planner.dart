import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_models.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_preview.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

/// Translates a [FrontingValidationIssue] into one or more user-selectable
/// [FrontingFixPlan]s, each containing typed [FrontingSessionChange] descriptors.
class FrontingFixPlanner {
  const FrontingFixPlanner();

  // ─── Public API ───────────────────────────────────────────────────────────

  List<FrontingFixPlan> plansForIssue(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    switch (issue.type) {
      case FrontingIssueType.overlap:
        return _plansForOverlap(issue, sessions);
      case FrontingIssueType.gap:
        return _plansForGap(issue, sessions);
      case FrontingIssueType.duplicate:
        return _plansForDuplicate(issue, sessions);
      case FrontingIssueType.mergeableAdjacent:
        return _plansForMergeableAdjacent(issue, sessions);
      case FrontingIssueType.invalidRange:
        return _plansForInvalidRange(issue, sessions);
      case FrontingIssueType.futureSession:
        return _plansForFutureSession(issue, sessions);
    }
  }

  FrontingFixPreview buildPreview(FrontingFixPlan plan) {
    final (summary, bullets) = _previewContent(plan);
    return FrontingFixPreview(
      plan: plan,
      summary: summary,
      bulletPoints: bullets,
    );
  }

  // ─── Overlap ──────────────────────────────────────────────────────────────

  List<FrontingFixPlan> _plansForOverlap(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    final involved = _sessionsFor(issue, sessions);
    if (involved.length < 2) return [];

    final earlier = involved.first.start.isBefore(involved.last.start)
        ? involved.first
        : involved.last;
    final later = earlier == involved.first ? involved.last : involved.first;

    final sameMember = issue.memberIds.length == 1 ||
        (involved.length >= 2 && involved.first.memberId == involved.last.memberId);

    if (sameMember) {
      // Merge: keep earliest start, latest end, delete the other
      final keepId = earlier.id;
      final deleteId = later.id;
      final earliestStart = earlier.start;
      final latestEnd = _laterDateTime(earlier.end, later.end);

      return [
        FrontingFixPlan(
          id: '${issue.id}-merge',
          type: FrontingFixType.mergeAdjacent,
          title: 'Merge sessions',
          description: 'Combine both overlapping sessions into one.',
          affectedSessionIds: [earlier.id, later.id],
          changes: [
            UpdateSessionChange(
              sessionId: keepId,
              patch: FrontingSessionPatch(
                start: earliestStart,
                end: latestEnd,
              ),
            ),
            DeleteSessionChange(deleteId),
          ],
        ),
      ];
    } else {
      // Different members — offer trim earlier or trim later
      final trimEarlierPlan = FrontingFixPlan(
        id: '${issue.id}-trim-earlier',
        type: FrontingFixType.trimEarlier,
        title: 'Trim earlier session',
        description: 'Shorten the earlier session to end where the later one begins.',
        affectedSessionIds: [earlier.id],
        changes: [
          UpdateSessionChange(
            sessionId: earlier.id,
            patch: FrontingSessionPatch(end: later.start),
          ),
        ],
      );

      final trimLaterPlan = FrontingFixPlan(
        id: '${issue.id}-trim-later',
        type: FrontingFixType.trimLater,
        title: 'Trim later session',
        description: 'Shorten the later session to start where the earlier one ends.',
        affectedSessionIds: [later.id],
        changes: [
          UpdateSessionChange(
            sessionId: later.id,
            patch: FrontingSessionPatch(start: earlier.end),
          ),
        ],
      );

      return [trimEarlierPlan, trimLaterPlan];
    }
  }

  // ─── Gap ─────────────────────────────────────────────────────────────────

  List<FrontingFixPlan> _plansForGap(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    final fillPlan = FrontingFixPlan(
      id: '${issue.id}-fill-unknown',
      type: FrontingFixType.fillGapWithUnknown,
      title: 'Fill gap with Unknown',
      description: 'Create an Unknown fronter session to cover the gap.',
      affectedSessionIds: issue.sessionIds,
      changes: [
        CreateSessionChange(
          FrontingSessionDraft(
            memberId: null, // Unknown fronter
            start: issue.rangeStart,
            end: issue.rangeEnd,
          ),
        ),
      ],
    );

    final leavePlan = FrontingFixPlan(
      id: '${issue.id}-leave-gap',
      type: FrontingFixType.leaveGap,
      title: 'Leave gap',
      description: 'Keep the timeline as-is without filling the gap.',
      affectedSessionIds: issue.sessionIds,
      changes: const [],
    );

    return [fillPlan, leavePlan];
  }

  // ─── Duplicate ────────────────────────────────────────────────────────────

  List<FrontingFixPlan> _plansForDuplicate(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    final involved = _sessionsFor(issue, sessions);
    if (involved.length < 2) return [];

    // Score each session by richness of data; delete the one with less
    final scored = involved.map((s) => (s, _dataScore(s))).toList();
    scored.sort((a, b) => b.$2.compareTo(a.$2)); // highest score first

    final deleteTarget = scored.last.$1;

    return [
      FrontingFixPlan(
        id: '${issue.id}-delete-duplicate',
        type: FrontingFixType.deleteDuplicate,
        title: 'Delete duplicate',
        description: 'Remove the less-complete duplicate session.',
        affectedSessionIds: [deleteTarget.id],
        changes: [DeleteSessionChange(deleteTarget.id)],
      ),
    ];
  }

  // ─── Mergeable adjacent ───────────────────────────────────────────────────

  List<FrontingFixPlan> _plansForMergeableAdjacent(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    final involved = _sessionsFor(issue, sessions);
    if (involved.length < 2) return [];

    final earlier = involved.reduce(
      (a, b) => a.start.isBefore(b.start) ? a : b,
    );
    final later = involved.firstWhere((s) => s.id != earlier.id);

    // Join notes with " | " separator, filtering out nulls/empty
    final noteParts = [earlier.notes, later.notes]
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    final mergedNotes = noteParts.isEmpty ? null : noteParts.join(' | ');

    final latestEnd = _laterDateTime(earlier.end, later.end);

    return [
      FrontingFixPlan(
        id: '${issue.id}-merge-adjacent',
        type: FrontingFixType.mergeAdjacent,
        title: 'Merge adjacent sessions',
        description: 'Combine consecutive sessions by the same member into one.',
        affectedSessionIds: [earlier.id, later.id],
        changes: [
          UpdateSessionChange(
            sessionId: earlier.id,
            patch: FrontingSessionPatch(
              end: latestEnd,
              notes: mergedNotes,
            ),
          ),
          DeleteSessionChange(later.id),
        ],
      ),
    ];
  }

  // ─── Invalid range ────────────────────────────────────────────────────────

  List<FrontingFixPlan> _plansForInvalidRange(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    final involved = _sessionsFor(issue, sessions);
    if (involved.isEmpty) return [];

    final session = involved.first;

    final swapPlan = FrontingFixPlan(
      id: '${issue.id}-swap',
      type: FrontingFixType.swapStartEnd,
      title: 'Swap start and end',
      description: 'Swap the reversed start and end times to make the session valid.',
      affectedSessionIds: [session.id],
      changes: [
        UpdateSessionChange(
          sessionId: session.id,
          patch: FrontingSessionPatch(
            start: session.end, // was end, now start
            end: session.start, // was start, now end
          ),
        ),
      ],
    );

    final deletePlan = FrontingFixPlan(
      id: '${issue.id}-delete',
      type: FrontingFixType.deleteSession,
      title: 'Delete session',
      description: 'Remove the session with the invalid time range.',
      affectedSessionIds: [session.id],
      changes: [DeleteSessionChange(session.id)],
    );

    return [swapPlan, deletePlan];
  }

  // ─── Future session ───────────────────────────────────────────────────────

  List<FrontingFixPlan> _plansForFutureSession(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sessions,
  ) {
    final involved = _sessionsFor(issue, sessions);
    if (involved.isEmpty) return [];

    final session = involved.first;
    final now = DateTime.now();

    return [
      FrontingFixPlan(
        id: '${issue.id}-clamp',
        type: FrontingFixType.clampToNow,
        title: 'Clamp to now',
        description: 'Move the session start time to the current time.',
        affectedSessionIds: [session.id],
        changes: [
          UpdateSessionChange(
            sessionId: session.id,
            patch: FrontingSessionPatch(
              start: now,
              clearEnd: true, // make active (end = null)
            ),
          ),
        ],
      ),
    ];
  }

  // ─── Preview ─────────────────────────────────────────────────────────────

  (String, List<String>) _previewContent(FrontingFixPlan plan) {
    switch (plan.type) {
      case FrontingFixType.mergeAdjacent:
        final deletes = plan.changes.whereType<DeleteSessionChange>().length;
        final updates = plan.changes.whereType<UpdateSessionChange>().length;
        return (
          'Merge ${plan.affectedSessionIds.length} sessions into one.',
          [
            if (updates > 0) 'Update $updates session${updates > 1 ? "s" : ""} with combined time range.',
            if (deletes > 0) 'Delete $deletes duplicate session${deletes > 1 ? "s" : ""}.',
            if (plan.changes.whereType<UpdateSessionChange>().any((u) => u.patch.notes != null))
              'Combine notes from both sessions.',
          ],
        );

      case FrontingFixType.trimEarlier:
        return (
          'Trim the earlier session to resolve the overlap.',
          [
            'Shorten the earlier session\'s end time to where the later session begins.',
            'No data is deleted.',
          ],
        );

      case FrontingFixType.trimLater:
        return (
          'Trim the later session to resolve the overlap.',
          [
            'Move the later session\'s start time to where the earlier session ends.',
            'No data is deleted.',
          ],
        );

      case FrontingFixType.fillGapWithUnknown:
        return (
          'Fill the gap with an Unknown fronter session.',
          [
            'Create a new session with no assigned member.',
            'The session will span the entire gap.',
          ],
        );

      case FrontingFixType.leaveGap:
        return (
          'Leave the gap as-is.',
          [
            'No changes will be made to the timeline.',
            'The gap will remain unrecorded.',
          ],
        );

      case FrontingFixType.deleteDuplicate:
        return (
          'Delete the less-complete duplicate session.',
          [
            'The session with fewer notes, lower confidence, or fewer co-fronters will be removed.',
            'The more complete session will be kept.',
          ],
        );

      case FrontingFixType.swapStartEnd:
        return (
          'Swap the start and end times to fix the invalid range.',
          [
            'The start and end times will be exchanged.',
            'No other data will be changed.',
          ],
        );

      case FrontingFixType.deleteSession:
        return (
          'Delete the session with the invalid time range.',
          [
            'The session will be permanently removed.',
            'This cannot be undone.',
          ],
        );

      case FrontingFixType.clampToNow:
        return (
          'Move the session start time to now.',
          [
            'The start time will be set to the current time.',
            'The session will become active (no end time).',
          ],
        );

      case FrontingFixType.splitIntoCofronting:
        return (
          'Split into co-fronting sessions.',
          [
            'The overlapping sessions will be converted to a single co-fronting session.',
          ],
        );

      case FrontingFixType.markForManualReview:
        return (
          'Mark for manual review.',
          [
            'The session will be flagged for later review.',
            'No automatic changes will be made.',
          ],
        );
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<FrontingSessionSnapshot> _sessionsFor(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> all,
  ) {
    final ids = issue.sessionIds.toSet();
    return all.where((s) => ids.contains(s.id)).toList();
  }

  /// Higher score = more data = more valuable session to keep.
  int _dataScore(FrontingSessionSnapshot s) {
    var score = 0;
    if (s.notes != null && s.notes!.isNotEmpty) score += 2;
    if (s.confidenceIndex != null) score += 1;
    score += s.coFronterIds.length;
    return score;
  }

  /// Returns the later of two nullable DateTimes. Null means "still active",
  /// which is always considered later than any concrete end time.
  DateTime? _laterDateTime(DateTime? a, DateTime? b) {
    if (a == null || b == null) return null; // null = active session
    return a.isAfter(b) ? a : b;
  }
}
