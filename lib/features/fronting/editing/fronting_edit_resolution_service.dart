import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

/// Sentinel DateTime used for active sessions in overlap calculations.
final _activeSentinel = DateTime(9999);

/// Returns the effective end of a snapshot for comparison purposes.
/// Active sessions (null end) are treated as far-future.
DateTime _effectiveEnd(FrontingSessionSnapshot s) => s.end ?? _activeSentinel;

// ── TrimResult ─────────────────────────────────────────────────────────────

class TrimResult {
  final List<FrontingSessionChange> changes;
  final bool wouldDeleteConflicting;
  final FrontingSessionSnapshot? updatedEdited;

  const TrimResult({
    required this.changes,
    this.wouldDeleteConflicting = false,
    this.updatedEdited,
  });
}

// ── Service ────────────────────────────────────────────────────────────────

class FrontingEditResolutionService {
  const FrontingEditResolutionService();

  // ── computeTrimChanges ──────────────────────────────────────────────────

  /// Compute changes to trim [conflicting] around [edited].
  /// The edited session takes priority.
  TrimResult computeTrimChanges(
    FrontingSessionSnapshot edited,
    FrontingSessionSnapshot conflicting,
  ) {
    final editedEnd = _effectiveEnd(edited);
    final conflictingEnd = _effectiveEnd(conflicting);

    // Full containment: edited fully contains conflicting
    if (!edited.start.isAfter(conflicting.start) && !editedEnd.isBefore(conflictingEnd)) {
      return TrimResult(
        changes: [DeleteSessionChange(conflicting.id)],
        wouldDeleteConflicting: true,
      );
    }

    // Partial overlap: edited starts first (edited.start <= conflicting.start)
    // conflicting.start is inside edited, trim conflicting start to edited.end
    if (!edited.start.isAfter(conflicting.start)) {
      final newStart = edited.end!; // edited.end is real (not active) here
      // Would trim produce zero or negative duration?
      if (!newStart.isBefore(conflictingEnd)) {
        return TrimResult(
          changes: [DeleteSessionChange(conflicting.id)],
          wouldDeleteConflicting: true,
        );
      }
      return TrimResult(
        changes: [
          UpdateSessionChange(
            sessionId: conflicting.id,
            patch: FrontingSessionPatch(start: newStart),
          ),
        ],
        wouldDeleteConflicting: false,
      );
    }

    // Partial overlap: conflicting starts first (conflicting.start < edited.start)
    // conflicting.end is inside edited, trim conflicting end to edited.start
    final newEnd = edited.start;
    // Would trim produce zero or negative duration?
    if (!conflicting.start.isBefore(newEnd)) {
      return TrimResult(
        changes: [DeleteSessionChange(conflicting.id)],
        wouldDeleteConflicting: true,
      );
    }
    return TrimResult(
      changes: [
        UpdateSessionChange(
          sessionId: conflicting.id,
          patch: FrontingSessionPatch(end: newEnd),
        ),
      ],
      wouldDeleteConflicting: false,
    );
  }

  // ── computeCoFrontingChanges ────────────────────────────────────────────

