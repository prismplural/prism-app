/// Cursor value object for PluralKit switch-history pagination (WS3 step 1).
///
/// PK paginates `/systems/{id}/switches` newest-first via the `before` query
/// param, returning at most 100 switches per page. The diff-sweep importer
/// stores its resume position as `(timestamp, switchId)` in
/// `pluralkit_sync_state` and walks backwards from "now" until it crosses
/// the previously-seen boundary.
///
/// The single-point comparison `if (sw.timestamp == cursorTs && sw.id == cursorId)`
/// is wrong: PluralKit can report multiple switches at the same timestamp
/// (rare, but possible with bulk imports / clock skew on the PK side), and
/// equality only stops at the *exact* cursor switch — switches at the same
/// timestamp but a different id were silently re-processed AFTER the cursor
/// boundary was reached. Worse, on the next sweep they were filtered out
/// because the cursor advanced past them.
///
/// This value object encapsulates the lexicographic `(timestamp, switchId)`
/// comparison so both call sites (the loop break check and the page
/// progress guard) use the same rule.
///
/// See:
/// - `docs/analysis/fronting-per-member-sessions-review-2026-04-30.md` finding #6
/// - `docs/analysis/fronting-per-member-sessions-remediation-plan-2026-04-30.md`
///   Workstream 3 steps 1, 2
library;

/// Resume cursor for incremental PK switch-history pagination.
///
/// A switch `(ts, id)` is *strictly newer* than the cursor when
/// `(ts, id) > (cursor.timestamp, cursor.switchId)` lexicographically:
///   - `ts > cursor.timestamp`, OR
///   - `ts == cursor.timestamp && id > cursor.switchId` (string compare).
class PkSwitchCursor {
  const PkSwitchCursor({required this.timestamp, required this.switchId});

  final DateTime timestamp;
  final String switchId;

  /// Lexicographic compare on `(timestamp, switchId)`.
  ///
  /// Returns:
  ///   - negative if this < other
  ///   - zero if equal
  ///   - positive if this > other
  int compareTo(PkSwitchCursor other) {
    final tsCmp = timestamp.compareTo(other.timestamp);
    if (tsCmp != 0) return tsCmp;
    return switchId.compareTo(other.switchId);
  }

  /// True if a switch at `(otherTs, otherId)` is at or before this cursor —
  /// i.e. already processed and must be skipped on the next sweep.
  bool covers(DateTime otherTs, String otherId) {
    final tsCmp = timestamp.compareTo(otherTs);
    if (tsCmp > 0) return true; // cursor strictly later
    if (tsCmp < 0) return false; // cursor strictly earlier
    return switchId.compareTo(otherId) >= 0;
  }

  @override
  bool operator ==(Object other) =>
      other is PkSwitchCursor &&
      other.timestamp == timestamp &&
      other.switchId == switchId;

  @override
  int get hashCode => Object.hash(timestamp, switchId);

  @override
  String toString() => 'PkSwitchCursor(${timestamp.toIso8601String()}, $switchId)';
}

/// Typed error thrown by the incremental sweep when pagination cannot make
/// progress (a non-empty page does not advance the `before` paging key past
/// the previous page's oldest timestamp).
///
/// In practice this means the PK API returned the same boundary timestamp on
/// two consecutive pages, and naive `before = page.last.timestamp` paging
/// would loop forever. The sweep abandons the run rather than spinning.
class PkPaginationNoProgressError extends Error {
  PkPaginationNoProgressError({
    required this.lastBefore,
    required this.pagesFetched,
  });

  final DateTime lastBefore;
  final int pagesFetched;

  @override
  String toString() =>
      'PkPaginationNoProgressError: paging stalled at '
      '${lastBefore.toIso8601String()} after $pagesFetched pages.';
}

/// Typed error thrown by the incremental sweep when the page count exceeds
/// the hard cap (`maxPages`). 1000 pages × 100 switches/page = 100,000
/// switches; well above any realistic system, so hitting this means either
/// the API is misbehaving or the cursor is so stale the import should be
/// treated as a full re-import path.
class PkImportTooLargeError extends Error {
  PkImportTooLargeError({required this.pagesFetched, required this.cap});

  final int pagesFetched;
  final int cap;

  @override
  String toString() =>
      'PkImportTooLargeError: aborted after $pagesFetched pages (cap $cap).';
}

/// Typed error thrown by the diff sweep (WS3 step 6 / review #30) when a
/// leaver's close timestamp is strictly *before* the row's start timestamp.
///
/// This means the input switch stream has a corrupt ordering — a "leave"
/// event whose timestamp predates the entrant's start. The diff sweep cannot
/// produce a sensible row for this situation (start > end is meaningless),
/// so it bails out rather than silently writing a zero/negative-duration
/// row that would re-export to PK as garbage. Surfacing as a typed error
/// lets the UI show the user that the source data is bad.
///
/// Same-timestamp leaves (`end == start`) are not corrupt — they just mean
/// the API listed an entrant and a leave at the same moment. The sweep
/// skips the close and bumps `zeroLengthCloseSkipped` instead of throwing.
class PkSwitchOrderingError extends Error {
  PkSwitchOrderingError({
    required this.rowId,
    required this.startTime,
    required this.endTime,
    required this.switchId,
  });

  /// The fronting-session row id whose close was attempted.
  final String rowId;

  /// The row's existing start timestamp (from the entrant write).
  final DateTime startTime;

  /// The leaver switch's timestamp (which would be the close end_time).
  final DateTime endTime;

  /// The leaver switch's id, for diagnostic messaging.
  final String switchId;

  @override
  String toString() =>
      'PkSwitchOrderingError: leaver close at ${endTime.toIso8601String()} '
      'precedes start ${startTime.toIso8601String()} for row $rowId '
      '(leaver switch $switchId).';
}
