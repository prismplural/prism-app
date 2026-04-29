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
  /// add-front-sheet selection order ≈ input order).
  ///
  /// Excludes any member with `is_always_fronting == true` — those are
  /// surfaced via [alwaysPresentMembers] instead.
  final List<String> activeMembers;

  /// Visitors who joined for less than the ephemeral threshold during this
  /// period and were collapsed into a trailing chip on the row.
  final List<EphemeralVisit> briefVisitors;

  /// IDs of every per-member session active throughout this period —
  /// i.e., every session whose `[clampedStart, clampedEnd]` covers any
  /// part of the period's span. This is the set the period-detail
  /// screen / delete swipe / dismissible key all key off, so it must
  /// reflect the real underlying contributors, not just the boundary
  /// events that triggered the period transition.
  final List<String> sessionIds;

  /// Members marked `is_always_fronting`. Rendered as a separate
  /// "Always-present" affordance, never in the avatar stack (§2.3).
  final List<String> alwaysPresentMembers;

  /// True when at least one underlying session contributing to THIS
  /// period is open-ended AND the period is the trailing edge of the
  /// sweep (its end equals the open-end substitute). Earlier closed
  /// periods are NEVER open-ended even when a later session is still
  /// open — the live timer must only render on the period that actually
  /// extends to "now".
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
///
/// `rangeStart` is the visible window's lower bound; everything from
/// `rangeStart` to `now` is in the visible window. There is no separate
/// `rangeEnd` — the upper bound is implicitly "now at derivation time."
/// Threading a captured-at-subscription `rangeEnd` through here was the
/// root cause of a captured-now whack-a-mole class of bugs (rows whose
/// startTime was after the captured value got dropped as "future-dated"
/// or had their endTime clamped below their startTime).
@immutable
class DerivePeriodsInput {
  const DerivePeriodsInput({
    required this.sessions,
    required this.members,
    required this.rangeStart,
    required this.now,
    this.ephemeralThreshold = kEphemeralThreshold,
  });

  final List<FrontingSession> sessions;

  /// Member-id → Member for `is_always_fronting` lookup. Members not in
  /// the map are treated as not-always-fronting.
  final Map<String, Member> members;

  final DateTime rangeStart;
  final DateTime now;
  final Duration ephemeralThreshold;
}

