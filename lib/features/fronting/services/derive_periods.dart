import 'package:flutter/foundation.dart';
import 'package:prism_plurality/domain/models/models.dart';

/// Default ephemeral-member collapse threshold (§2.3).
///
/// Periods shorter than this don't get their own row; they fold into the
/// surrounding period as a trailing "+Sam briefly" chip. Configurable per
/// user in 1B; for 1A this is hardcoded.
const Duration kEphemeralThreshold = Duration(minutes: 2);

/// A maximal time span during which the active fronter set didn't change.
///
/// Derived from per-member [FrontingSession] rows by [deriveMaximalPeriods].
/// Each period collapses one or more underlying per-member sessions into a
/// single list row with an avatar stack.
@immutable
class FrontingPeriod {
  const FrontingPeriod({
    required this.start,
    required this.end,
    required this.activeMembers,
    required this.briefVisitors,
    required this.sessionIds,
    required this.alwaysPresentMembers,
    required this.isOpenEnded,
  });

  /// Period start (clamped to the visible range bound on the leading edge).
  final DateTime start;

  /// Period end. For an open-ended (current) period this is the substituted
  /// "now" (or `range_end` if greater); see [isOpenEnded].
  final DateTime end;

  /// Members continuously fronting through this period, ordered for the
  /// avatar stack (longest-active-at-period-start first; tiebreak by the
  /// add-front-sheet selection order ≈ session.startTime ascending).
  ///
  /// Excludes any member with `is_always_fronting == true` — those are
  /// surfaced via [alwaysPresentMembers] instead.
  final List<String> activeMembers;

  /// Visitors who joined for less than the ephemeral threshold during this
  /// period and were collapsed into a trailing chip on the row.
  final List<EphemeralVisit> briefVisitors;

  /// IDs of every per-member session that contributed to this period
  /// (across the full set, including ephemeral visitors). Used to navigate
  /// to the period detail screen on tap.
  final List<String> sessionIds;

  /// Members marked `is_always_fronting`. Rendered as a separate
  /// "Always-present" affordance, never in the avatar stack (§2.3).
  final List<String> alwaysPresentMembers;

  /// True when at least one underlying session is still open at the period's
  /// end. The widget renders the trailing time as "Now" instead of an end
  /// time in this case.
  final bool isOpenEnded;

  Duration get duration => end.difference(start);

  /// True when the period has no fronters at all (empty active set).
  /// The list view skips these rows; gaps are not "fronts."
  bool get isEmpty =>
      activeMembers.isEmpty &&
      briefVisitors.isEmpty &&
      alwaysPresentMembers.isEmpty;

  @override
  String toString() =>
      'FrontingPeriod($start - $end, active=$activeMembers, '
      'brief=${briefVisitors.length}, alwaysPresent=$alwaysPresentMembers, '
      'isOpenEnded=$isOpenEnded)';
}

/// A collapsed brief visit during a longer period.
@immutable
class EphemeralVisit {
  const EphemeralVisit({
    required this.memberId,
    required this.start,
    required this.end,
    required this.sessionId,
  });

  final String memberId;
  final DateTime start;
  final DateTime end;
  final String sessionId;

  Duration get duration => end.difference(start);
}

/// Inputs to [deriveMaximalPeriods].
///
/// `members` carries `is_always_fronting` so the sweep can split background
/// hosts out of the active set. `now` is injectable for tests.
@immutable
class DerivePeriodsInput {
  const DerivePeriodsInput({
    required this.sessions,
    required this.members,
    required this.rangeStart,
    required this.rangeEnd,
    required this.now,
    this.ephemeralThreshold = kEphemeralThreshold,
  });

  final List<FrontingSession> sessions;

  /// Member-id → Member for `is_always_fronting` lookup. Members not in
  /// the map are treated as not-always-fronting.
  final Map<String, Member> members;

  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime now;
  final Duration ephemeralThreshold;
}

