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
  ///
  /// Used for same-member self-overlap resolution and sleep↔front cross-type
  /// overlaps. Cross-member overlaps between different normal fronting sessions
  /// are valid by design and should not be passed to this method.
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

  // ── resolveAllOverlaps ──────────────────────────────────────────────────

  /// Apply the chosen [resolution] to all [overlaps] for [edited].
  /// Overlaps are processed in chronological order.
  /// After each resolution, the edited session's effective boundaries are
  /// updated for subsequent computations.
  ///
  /// In the per-member model only [OverlapResolution.trim] and
  /// [OverlapResolution.cancel] are valid. Overlaps passed here should be
  /// same-member self-overlaps or sleep↔front cross-type overlaps only.
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
      final result = computeTrimChanges(currentEdited, overlap);
      allChanges.addAll(result.changes);
      // If the edited session itself was updated as a side effect, track it.
      if (result.updatedEdited != null) {
        currentEdited = result.updatedEdited!;
      }
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

}
