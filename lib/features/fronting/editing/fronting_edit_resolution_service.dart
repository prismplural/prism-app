import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
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
  /// Used for same-member, same-type self-overlap resolution. Cross-member
  /// overlaps between different normal fronting sessions, and cross-TYPE
  /// overlaps (sleep vs. normal fronting), are valid by design and must not be
  /// passed to this method — see [resolveAllOverlaps], which drops cross-type
  /// overlaps defensively.
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
  /// same-member, same-type self-overlaps only.
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
      // Defense in depth: never trim across session types. Sleep and normal
      // fronting are parallel timelines, so trimming one against the other is
      // exactly the sleep-data-loss bug — an open-ended front would delete the
      // entire sleep history. The edit guard already filters these out; this
      // guarantees no caller can route a cross-type overlap into a delete.
      if (overlap.sessionType != edited.sessionType) continue;
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
        // Write the canonical Unknown sentinel id directly rather than
        // clearing memberId.  Routing through the sentinel keeps the
        // session participating in member totals, percentages, and
        // pair-overlap input — and matches what the "Front as Unknown"
        // sheet emits, so converted rows are indistinguishable from
        // intentionally-Unknown rows.  The change executor calls
        // `ensureUnknownSentinelMember()` before applying any change
        // that references this id so the foreign-key target exists
        // locally.
        return [
          UpdateSessionChange(
            sessionId: session.id,
            patch: FrontingSessionPatch(
              memberId: unknownSentinelMemberId,
            ),
          ),
        ];

      case FrontingDeleteStrategy.leaveGap:
        return [DeleteSessionChange(session.id)];
    }
  }

  // ── computeDeletePeriodChanges ──────────────────────────────────────────

  /// Changes for deleting the period [context] under [strategy].
  ///
  /// Sessions in the slice are trimmed at the boundaries, split if they
  /// straddle both, or deleted if fully contained. The strategy then
  /// fills the cleared slice (extend the predecessor, drop in an
  /// Unknown row, or leave a gap).
  ///
  /// Comment routing is decided up front so trim/split patches can
  /// carry the reparent target:
  ///
  /// * `convertToUnknown` reuses a contained session as the Unknown row
  ///   when possible (so its per-session comments stay attached) and
  ///   otherwise emits a fresh Create with a preset id first; either
  ///   way every other trim/split routes its orphans to that id.
  /// * `extendPrevious` routes to whichever session ends up covering
  ///   the slice — a straddle-start being extended, a both-straddler
  ///   left intact, or the first touching previousSession.
  /// * `leaveGap` drops orphans.
  ///
  /// Open-ended sessions inside an ongoing period get special handling:
  /// trimming start to `periodEnd` would create a fresh `[now, null]`
  /// row that silently undoes the delete, so they're either deleted
  /// (when contained) or closed at `periodStart` (when straddling).
  List<FrontingSessionChange> computeDeletePeriodChanges(
    FrontingDeletePeriodContext context,
    FrontingDeleteStrategy strategy,
  ) {
    final pStart = context.periodStart;
    final pEnd = context.periodEnd;
    final changes = <FrontingSessionChange>[];

    // Deterministic order so two synced devices pick the same
    // survivor/target. Without this, per-field LWW after sync would
    // resolve {Update memberId, Delete other} pairs into both rows
    // deleted — the Unknown the user asked for would disappear.
    final orderedInPeriod = [...context.sessionsInPeriod]..sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });

    String? unknownSurvivorId;
    String? unknownPresetId;
    String? sliceCommentTargetId;
    if (strategy == FrontingDeleteStrategy.convertToUnknown) {
      for (final s in orderedInPeriod) {
        final isOpen = s.end == null;
        final effectiveEnd = s.end ?? _activeSentinel;
        final startsBefore = s.start.isBefore(pStart);
        final endsAfter = effectiveEnd.isAfter(pEnd);
        final fullyContained = !startsBefore && !endsAfter;
        final ongoingContainedOpen =
            context.isOngoing && isOpen && !startsBefore;
        if (fullyContained || ongoingContainedOpen) {
          unknownSurvivorId = s.id;
          break;
        }
      }
      if (unknownSurvivorId != null) {
        sliceCommentTargetId = unknownSurvivorId;
      } else {
        // Create the Unknown row first so its session exists when later
        // trims reparent into it.
        unknownPresetId = const Uuid().v4();
        sliceCommentTargetId = unknownPresetId;
        changes.add(
          CreateSessionChange(
            FrontingSessionDraft(
              memberId: unknownSentinelMemberId,
              start: pStart,
              end: context.isOngoing ? null : pEnd,
              presetId: unknownPresetId,
            ),
          ),
        );
      }
    } else if (strategy == FrontingDeleteStrategy.extendPrevious) {
      // Whatever session ends up covering the slice afterwards is a
      // valid target: a straddle-start (extended to pEnd), a both-
      // straddler (left intact), or — failing those — the first touching
      // previousSession. Ongoing-open straddlers are skipped: they're
      // left as-is for the special case below, not extended.
      for (final s in orderedInPeriod) {
        final isOpen = s.end == null;
        if (context.isOngoing && isOpen) continue;
        final effectiveEnd = s.end ?? _activeSentinel;
        final startsBefore = s.start.isBefore(pStart);
        final endsAfter = effectiveEnd.isAfter(pEnd);
        if (startsBefore && !endsAfter) {
          sliceCommentTargetId = s.id;
          break;
        }
        if (startsBefore && endsAfter) {
          sliceCommentTargetId = s.id;
          break;
        }
      }
      if (sliceCommentTargetId == null &&
          context.previousSessions.isNotEmpty) {
        final orderedPrevious = [...context.previousSessions]..sort((a, b) {
          final c = a.start.compareTo(b.start);
          if (c != 0) return c;
          return a.id.compareTo(b.id);
        });
        sliceCommentTargetId = orderedPrevious.first.id;
      }
    }

    for (final s in context.sessionsInPeriod) {
      if (s.id == unknownSurvivorId) {
        changes.add(
          UpdateSessionChange(
            sessionId: s.id,
            patch: FrontingSessionPatch(
              memberId: unknownSentinelMemberId,
              start: pStart,
              end: context.isOngoing ? null : pEnd,
              clearEnd: context.isOngoing,
            ),
          ),
        );
        continue;
      }

      final isOpen = s.end == null;
      final effectiveEnd = s.end ?? _activeSentinel;
      final startsBefore = s.start.isBefore(pStart);
      final endsAfter = effectiveEnd.isAfter(pEnd);
      final fullyContained = !startsBefore && !endsAfter;

      // Open inside an ongoing period: can't trim start to pEnd without
      // producing a fresh `[now, null]` row that silently undoes the
      // delete. Close at pStart for both-straddlers (no post-period
      // tail to recreate), delete the rest outright.
      if (context.isOngoing && isOpen) {
        if (startsBefore) {
          if (strategy != FrontingDeleteStrategy.extendPrevious) {
            changes.add(
              UpdateSessionChange(
                sessionId: s.id,
                patch: FrontingSessionPatch(
                  end: pStart,
                  dropOrphanedComments: sliceCommentTargetId == null,
                  reparentOrphansToSessionId: sliceCommentTargetId,
                ),
              ),
            );
          }
        } else {
          changes.add(DeleteSessionChange(s.id));
        }
        continue;
      }

      if (fullyContained) {
        changes.add(DeleteSessionChange(s.id));
        continue;
      }

      if (startsBefore && endsAfter) {
        // Both-straddler: under extendPrevious the session already
        // covers the slice as-is. Otherwise split at the boundaries.
        if (strategy == FrontingDeleteStrategy.extendPrevious) {
          continue;
        }
        changes.add(
          UpdateSessionChange(
            sessionId: s.id,
            patch: FrontingSessionPatch(end: pStart),
          ),
        );
        changes.add(
          CreateSessionChange(
            FrontingSessionDraft(
              memberId: s.memberId,
              start: pEnd,
              end: s.end,
              notes: s.notes,
              confidenceIndex: s.confidenceIndex,
              sessionType: s.sessionType,
              quality: s.quality,
              isHealthKitImport: s.isHealthKitImport,
              // Same v5 derivation FrontingMutationService.splitSession
              // uses so two synced devices converge on the same right-
              // half row.
              presetId: const Uuid().v5(
                splitNamespace,
                '${s.id}:${pEnd.toUtc().toIso8601String()}',
              ),
              splitFromSessionId: s.id,
              sliceReparentToSessionId: sliceCommentTargetId,
            ),
          ),
        );
        continue;
      }

      if (startsBefore) {
        // Straddle-start only.
        if (strategy == FrontingDeleteStrategy.extendPrevious) {
          changes.add(
            UpdateSessionChange(
              sessionId: s.id,
              patch: context.isOngoing
                  ? const FrontingSessionPatch(clearEnd: true)
                  : FrontingSessionPatch(end: pEnd),
            ),
          );
        } else {
          changes.add(
            UpdateSessionChange(
              sessionId: s.id,
              patch: FrontingSessionPatch(
                end: pStart,
                dropOrphanedComments: sliceCommentTargetId == null,
                reparentOrphansToSessionId: sliceCommentTargetId,
              ),
            ),
          );
        }
        continue;
      }

      // Straddle-end only (open-inside-ongoing already handled above).
      changes.add(
        UpdateSessionChange(
          sessionId: s.id,
          patch: FrontingSessionPatch(
            start: pEnd,
            dropOrphanedComments: sliceCommentTargetId == null,
            reparentOrphansToSessionId: sliceCommentTargetId,
          ),
        ),
      );
    }

    switch (strategy) {
      case FrontingDeleteStrategy.extendPrevious:
        for (final p in context.previousSessions) {
          changes.add(
            UpdateSessionChange(
              sessionId: p.id,
              patch: context.isOngoing
                  ? const FrontingSessionPatch(clearEnd: true)
                  : FrontingSessionPatch(end: pEnd),
            ),
          );
        }
        break;

      case FrontingDeleteStrategy.convertToUnknown:
      case FrontingDeleteStrategy.leaveGap:
      case FrontingDeleteStrategy.extendNext:
      case FrontingDeleteStrategy.splitBetweenNeighbors:
        // convertToUnknown emitted the survivor update or up-front
        // Create above; nothing more to do here. extendNext and
        // splitBetweenNeighbors aren't surfaced by availableStrategies
        // today — fall through with leaveGap-style behavior.
        break;
    }

    return changes;
  }

  // ── computeGapFillChanges ───────────────────────────────────────────────

  /// Create Unknown sentinel sessions to fill each [gap].
  ///
  /// Writes [unknownSentinelMemberId] directly rather than null so that
  /// gap-fill rows participate in analytics totals on the same footing as
  /// the "Front as Unknown" sheet's output.  The change executor lazily
  /// creates the sentinel member entity before applying these changes.
  List<FrontingSessionChange> computeGapFillChanges(List<GapInfo> gaps) {
    return gaps
        .map(
          (gap) => CreateSessionChange(
            FrontingSessionDraft(
              memberId: unknownSentinelMemberId,
              start: gap.start,
              end: gap.end,
            ),
          ),
        )
        .toList();
  }

}