/// Computes maximal "same-fronter-set" periods from per-member sessions.
///
/// Algorithm (§4.6):
///
/// 1. Filter to sessions overlapping `[rangeStart, now]`.
/// 2. Emit `(time, +member, sessionId)` and `(time, -member, sessionId)`
///    events, clamped to the range bounds. Open-ended sessions
///    substitute `now`; closed sessions clamp to `now` on the upper
///    edge as well (a closed session whose endTime is past `now` was
///    written from a clock skew or the user editing into the future,
///    and we clamp at the visible-window upper bound either way).
/// 3. Sort events; process all events at the same instant as one batch
///    (avoids zero-length "neither fronting" periods on swap).
/// 4. Sweep, maintaining a per-member set of active session IDs. Emit
///    a period whenever the active member set changes after a tied
///    batch. Carry forward the active session IDs for sessionId
///    bookkeeping.
/// 5. Apply ephemeral-member collapse: periods shorter than
///    [DerivePeriodsInput.ephemeralThreshold] fold into the surrounding
///    period as brief visitors. Cascading shorts collapse iteratively
///    so an all-short input still produces at least one row.
///
/// Sessions belonging to members marked `is_always_fronting` are kept
/// out of the active set entirely; they're surfaced as
/// `alwaysPresentMembers` on every period whose span overlaps their
/// session.
List<FrontingPeriod> deriveMaximalPeriods(DerivePeriodsInput input) {
  // Skip sleep sessions, soft-deleted rows, and future-dated rows.
  //
  // Future-dated rejection: the upstream DAO query uses an internal
  // `+30d` SQL lookahead so newly-inserted rows are caught by Drift
  // `.watch()` re-evaluation. That same lookahead means a typo'd
  // session with `start_time = tomorrow` reaches us. Such a session
  // is not yet active and must not produce visible periods — silently
  // drop it here.
  //
  // Cutoff is `input.now` (captured fresh per derivation). The bundle
  // no longer carries a `rangeEnd` at all — that captured-at-
  // subscription value was the root cause of the captured-now class
  // of bugs (rows inserted after subscription had startTime >
  // capturedRangeEnd and were silently dropped, OR had endTime
  // clamped below startTime, dropping the row entirely). Using
  // `input.now` everywhere means newly-arrived rows round-trip
  // cleanly while a genuine future-dated typo (start = tomorrow) is
  // still rejected.
  final sessions = [
    for (final s in input.sessions)
      if (!s.isSleep && !s.isDeleted && !s.startTime.isAfter(input.now)) s,
  ];
  if (sessions.isEmpty) return const [];

  // Upper bound for ALL clamping (open and closed sessions): `input.now`.
  // Open-ended sessions substitute it for their missing endTime; closed
  // sessions whose endTime is past `now` (clock skew, editing-future)
  // clamp to it too. There is no separate visible `rangeEnd` — the
  // visible window is implicitly `[rangeStart, input.now]`.
  final effectiveRangeEnd = input.now;

  // Partition into background (always-present) sessions and foreground.
  // Background sessions never enter the active set; instead, every period
  // they overlap gets the member added to `alwaysPresentMembers`.
  //
  // Insertion order is preserved: foreground/background are populated in
  // the order sessions appear in `input.sessions`, which lets the sweep
  // emit a stable arrival index for tie-breaking the avatar stack
  // (selection-order tiebreak per §2.3, since the input stream's order
  // matches the add-front sheet selection order in practice).
  final foreground = <_NormalizedSession>[];
  final background = <_NormalizedSession>[];
  for (final s in sessions) {
    final memberId = s.memberId;
    if (memberId == null) continue; // Unknown-fronter rows — treat as no-op.
    final start = s.startTime;
    final rawEnd = s.endTime;
    // Clamp spans against `[rangeStart, input.now]`. Open and closed
    // sessions both use `input.now` as the upper bound:
    //   - Open-ended: substitutes `now` for the missing endTime.
    //   - Closed: a closed session whose endTime is past `now` (clock
    //     skew, future-dated edit) clamps at `now`.
    // The future-dated rejection above already filtered any session
    // whose startTime is past `now`, so `start.isBefore(now)` always
    // holds for sessions that reach this point (modulo the equality
    // case handled by the `!start.isBefore(...)` guard below).
    final end = rawEnd ?? input.now;
    if (!end.isAfter(input.rangeStart)) continue;
    if (!start.isBefore(effectiveRangeEnd)) continue;

    final clampedStart =
        start.isBefore(input.rangeStart) ? input.rangeStart : start;
    final clampedEnd =
        end.isAfter(effectiveRangeEnd) ? effectiveRangeEnd : end;
    if (!clampedEnd.isAfter(clampedStart)) continue;

    final isBackground = input.members[memberId]?.isAlwaysFronting ?? false;
    final normalized = _NormalizedSession(
      sessionId: s.id,
      memberId: memberId,
      origStart: start,
      origEnd: rawEnd,
      clampedStart: clampedStart,
      clampedEnd: clampedEnd,
      isOpen: rawEnd == null,
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

  // Index foreground sessions by member for O(1) "find best contributing
  // session for this member" lookups during ephemeral collapse. Avoids
  // an O(N) scan inside the inner loop (P2: n × m_short was the prior
  // worst case at the 10–20k session scale).
  final foregroundByMember = <String, List<_NormalizedSession>>{};
  for (final s in foreground) {
    foregroundByMember.putIfAbsent(s.memberId, () => []).add(s);
  }

  // Stable per-member arrival index keyed off input order. The
  // foreground list is built in `input.sessions` order; the first time
  // we see a member's session, we stamp the index. This is the
  // selection-order tiebreak (§2.3): when two members share the same
  // firstStart, we order by who was selected first in the add-front
  // sheet (which matches the input stream's ordering at the storage
  // layer in practice).
  final memberArrivalIndex = <String, int>{};
  {
    var idx = 0;
    for (final s in foreground) {
      memberArrivalIndex.putIfAbsent(s.memberId, () => idx++);
    }
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
    // Stable secondary by member arrival index → input order. Avoids
    // alphabetical-by-memberId ordering (which would lock in a bug
    // where the avatar stack ignored selection order).
    final ai = memberArrivalIndex[a.session.memberId] ?? 0;
    final bi = memberArrivalIndex[b.session.memberId] ?? 0;
    return ai.compareTo(bi);
  });

  // Sweep. We track active session IDs PER MEMBER (refcount-equivalent):
  //   member → set of active session IDs
  // Member is "active" iff its set is non-empty. The full active session
  // set across all members is the union, which we maintain incrementally
  // for fast period-emission.
  final activeSessionsByMember = <String, Set<String>>{};
  // Earliest clampedStart per active member, for avatar ordering.
  final activeFirstStart = <String, DateTime>{};
  // Currently-active session IDs across every active member. Snapshot
  // at period emission to capture the set throughout the period (NOT
  // just the boundary events).
  final activeSessionIds = <String>{};

  final rawPeriods = <_RawPeriod>[];
  var periodStart = input.rangeStart;
  // Snapshot of activeFirstStart at periodStart: used to order avatars.
  Map<String, DateTime> snapshotFirstStart = {};
  // Snapshot of activeSessionIds at periodStart: used so the period's
  // sessionIds reflect its FULL active set, not just the events at its
  // boundary timestamps.
  Set<String> snapshotSessionIds = {};
  // Whether this period reaches the trailing edge of the sweep (i.e.,
  // its end is the very last point in the visible window). Trailing-edge
  // status is what makes a period eligible for `isOpenEnded = true` —
  // earlier closed periods never carry the live timer.
  var snapshotHasOpenSession = false;

  void emitPeriod(DateTime end) {
    if (!end.isAfter(periodStart)) return;

    // Skip empty-active-set periods. The list view shows fronts, not
    // gaps; nobody-fronting is rendered as the absence of a row.
    if (snapshotFirstStart.isEmpty) {
      return;
    }

    // Active members snapshot ordered by:
    //   1. firstStart ascending (earliest-started → longest active at
    //      period start → leads the stack)
    //   2. arrivalIndex ascending (selection-order tiebreak via
    //      input order)
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
      sessionIds: snapshotSessionIds.toList(),
      hasOpenSession: snapshotHasOpenSession,
    ));
  }

  void refreshSnapshots() {
    snapshotFirstStart = Map.of(activeFirstStart);
    snapshotSessionIds = Set.of(activeSessionIds);
    // Whether any of the currently-active sessions is open-ended. A
    // period inherits trailing-edge open-ended status only if (a) at
    // least one active session is open AND (b) the period's end equals
    // the open-end substitute (the trailing-edge check is applied at
    // emit time, not here).
    var hasOpen = false;
    for (final mid in activeSessionsByMember.keys) {
      final ids = activeSessionsByMember[mid]!;
      for (final s in foregroundByMember[mid] ?? const <_NormalizedSession>[]) {
        if (s.isOpen && ids.contains(s.sessionId)) {
          hasOpen = true;
          break;
        }
      }
      if (hasOpen) break;
    }
    snapshotHasOpenSession = hasOpen;
  }

  // Compute whether any currently-active session is open-ended. Used
  // alongside activeSessionsByMember and activeSessionIds to detect
  // tied-batch transitions that change ANY snapshot-relevant state, not
  // just the active member set.
  bool computeAnyOpen() {
    for (final mid in activeSessionsByMember.keys) {
      final ids = activeSessionsByMember[mid]!;
      for (final s in foregroundByMember[mid] ?? const <_NormalizedSession>[]) {
        if (s.isOpen && ids.contains(s.sessionId)) return true;
      }
    }
    return false;
  }

  var i = 0;
  while (i < events.length) {
    final t = events[i].time;
    // Process all events at this instant as one tied batch, then compare
    // active-set membership AND active session IDs AND open-session
    // status before vs. after. Same-member tied transitions (A1 ends at
    // T, A2 starts at T for the same member) keep the same active
    // member set but change activeSessionIds and possibly hasOpenSession;
    // those must trigger a snapshot refresh too.
    final preActive = activeSessionsByMember.keys.toSet();
    final preSessionIds = Set<String>.of(activeSessionIds);
    final preAnyOpen = computeAnyOpen();

    // First time we see this tick: emit the period accumulated up to it.
    // (Only if we have moved forward from periodStart.)
    if (t.isAfter(periodStart)) {
      emitPeriod(t);
      periodStart = t;
    }

    // Drain the tied batch.
    while (i < events.length && events[i].time == t) {
      final e = events[i];
      final mid = e.session.memberId;
      final sid = e.session.sessionId;
      if (e.kind == _EventKind.start) {
        final set = activeSessionsByMember.putIfAbsent(mid, () => <String>{});
        set.add(sid);
        activeSessionIds.add(sid);
        if (set.length == 1) {
          activeFirstStart[mid] = e.session.clampedStart;
        }
      } else {
        final set = activeSessionsByMember[mid];
        if (set != null) {
          set.remove(sid);
          if (set.isEmpty) {
            activeSessionsByMember.remove(mid);
            activeFirstStart.remove(mid);
          }
        }
        activeSessionIds.remove(sid);
      }
      i++;
    }

    final postActive = activeSessionsByMember.keys.toSet();
    final postAnyOpen = computeAnyOpen();
    if (!_setEquals(preActive, postActive) ||
        !_setEquals(preSessionIds, activeSessionIds) ||
        preAnyOpen != postAnyOpen) {
      // Any of (activeMembers, activeSessionIds, hasOpenSession) changed
      // across the batch — start a new period. periodStart is already
      // set to t above.
      refreshSnapshots();
    }
  }

  // Trailing period from the last event time to `now`, if active set is
  // non-empty. Almost always empty in practice (last event is a session
  // end), but covers the edge case where the sweep finishes mid-active.
  if (snapshotFirstStart.isNotEmpty && periodStart.isBefore(effectiveRangeEnd)) {
    emitPeriod(effectiveRangeEnd);
  }

  // Apply ephemeral-member collapse + always-present surfacing + open-ended
  // detection to produce the final period stream.
  return _collapseAndAnnotate(
    rawPeriods,
    background,
    foregroundByMember,
    input.ephemeralThreshold,
    effectiveRangeEnd,
  );
}