/// Computes maximal "same-fronter-set" periods from per-member sessions.
///
/// Algorithm (§4.6):
///
/// 1. Filter to sessions overlapping `[rangeStart, rangeEnd]`.
/// 2. Emit `(time, +member)` and `(time, -member)` events, clamped to the
///    range bounds. Open-ended sessions substitute `max(now, rangeEnd)`.
/// 3. Sort events; process all events at the same instant as one batch
///    (avoids zero-length "neither fronting" periods on swap).
/// 4. Sweep, maintaining the active set; emit a period whenever the set
///    changes after a tied-batch.
/// 5. Apply ephemeral-member collapse: periods shorter than
///    [DerivePeriodsInput.ephemeralThreshold] fold into the surrounding
///    period as brief visitors.
///
/// Sessions belonging to members marked `is_always_fronting` are kept out
/// of the active set entirely; they're surfaced as `alwaysPresentMembers`
/// on every period whose span overlaps their session.
List<FrontingPeriod> deriveMaximalPeriods(DerivePeriodsInput input) {
  // Skip sleep sessions — the list view renders those via a separate sleep
  // tile, not a fronting period.
  final sessions = [
    for (final s in input.sessions)
      if (!s.isSleep && !s.isDeleted) s,
  ];
  if (sessions.isEmpty) return const [];

  // Open-ended substitution per §4.6: substitute max(now, rangeEnd) so a
  // currently-active session whose start is in the range produces a period
  // that extends to the end of the visible range, not an arbitrary "now"
  // earlier than that. We also use this as the effective upper clamp bound
  // so periods can extend to "now" even when "now" is past rangeEnd.
  final openEndSub =
      input.now.isAfter(input.rangeEnd) ? input.now : input.rangeEnd;
  final effectiveRangeEnd = openEndSub;

  // Partition into background (always-present) sessions and foreground.
  // Background sessions never enter the active set; instead, every period
  // they overlap gets the member added to `alwaysPresentMembers`.
  final foreground = <_NormalizedSession>[];
  final background = <_NormalizedSession>[];
  for (final s in sessions) {
    final memberId = s.memberId;
    if (memberId == null) continue; // Unknown-fronter rows — treat as no-op.
    final start = s.startTime;
    final end = s.endTime ?? openEndSub;
    if (!end.isAfter(input.rangeStart)) continue;
    if (!start.isBefore(effectiveRangeEnd)) continue;

    final clampedStart = start.isBefore(input.rangeStart) ? input.rangeStart : start;
    final clampedEnd = end.isAfter(effectiveRangeEnd) ? effectiveRangeEnd : end;
    if (!clampedEnd.isAfter(clampedStart)) continue;

    final isBackground = input.members[memberId]?.isAlwaysFronting ?? false;
    final normalized = _NormalizedSession(
      sessionId: s.id,
      memberId: memberId,
      origStart: start,
      origEnd: s.endTime,
      clampedStart: clampedStart,
      clampedEnd: clampedEnd,
      isOpen: s.endTime == null,
    );
    if (isBackground) {
      background.add(normalized);
    } else {
      foreground.add(normalized);
    }
  }

  if (foreground.isEmpty) {
    // No foreground activity at all: emit nothing. Background-only periods
    // would be a "gap" in list-view terms; we skip those (caller renders
    // active fronts only).
    return const [];
  }

  // Build event stream over foreground sessions. Each session contributes
  // a (start, +) and (end, -) event.
  final events = <_Event>[];
  for (final s in foreground) {
    events.add(_Event(
      time: s.clampedStart,
      kind: _EventKind.start,
      session: s,
    ));
    events.add(_Event(
      time: s.clampedEnd,
      kind: _EventKind.end,
      session: s,
    ));
  }

  events.sort((a, b) {
    final cmp = a.time.compareTo(b.time);
    if (cmp != 0) return cmp;
    // Stable secondary by member id so ordering inside a tied batch is
    // deterministic across platforms.
    return a.session.memberId.compareTo(b.session.memberId);
  });

  // Sweep. Maintain refcounted active set keyed by memberId so a single
  // member with two overlapping rows enters once and exits once (no
  // duplicate avatars in the stack).
  final activeRefCounts = <String, int>{};
  // Track the earliest clampedStart per active member for ordering
  // (longest-active-at-period-start first).
  final activeFirstStart = <String, DateTime>{};
  // Track every session id that has contributed to the period currently
  // being built. Cleared whenever we emit a period.
  final contributingSessionIds = <String>{};
  // Track a stable per-member arrival index so we have a deterministic
  // tiebreak when two members share the same first-start (≈ selection
  // order from the add-front sheet).
  final memberArrivalIndex = <String, int>{};
  var arrivalCounter = 0;

  final rawPeriods = <_RawPeriod>[];
  var periodStart = input.rangeStart;
  // Snapshot of activeFirstStart at periodStart: used to order avatars.
  Map<String, DateTime> snapshotFirstStart = {};

  void emitPeriod(DateTime end) {
    if (!end.isAfter(periodStart)) return;

    // Skip empty-active-set periods. The list view shows fronts, not
    // gaps; nobody-fronting is rendered as the absence of a row.
    if (snapshotFirstStart.isEmpty) {
      contributingSessionIds.clear();
      return;
    }

    // Active members snapshot ordered by:
    //   1. firstStart ascending (earliest-started → longest active at
    //      period start → leads the stack)
    //   2. arrivalIndex ascending (selection-order tiebreak)
    final memberIds = snapshotFirstStart.keys.toList();
    memberIds.sort((a, b) {
      final cmp = snapshotFirstStart[a]!.compareTo(snapshotFirstStart[b]!);
      if (cmp != 0) return cmp;
      final ai = memberArrivalIndex[a] ?? 0;
      final bi = memberArrivalIndex[b] ?? 0;
      return ai.compareTo(bi);
    });

    rawPeriods.add(_RawPeriod(
      start: periodStart,
      end: end,
      activeMembers: memberIds,
      sessionIds: contributingSessionIds.toList(),
    ));
    contributingSessionIds.clear();
  }

  var i = 0;
  while (i < events.length) {
    final t = events[i].time;
    // Process all events at this instant as one tied batch, then compare
    // active-set membership before vs. after.
    final preActive = activeRefCounts.keys.toSet();

    // First time we see this tick: emit the period accumulated up to it.
    // (Only if we have moved forward from periodStart.)
    if (t.isAfter(periodStart)) {
      emitPeriod(t);
      periodStart = t;
    }

    // Drain the tied batch.
    while (i < events.length && events[i].time == t) {
      final e = events[i];
      contributingSessionIds.add(e.session.sessionId);
      if (e.kind == _EventKind.start) {
        final mid = e.session.memberId;
        final cnt = (activeRefCounts[mid] ?? 0) + 1;
        activeRefCounts[mid] = cnt;
        if (cnt == 1) {
          activeFirstStart[mid] = e.session.clampedStart;
          memberArrivalIndex[mid] = arrivalCounter++;
        }
      } else {
        final mid = e.session.memberId;
        final cnt = (activeRefCounts[mid] ?? 0) - 1;
        if (cnt <= 0) {
          activeRefCounts.remove(mid);
          activeFirstStart.remove(mid);
        } else {
          activeRefCounts[mid] = cnt;
        }
      }
      i++;
    }

    final postActive = activeRefCounts.keys.toSet();
    if (!_setEquals(preActive, postActive)) {
      // Active set changed across the batch — start a new period.
      // Periodstart is already set to t above.
      snapshotFirstStart = Map.of(activeFirstStart);
    }
  }

  // Trailing period from the last event time to rangeEnd, if active set
  // is non-empty. Almost always empty in practice (last event is a session
  // end), but covers the edge case where the sweep finishes mid-active.
  if (snapshotFirstStart.isNotEmpty && periodStart.isBefore(effectiveRangeEnd)) {
    emitPeriod(effectiveRangeEnd);
  }

  // Apply ephemeral-member collapse + always-present surfacing + open-ended
  // detection to produce the final period stream.
  return _collapseAndAnnotate(
    rawPeriods,
    background,
    foreground,
    input.ephemeralThreshold,
    openEndSub,
  );
}

