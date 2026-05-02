/// Adjacent-merge pass for per-member fronting rows.
///
/// Spec: `docs/plans/fronting-per-member-sessions.md` §2.1.
///
/// Run after the per-member fan-out (migration §4.1 step 4 and the
/// PRISM1 rescue importer §4.7) to collapse adjacent same-member rows
/// whose `end_time` exactly matches the next row's `start_time`. Those
/// boundaries existed in the old shape only because a co-fronter
/// joined or left — under the per-member abstraction they are
/// arbitrary cosmetic artifacts that fragment a continuously-fronting
/// host into dozens of short rows (the "24/7 host pattern" the spec
/// explicitly called out as broken in the old model).
///
/// Both call sites (the destructive migration transaction and the
/// rescue import transaction) issue writes through
/// [FrontingSessionRepository] so sync ops emit (or, in the migration
/// case, are suppressed by the surrounding `SyncRecordMixin.suppress`
/// — same as the rest of the migration body).
library;

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';

/// Walks each [memberIds] member's normal (non-sleep) active sessions
/// in `start_time ASC` order and, while any merge fires, collapses
/// pairs whose `end_time == nextStartTime` into one continuous row.
///
/// Merge rules:
///   - The earlier row is updated in place (its id stays stable).
///   - The later row is soft-deleted via [FrontingSessionRepository.deleteSession].
///   - `end_time` becomes the later row's end (may be null for
///     open-ended currently-fronting rows).
///   - `notes` concatenates with `\n\n` when both sides are non-null;
///     otherwise the non-null one wins (or null if both are null).
///   - `confidence` takes the max ordinal when both sides are
///     non-null; otherwise the non-null one wins.
///
/// Sleep rows (`SessionType.sleep`) are NEVER merged — they are
/// already single-member-or-null in the new shape, and the migration
/// doesn't fan them out. The repository query
/// (`getSessionsForMember`) already excludes them.
///
/// PK-linked rows (rows with a non-null `pluralkitUuid`) are also
/// skipped: their identity is the deterministic
/// `derivePkSessionId(switch_uuid, member_pk_uuid)`, and the live PK
/// API diff sweep relies on each (switch, member) pair surviving as
/// its own row so a re-import can correct boundaries via field-LWW.
/// Collapsing them would erase the ids the diff sweep expects to find
/// (and would eat the lossy-boundary recovery story the rescue
/// importer's spec §4.7 explicitly relies on).
///
/// Iterates per member until no more merges fire so cascading runs of
/// adjacent rows (A→B→C all touching) collapse to a single row in one
/// invocation.
///
/// Returns the total number of merges performed across all members
/// (i.e., the count of rows that were soft-deleted as their data was
/// folded into an earlier row). Useful for migration / import result
/// counters.
///
/// [excludeMemberIds] is consulted before any per-member merge runs.
/// Member ids in that set are skipped entirely. The PRISM1 rescue
/// importer (§4.7) passes the Unknown sentinel id here so adjacent
/// orphan-rescue rows stay distinct rather than being collapsed into
/// one giant Unknown-sentinel session that loses per-row notes /
/// confidence identity (review finding #42).
Future<int> mergeAdjacentSameMemberRows(
  FrontingSessionRepository repo, {
  required Iterable<String> memberIds,
  Set<String> excludeMemberIds = const {},
}) async {
  var merges = 0;
  for (final memberId in memberIds) {
    if (memberId.isEmpty) continue;
    if (excludeMemberIds.contains(memberId)) continue;
    // Re-fetch on each pass so cascading merges see the updated
    // earlier-row end_time without us having to maintain a parallel
    // in-memory model of the table.
    var madeProgress = true;
    while (madeProgress) {
      madeProgress = false;
      final all = await repo.getSessionsForMember(memberId);
      // Skip PK-linked rows: their deterministic `(switch, member)` id
      // is what the diff sweep keys off for boundary correction;
      // collapsing them would erase the rows the API expects to find.
      final rows = all
          .where((r) => r.pluralkitUuid == null || r.pluralkitUuid!.isEmpty)
          .toList();
      // getSessionsForMember orders by start_time DESC; flip to ASC
      // so adjacency is i / i+1 from earlier to later.
      rows.sort((a, b) => a.startTime.compareTo(b.startTime));
      for (var i = 0; i < rows.length - 1; i++) {
        final a = rows[i];
        final b = rows[i + 1];
        // Only merge on an exact boundary. A few-second tolerance
        // would over-merge — the migration is operating on rows
        // derived from the user's own session boundaries, so anything
        // non-exact represents an intentional gap.
        if (a.endTime == null) continue; // open-ended earlier row → no boundary
        if (a.endTime != b.startTime) continue;
        await repo.updateSession(
          a.copyWith(
            endTime: b.endTime,
            notes: _mergeNotes(a.notes, b.notes),
            confidence: _mergeConfidence(a.confidence, b.confidence),
          ),
        );
        await repo.deleteSession(b.id);
        merges++;
        madeProgress = true;
        // Restart the per-member loop after a merge: the row indices
        // have shifted and a fresh fetch keeps the logic simple.
        break;
      }
    }
  }
  return merges;
}

String? _mergeNotes(String? a, String? b) {
  final aFilled = a != null && a.isNotEmpty;
  final bFilled = b != null && b.isNotEmpty;
  if (aFilled && bFilled) return '$a\n\n$b';
  if (aFilled) return a;
  if (bFilled) return b;
  return null;
}

FrontConfidence? _mergeConfidence(FrontConfidence? a, FrontConfidence? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.index >= b.index ? a : b;
}
