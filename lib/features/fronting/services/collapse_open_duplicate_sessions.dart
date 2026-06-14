/// Open-session collapse pass for per-member fronting rows, mirroring
/// [FrontingMutationService._collapseOpenDuplicates].
///
/// The importer needs its own copy: a backup taken from a device that
/// accumulated duplicate opens (close-ops lost in the relay-pruning era, or rows
/// from a pre-invariant build) restores every one through the invariant-free
/// [FrontingSessionRepository.createSession], and the startup repair only runs
/// on a sync-healthy device — a standalone import never reaches it.
///
/// Unlike [mergeAdjacentSameMemberRows], PK-linked rows are NOT skipped: merging
/// would erase the deterministic `(switch, member)` id, but closing only sets
/// `end_time` and keeps the id for the PK diff sweep to re-bound via field-LWW.
library;

import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';

/// Collapses duplicate open sessions for each member in [memberIds] to one,
/// keeping the most-recently started and closing earlier opens at their next
/// session's start. Writes through [FrontingSessionRepository.endSession]; the
/// caller (running under `SyncRecordMixin.suppress`) re-emits the returned ids.
///
/// Returns the set of session ids whose `end_time` this closed.
Future<Set<String>> collapseOpenDuplicateSessions(
  FrontingSessionRepository repo, {
  required Iterable<String> memberIds,
  Set<String> excludeMemberIds = const {},
}) async {
  final closed = <String>{};
  final seen = <String>{};
  for (final memberId in memberIds) {
    if (memberId.isEmpty || excludeMemberIds.contains(memberId)) continue;
    if (!seen.add(memberId)) continue;

    // getSessionsForMember returns normal (non-sleep), non-deleted rows; sort
    // ASC so "next session" is a forward scan and opens.last is most-recent.
    final sorted = [...await repo.getSessionsForMember(memberId)]
      ..sort((a, b) {
        final byStart = a.startTime.compareTo(b.startTime);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    final opens = [
      for (final s in sorted)
        if (s.endTime == null) s,
    ];
    if (opens.length <= 1) continue;

    final keep = opens.last;
    for (final open in opens) {
      if (open.id == keep.id) continue;
      // Close at the start of the next session that begins after this open —
      // the moment the member's next (duplicate) front took over.
      DateTime? nextStart;
      for (final other in sorted) {
        if (other.id == open.id) continue;
        if (other.startTime.isAfter(open.startTime) &&
            (nextStart == null || other.startTime.isBefore(nextStart))) {
          nextStart = other.startTime;
        }
      }
      final end = nextStart ?? keep.startTime;
      final safeEnd = end.isAfter(open.startTime)
          ? end
          : open.startTime.add(const Duration(seconds: 1));
      await repo.endSession(open.id, safeEnd);
      closed.add(open.id);
    }
  }
  return closed;
}