/// Walks raw periods, collapsing brief visitors into the surrounding
/// period, attaching always-present members, and marking open-ended.
///
/// Collapse rules:
///   - A period is "short" when its duration < threshold.
///   - A short period whose extra members (those not in either neighbor)
///     can fold into a longer adjacent period folds; its session ids
///     and brief-visit chips carry forward to the next kept period.
///   - When ALL periods are short, the algorithm still emits at least
///     one row spanning the whole sweep, with everyone as briefs — the
///     user has data, we should show it.
///   - Cascading shorts (multiple consecutive shorts) compose: each
///     short's pending briefs roll forward to the next short or
///     surviving neighbor.
List<FrontingPeriod> _collapseAndAnnotate(
  List<_RawPeriod> raw,
  List<_NormalizedSession> background,
  Map<String, List<_NormalizedSession>> foregroundByMember,
  Duration ephemeralThreshold,
  DateTime effectiveRangeEnd,
) {
  if (raw.isEmpty) return const [];

  // Shortcut: if EVERY raw period is short, emit a single combined row
  // covering the full span with all participants as briefs. Without this
  // an all-short input produced empty output (P2 cascade bug).
  //
  // BUT: ephemeral collapse is for HISTORICAL noise reduction. A
  // currently-open period (even one under the threshold — e.g. a front
  // started 30 seconds ago) must NOT collapse into a brief-visitors-
  // only row, because the row's `activeMembers` would be empty and the
  // widget would render it as "Unknown." If any raw period contains an
  // open-ended session we skip the all-short shortcut entirely and
  // fall through to the standard collapse pass, which preserves the
  // open period's active members.
  final hasOpenAnywhere = raw.any((p) => p.hasOpenSession);
  final allShort =
      !hasOpenAnywhere && raw.every((p) => p.duration < ephemeralThreshold);
  if (allShort) {
    final start = raw.first.start;
    final end = raw.last.end;
    final allMembers = <String>{};
    final allSessionIds = <String>{};
    final brief = <EphemeralVisit>[];
    for (final p in raw) {
      allMembers.addAll(p.activeMembers);
      allSessionIds.addAll(p.sessionIds);
      for (final mid in p.activeMembers) {
        final sess = _findBestSessionForMember(foregroundByMember, mid, p);
        if (sess != null) {
          brief.add(EphemeralVisit(
            memberId: mid,
            start: p.start.isBefore(sess.clampedStart)
                ? sess.clampedStart
                : p.start,
            end: p.end.isAfter(sess.clampedEnd) ? sess.clampedEnd : p.end,
            sessionId: sess.sessionId,
          ));
        }
      }
    }
    final alwaysPresent = _alwaysPresentDuring(background, start, end);
    return [
      FrontingPeriod(
        start: start,
        end: end,
        activeMembers: const [],
        briefVisitors: brief,
        sessionIds: allSessionIds.toList(),
        alwaysPresentMembers: alwaysPresent,
        // The all-short branch only fires when no raw period contains
        // an open session (see `hasOpenAnywhere` above), so the
        // combined row is always closed.
        isOpenEnded: false,
      ),
    ];
  }

  // Standard pass: walk raw periods; carry pending briefs forward
  // through cascading shorts; emit a kept period when we land on a
  // non-short row (or when there are no further rows to absorb the
  // pending briefs).
  final result = <FrontingPeriod>[];
  final pendingBrief = <EphemeralVisit>[];
  final pendingSessionIds = <String>{};

  for (var idx = 0; idx < raw.length; idx++) {
    final p = raw[idx];
    // A period containing an open session represents the current state.
    // We must NEVER collapse it as ephemeral, even if it's under the
    // threshold (e.g. a front started 30 seconds ago). Without this
    // guard, a just-started current front would land in pendingBrief
    // and either render with empty activeMembers (the "Unknown" bug)
    // or get dropped entirely.
    final isShort =
        p.duration < ephemeralThreshold && !p.hasOpenSession;

    if (isShort) {
      // Try to fold this period's "extra" members into adjacent periods
      // as brief visitors. Walk left/right past contiguous shorts to
      // find the actual surviving neighbors — a chain of shorts
      // shouldn't think of itself as its own neighbor.
      final neighborMembers = <String>{};
      for (var j = idx - 1; j >= 0; j--) {
        if (raw[j].duration >= ephemeralThreshold) {
          neighborMembers.addAll(raw[j].activeMembers);
          break;
        }
      }
      for (var j = idx + 1; j < raw.length; j++) {
        if (raw[j].duration >= ephemeralThreshold) {
          neighborMembers.addAll(raw[j].activeMembers);
          break;
        }
      }
      // Members appearing only in this short period are the "brief" set.
      final brief =
          p.activeMembers.where((m) => !neighborMembers.contains(m));
      for (final mid in brief) {
        final sess = _findBestSessionForMember(foregroundByMember, mid, p);
        if (sess != null) {
          pendingBrief.add(EphemeralVisit(
            memberId: mid,
            start: p.start.isBefore(sess.clampedStart)
                ? sess.clampedStart
                : p.start,
            end: p.end.isAfter(sess.clampedEnd) ? sess.clampedEnd : p.end,
            sessionId: sess.sessionId,
          ));
        }
      }
      pendingSessionIds.addAll(p.sessionIds);
      continue;
    }

    // Keep this period. Flush any pending brief visitors into it,
    // deduping members who are already active in this period — a
    // closed-short → open-short same-member handoff would otherwise
    // render the active member as a "brief visitor" of their own
    // active period (Codex P2).
    final allSessionIds = <String>{...p.sessionIds, ...pendingSessionIds};
    final activeMemberSet = p.activeMembers.toSet();
    final brief = <EphemeralVisit>[
      for (final v in pendingBrief)
        if (!activeMemberSet.contains(v.memberId)) v,
    ];
    pendingBrief.clear();
    pendingSessionIds.clear();

    final alwaysPresent = _alwaysPresentDuring(background, p.start, p.end);
    final isOpen = p.hasOpenSession && !p.end.isBefore(effectiveRangeEnd);

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
        // The merged period inherits the latter's trailing-edge state —
        // only the most recent end matters for liveness.
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
  }

  // If we ended with pending brief visitors and no kept period followed,
  // attach them to the last kept period (mutate by replacing). Dedupe
  // against the last period's active member set — a same-member
  // handoff at the trailing edge shouldn't render the active member
  // as a brief visitor of themselves.
  if (pendingBrief.isNotEmpty && result.isNotEmpty) {
    final last = result.removeLast();
    final lastActiveSet = last.activeMembers.toSet();
    final dedupedTrailing = <EphemeralVisit>[
      for (final v in pendingBrief)
        if (!lastActiveSet.contains(v.memberId)) v,
    ];
    result.add(FrontingPeriod(
      start: last.start,
      end: last.end,
      activeMembers: last.activeMembers,
      briefVisitors: [...last.briefVisitors, ...dedupedTrailing],
      sessionIds: {...last.sessionIds, ...pendingSessionIds}.toList(),
      alwaysPresentMembers: last.alwaysPresentMembers,
      isOpenEnded: last.isOpenEnded,
    ));
  }

  return result;
}

_NormalizedSession? _findBestSessionForMember(
  Map<String, List<_NormalizedSession>> foregroundByMember,
  String memberId,
  _RawPeriod p,
) {
  final list = foregroundByMember[memberId];
  if (list == null) return null;
  _NormalizedSession? best;
  var bestOverlap = Duration.zero;
  for (final s in list) {
    final overlapStart =
        s.clampedStart.isAfter(p.start) ? s.clampedStart : p.start;
    final overlapEnd =
        s.clampedEnd.isBefore(p.end) ? s.clampedEnd : p.end;
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
    required this.hasOpenSession,
  });

  final DateTime start;
  final DateTime end;
  final List<String> activeMembers;
  final List<String> sessionIds;
  /// Whether the active session set at the time this period was emitted
  /// included at least one open-ended session. Combined with the
  /// trailing-edge check at emit time, this drives `isOpenEnded`.
  final bool hasOpenSession;

  Duration get duration => end.difference(start);
}