  /// Split edited and conflicting sessions into segments around the overlap:
  ///   - Pre-overlap solo segment
  ///   - Overlap co-fronting segment
  ///   - Post-overlap solo segment
  List<FrontingSessionChange> computeCoFrontingChanges(
    FrontingSessionSnapshot edited,
    FrontingSessionSnapshot conflicting,
  ) {
    final editedEnd = _effectiveEnd(edited);
    final conflictingEnd = _effectiveEnd(conflicting);

    final overlapStart =
        edited.start.isAfter(conflicting.start) ? edited.start : conflicting.start;
    final overlapEndSentinel =
        editedEnd.isBefore(conflictingEnd) ? editedEnd : conflictingEnd;

    // For co-front segment: if either was active and the overlap reaches their
    // end, that segment should remain active (null end).
    final bool coFrontIsActive =
        (edited.end == null && overlapEndSentinel == editedEnd) ||
        (conflicting.end == null && overlapEndSentinel == conflictingEnd);
    final DateTime? coFrontEnd = coFrontIsActive ? null : overlapEndSentinel;

    // Build merged co-fronter list: all from both sessions + conflicting.memberId,
    // minus edited.memberId, no duplicates.
    final mergedCoFronters = <String>{
      ...edited.coFronterIds,
      ...conflicting.coFronterIds,
      if (conflicting.memberId != null) conflicting.memberId!,
    }..remove(edited.memberId);

    // Higher confidence wins (by enum index).
    final int? mergedConfidence = _higherConfidence(
      edited.confidenceIndex,
      conflicting.confidenceIndex,
    );

    // Join non-null, non-empty notes with " | ".
    final mergedNotes = _joinNotes(edited.notes, conflicting.notes);

    final changes = <FrontingSessionChange>[];

    final editedStartsFirst = !edited.start.isAfter(conflicting.start);
    final fullContainment =
        !edited.start.isAfter(conflicting.start) && !editedEnd.isBefore(conflictingEnd);

    if (fullContainment) {
      // Update edited to end at overlapStart (if that produces a valid segment)
      if (edited.start.isBefore(overlapStart)) {
        changes.add(
          UpdateSessionChange(
            sessionId: edited.id,
            patch: FrontingSessionPatch(end: overlapStart),
          ),
        );
      }

      // Create co-front segment
      changes.add(
        CreateSessionChange(
          FrontingSessionDraft(
            memberId: edited.memberId,
            start: overlapStart,
            end: coFrontEnd,
            coFronterIds: mergedCoFronters.toList(),
            notes: mergedNotes,
            confidenceIndex: mergedConfidence,
          ),
        ),
      );

      // Create solo edited segment after the overlap, if edited extends past conflicting
      final postStart = coFrontIsActive ? null : overlapEndSentinel;
      if (postStart != null && edited.end != null && postStart.isBefore(edited.end!)) {
        changes.add(
          CreateSessionChange(
            FrontingSessionDraft(
              memberId: edited.memberId,
              start: postStart,
              end: edited.end,
              coFronterIds: edited.coFronterIds,
              notes: edited.notes,
              confidenceIndex: edited.confidenceIndex,
            ),
          ),
        );
      }

      // Delete conflicting
      changes.add(DeleteSessionChange(conflicting.id));
    } else if (editedStartsFirst) {
      // Edited starts first: partial overlap, conflicting extends past edited
      // Update edited to end at overlapStart
      changes.add(
        UpdateSessionChange(
          sessionId: edited.id,
          patch: FrontingSessionPatch(end: overlapStart),
        ),
      );

      // Create co-front segment (overlapStart to overlapEnd)
      changes.add(
        CreateSessionChange(
          FrontingSessionDraft(
            memberId: edited.memberId,
            start: overlapStart,
            end: coFrontEnd,
            coFronterIds: mergedCoFronters.toList(),
            notes: mergedNotes,
            confidenceIndex: mergedConfidence,
          ),
        ),
      );

      // Update conflicting to start at overlapEnd
      if (!coFrontIsActive) {
        changes.add(
          UpdateSessionChange(
            sessionId: conflicting.id,
            patch: FrontingSessionPatch(start: overlapEndSentinel),
          ),
        );
      }
    } else {
      // Conflicting starts first: partial overlap, edited extends past conflicting
      // Update conflicting to end at overlapStart
      changes.add(
        UpdateSessionChange(
          sessionId: conflicting.id,
          patch: FrontingSessionPatch(end: overlapStart),
        ),
      );

      // Create co-front segment (overlapStart to overlapEnd)
      changes.add(
        CreateSessionChange(
          FrontingSessionDraft(
            memberId: edited.memberId,
            start: overlapStart,
            end: coFrontEnd,
            coFronterIds: mergedCoFronters.toList(),
            notes: mergedNotes,
            confidenceIndex: mergedConfidence,
          ),
        ),
      );

      // Update edited to start at overlapEnd
      if (!coFrontIsActive) {
        changes.add(
          UpdateSessionChange(
            sessionId: edited.id,
            patch: FrontingSessionPatch(start: overlapEndSentinel),
          ),
        );
      }
    }

    return changes;
  }

  // ── resolveAllOverlaps ──────────────────────────────────────────────────