/// Walks raw periods, collapsing brief visitors into the surrounding
/// period, attaching always-present members, and marking open-ended.
List<FrontingPeriod> _collapseAndAnnotate(
  List<_RawPeriod> raw,
  List<_NormalizedSession> background,
  List<_NormalizedSession> foreground,
  Duration ephemeralThreshold,
  DateTime openEndSub,
) {
  if (raw.isEmpty) return const [];

  // Build a quick lookup from sessionId → session for ephemeral visit
  // bookkeeping (needs the original session id and start/end for chip data).
  final sessionById = <String, _NormalizedSession>{
    for (final s in foreground) s.sessionId: s,
  };

  // Step 1: identify ephemeral periods. A period is ephemeral when:
  //   - duration < threshold, AND
  //   - it has at least one extra member compared to a neighbor
  //     (i.e., the brief member can fold into a longer adjacent period).
  //
  // Practical rule used here: any period whose duration < threshold and
  // whose active set differs from at least one neighbor by exactly the
  // members who appear only briefly. To keep this simple and robust we
  // collapse a short period by folding members who do NOT appear in the
  // surrounding periods on either side as brief visitors of the longer
  // adjacent period (preferring the longer of the two neighbors).

  // We carry forward "pending brief visits" from short periods we've
  // skipped, then attach them to the next non-short period we keep.
  final result = <FrontingPeriod>[];
  final pendingBrief = <EphemeralVisit>[];
  final pendingSessionIds = <String>{};

  _RawPeriod? lastKept;

  for (var idx = 0; idx < raw.length; idx++) {
    final p = raw[idx];
    final isShort = p.duration < ephemeralThreshold;

    if (isShort && raw.length > 1) {
      // Try to fold this period's "extra" members into adjacent periods
      // as brief visitors.
      final prev = idx > 0 ? raw[idx - 1] : null;
      final next = idx + 1 < raw.length ? raw[idx + 1] : null;
      final neighborMembers = <String>{
        ...?prev?.activeMembers,
        ...?next?.activeMembers,
      };
      // Members appearing only in this short period are the "brief" set.
      final brief = p.activeMembers.where((m) => !neighborMembers.contains(m));
      for (final mid in brief) {
        // Find the contributing session for this member in this period —
        // pick the session with the largest overlap with [p.start, p.end].
        final sess = _findBestSessionForMember(sessionById, mid, p);
        if (sess != null) {
          pendingBrief.add(EphemeralVisit(
            memberId: mid,
            start: p.start.isBefore(sess.clampedStart)
                ? sess.clampedStart
                : p.start,
            end: p.end.isAfter(sess.clampedEnd)
                ? sess.clampedEnd
                : p.end,
            sessionId: sess.sessionId,
          ));
        }
      }
      pendingSessionIds.addAll(p.sessionIds);

      // If the period has members that ARE in a neighbor (i.e., brief
      // doesn't cover everyone), we still merge the row into the
      // neighbor with the matching set — handled by simply not emitting
      // a row for this short period and letting the neighbor's row span
      // its own range.
      continue;
    }

    // Keep this period. Flush any pending brief visitors into it.
    final allSessionIds = <String>{...p.sessionIds, ...pendingSessionIds};
    final brief = List<EphemeralVisit>.from(pendingBrief);
    pendingBrief.clear();
    pendingSessionIds.clear();

    final alwaysPresent = _alwaysPresentDuring(background, p.start, p.end);
    final isOpen = _isOpenEnded(foreground, p.end);

    // Merge with previous result if same active set: a short period
    // sandwiched between two same-set periods was just collapsed, so the
    // two surrounding ones should now be one continuous row.
    if (result.isNotEmpty &&
        _listEquals(result.last.activeMembers, p.activeMembers)) {
      final prev = result.removeLast();
      result.add(FrontingPeriod(
        start: prev.start,
        end: p.end,
        activeMembers: prev.activeMembers,
        briefVisitors: [...prev.briefVisitors, ...brief],
        sessionIds: {...prev.sessionIds, ...allSessionIds}.toList(),
        alwaysPresentMembers: alwaysPresent,
        isOpenEnded: isOpen,
      ));
    } else {
      result.add(FrontingPeriod(
        start: p.start,
        end: p.end,
        activeMembers: p.activeMembers,
        briefVisitors: brief,
        sessionIds: allSessionIds.toList(),
        alwaysPresentMembers: alwaysPresent,
        isOpenEnded: isOpen,
      ));
    }
    lastKept = p;
  }

  // If we ended with pending brief visitors and no kept period followed,
  // attach them to the last kept period (mutate by replacing).
  if (pendingBrief.isNotEmpty && lastKept != null && result.isNotEmpty) {
    final last = result.removeLast();
    result.add(FrontingPeriod(
      start: last.start,
      end: last.end,
      activeMembers: last.activeMembers,
      briefVisitors: [...last.briefVisitors, ...pendingBrief],
      sessionIds: {...last.sessionIds, ...pendingSessionIds}.toList(),
      alwaysPresentMembers: last.alwaysPresentMembers,
      isOpenEnded: last.isOpenEnded,
    ));
  }

  return result;
}