  /// Apply the chosen [resolution] to all [overlaps] for [edited].
  /// Overlaps are processed in chronological order.
  /// After each resolution, the edited session's effective boundaries are
  /// updated for subsequent computations.
  List<FrontingSessionChange> resolveAllOverlaps({
    required FrontingSessionSnapshot edited,
    required List<FrontingSessionSnapshot> overlaps,
    required OverlapResolution resolution,
  }) {
    if (resolution == OverlapResolution.cancel) return [];

    // Sort overlaps by start time
    final sorted = [...overlaps]..sort((a, b) => a.start.compareTo(b.start));

    final allChanges = <FrontingSessionChange>[];
    var currentEdited = edited;

    for (final overlap in sorted) {
      final List<FrontingSessionChange> stepChanges;

      if (resolution == OverlapResolution.trim) {
        final result = computeTrimChanges(currentEdited, overlap);
        stepChanges = result.changes;
        // If the edited session itself was updated as a side effect, track it.
        if (result.updatedEdited != null) {
          currentEdited = result.updatedEdited!;
        }
      } else {
        // makeCoFronting
        stepChanges = computeCoFrontingChanges(currentEdited, overlap);
        // After co-fronting, the edited session boundaries may shift.
        // Extract the updated edited boundaries from the changes.
        for (final change in stepChanges) {
          if (change is UpdateSessionChange &&
              change.sessionId == currentEdited.id) {
            currentEdited = _applyPatchToSnapshot(currentEdited, change.patch);
          }
        }
      }

      allChanges.addAll(stepChanges);
    }

    return allChanges;
  }

  // ── computeDeleteChanges ────────────────────────────────────────────────

  /// Compute changes for deleting [context.session] using [strategy].
  List<FrontingSessionChange> computeDeleteChanges(
    FrontingDeleteContext context,
    FrontingDeleteStrategy strategy,
  ) {
    final session = context.session;

    switch (strategy) {
      case FrontingDeleteStrategy.extendPrevious:
        final previous = context.previous!;
        final bool sessionIsActive = session.end == null;
        return [
          UpdateSessionChange(
            sessionId: previous.id,
            patch: sessionIsActive
                ? const FrontingSessionPatch(clearEnd: true)
                : FrontingSessionPatch(end: session.end),
          ),
          DeleteSessionChange(session.id),
        ];

      case FrontingDeleteStrategy.extendNext:
        final next = context.next!;
        return [
          UpdateSessionChange(
            sessionId: next.id,
            patch: FrontingSessionPatch(start: session.start),
          ),
          DeleteSessionChange(session.id),
        ];

      case FrontingDeleteStrategy.splitBetweenNeighbors:
        final previous = context.previous!;
        final next = context.next!;
        // session.end must be non-null (checked in availableStrategies)
        final midpointMs = session.start.millisecondsSinceEpoch +
            (session.end!.millisecondsSinceEpoch -
                    session.start.millisecondsSinceEpoch) ~/
                2;
        final midpoint =
            DateTime.fromMillisecondsSinceEpoch(midpointMs, isUtc: session.start.isUtc);
        return [
          UpdateSessionChange(
            sessionId: previous.id,
            patch: FrontingSessionPatch(end: midpoint),
          ),
          UpdateSessionChange(
            sessionId: next.id,
            patch: FrontingSessionPatch(start: midpoint),
          ),
          DeleteSessionChange(session.id),
        ];

      case FrontingDeleteStrategy.convertToUnknown:
        return [
          UpdateSessionChange(
            sessionId: session.id,
            patch: const FrontingSessionPatch(
              clearMemberId: true,
              coFronterIds: [],
            ),
          ),
        ];

      case FrontingDeleteStrategy.leaveGap:
        return [DeleteSessionChange(session.id)];
    }
  }

  // ── computeGapFillChanges ───────────────────────────────────────────────

  /// Create Unknown (null memberId) sessions to fill each [gap].
  List<FrontingSessionChange> computeGapFillChanges(List<GapInfo> gaps) {
    return gaps
        .map(
          (gap) => CreateSessionChange(
            FrontingSessionDraft(
              memberId: null,
              start: gap.start,
              end: gap.end,
            ),
          ),
        )
        .toList();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Returns the higher confidence index, or null if both are null.
  int? _higherConfidence(int? a, int? b) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  /// Join two nullable notes with " | ", skipping nulls/empty strings.
  String? _joinNotes(String? a, String? b) {
    final parts = [
      if (a != null && a.isNotEmpty) a,
      if (b != null && b.isNotEmpty) b,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' | ');
  }

  /// Apply a patch to a snapshot to produce a new snapshot for boundary tracking.
  FrontingSessionSnapshot _applyPatchToSnapshot(
    FrontingSessionSnapshot snap,
    FrontingSessionPatch patch,
  ) {
    return FrontingSessionSnapshot(
      id: snap.id,
      memberId: patch.clearMemberId ? null : (patch.memberId ?? snap.memberId),
      start: patch.start ?? snap.start,
      end: patch.clearEnd ? null : (patch.end ?? snap.end),
      coFronterIds: patch.coFronterIds ?? snap.coFronterIds,
      notes: patch.notes ?? snap.notes,
      confidenceIndex: patch.confidenceIndex ?? snap.confidenceIndex,
    );
  }
}