_NormalizedSession? _findBestSessionForMember(
  Map<String, _NormalizedSession> sessionById,
  String memberId,
  _RawPeriod p,
) {
  _NormalizedSession? best;
  var bestOverlap = Duration.zero;
  for (final s in sessionById.values) {
    if (s.memberId != memberId) continue;
    final overlapStart = s.clampedStart.isAfter(p.start) ? s.clampedStart : p.start;
    final overlapEnd = s.clampedEnd.isBefore(p.end) ? s.clampedEnd : p.end;
    if (overlapEnd.isAfter(overlapStart)) {
      final dur = overlapEnd.difference(overlapStart);
      if (dur > bestOverlap) {
        bestOverlap = dur;
        best = s;
      }
    }
  }
  return best;
}

List<String> _alwaysPresentDuring(
  List<_NormalizedSession> background,
  DateTime start,
  DateTime end,
) {
  final ids = <String>{};
  for (final s in background) {
    // Overlap test against [start, end].
    if (s.clampedStart.isBefore(end) && s.clampedEnd.isAfter(start)) {
      ids.add(s.memberId);
    }
  }
  return ids.toList()..sort();
}

bool _isOpenEnded(List<_NormalizedSession> foreground, DateTime periodEnd) {
  // The period is open-ended when at least one foreground session is still
  // open AND its clampedEnd reaches the period's end (i.e., its end was
  // substituted by the open-end sentinel).
  for (final s in foreground) {
    if (s.isOpen && !s.clampedEnd.isBefore(periodEnd)) return true;
  }
  return false;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  for (final x in a) {
    if (!b.contains(x)) return false;
  }
  return true;
}

class _NormalizedSession {
  _NormalizedSession({
    required this.sessionId,
    required this.memberId,
    required this.origStart,
    required this.origEnd,
    required this.clampedStart,
    required this.clampedEnd,
    required this.isOpen,
  });

  final String sessionId;
  final String memberId;
  final DateTime origStart;
  final DateTime? origEnd;
  final DateTime clampedStart;
  final DateTime clampedEnd;
  final bool isOpen;
}

enum _EventKind { start, end }

class _Event {
  _Event({required this.time, required this.kind, required this.session});

  final DateTime time;
  final _EventKind kind;
  final _NormalizedSession session;
}

class _RawPeriod {
  _RawPeriod({
    required this.start,
    required this.end,
    required this.activeMembers,
    required this.sessionIds,
  });

  final DateTime start;
  final DateTime end;
  final List<String> activeMembers;
  final List<String> sessionIds;

  Duration get duration => end.difference(start);
}
