import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_table_ticker_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

/// How long an open fronting session must be running before a member is
/// auto-promoted into the "Always present" pinned header — even when the
/// member has not opted into [Member.isAlwaysFronting] explicitly.
///
/// Hardcoded for v1; surfaced as a constant so tests can reference the
/// same boundary the provider uses.
const Duration kAutoPromoteThreshold = Duration(days: 7);

/// A member that currently qualifies for the always-present pinned header,
/// bundled with the session that anchors them and the age of that session.
///
/// Returned by [alwaysPresentMembersProvider]. The shape is intentionally
/// small and immutable so consumers (the header widget, downstream filters
/// in `perMemberRows` view) can pattern-match without copying state.
class AlwaysPresentMember {
  const AlwaysPresentMember({
    required this.member,
    required this.session,
    required this.age,
  });

  /// The qualifying member.
  final Member member;

  /// The currently-open fronting session that anchors them in the header.
  /// Always satisfies `endTime == null`, `sessionType == normal`, and
  /// `isDeleted == false`.
  final FrontingSession session;

  /// `now - session.startTime` at the moment the provider computed the
  /// snapshot. Used by the widget to render the duration label and by
  /// downstream consumers to apply date-scoped filtering.
  final Duration age;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlwaysPresentMember &&
        other.member == member &&
        other.session == session &&
        other.age == age;
  }

  @override
  int get hashCode => Object.hash(member, session, age);
}

/// Members who currently satisfy ALL of:
///
///   - Have a currently-open fronting session (`endTime == null`,
///     `sessionType == normal`, `isDeleted == false`), AND
///   - EITHER `member.isAlwaysFronting == true` (explicit opt-in)
///     OR `now - session.startTime >= kAutoPromoteThreshold` (auto-promote).
///
/// The active-session prerequisite is critical: an explicit
/// `isAlwaysFronting` member with no open session does NOT appear here —
/// there is nothing to be "always present" about.
///
/// Auto-rebuild triggers:
///   - `frontingTableTickerProvider` — fires on any write to
///     `fronting_sessions`.
///   - `activeSessionsProvider` — Drift `.watch()` fires on relevant rows.
///   - `allMembersProvider` — Drift `.watch()` fires on `is_always_fronting`
///     toggles and other member edits.
///   - A `Timer` scheduled for the next not-yet-promoted threshold-crossing
///     moment, so a session crossing 7d at wall-clock triggers a rebuild
///     WITHOUT any DB write happening at that instant.
///
/// NOT autoDispose: the home tab lives inside an IndexedStack and we want
/// the timer + cached value to survive cross-tab navigation.
///
/// Ordering: results are sorted by `member.displayOrder` ascending, then
/// by `session.startTime` ascending, then by `member.id` for tiebreak.
/// This keeps the avatar stack visually stable across rebuilds.
final alwaysPresentMembersProvider =
    Provider<AsyncValue<List<AlwaysPresentMember>>>((ref) {
  // Force rebuild on `fronting_sessions` writes (debounced ticker).
  ref.watch(frontingTableTickerProvider);

  final activeSessions = ref.watch(activeSessionsProvider);
  final members = ref.watch(allMembersProvider);

  return activeSessions.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (sessions) => members.when(
      loading: () => const AsyncValue.loading(),
      error: AsyncValue.error,
      data: (memberList) {
        final now = DateTime.now();
        final byId = {for (final m in memberList) m.id: m};
        final qualifying = <AlwaysPresentMember>[];

        for (final session in sessions) {
          if (session.endTime != null) continue;
          if (session.sessionType != SessionType.normal) continue;
          if (session.isDeleted) continue;
          final memberId = session.memberId;
          if (memberId == null) continue;
          final member = byId[memberId];
          if (member == null) continue;

          final age = now.difference(session.startTime);
          final qualifies =
              member.isAlwaysFronting || age >= kAutoPromoteThreshold;
          if (!qualifies) continue;

          qualifying.add(AlwaysPresentMember(
            member: member,
            session: session,
            age: age,
          ));
        }

        qualifying.sort((a, b) {
          final byOrder = a.member.displayOrder.compareTo(b.member.displayOrder);
          if (byOrder != 0) return byOrder;
          final byStart = a.session.startTime.compareTo(b.session.startTime);
          if (byStart != 0) return byStart;
          return a.member.id.compareTo(b.member.id);
        });

        // Schedule a one-shot timer for the next session crossing the
        // auto-promote threshold among any not-yet-promoted active rows.
        // No DB write happens at the crossing moment, so without this the
        // header would never render until the user triggers a write.
        _scheduleThresholdTimer(ref, sessions, byId, now);

        return AsyncValue.data(List.unmodifiable(qualifying));
      },
    ),
  );
});

/// Scans the current [sessions] for the earliest moment a not-yet-promoted
/// active session would cross [kAutoPromoteThreshold], and schedules a
/// one-shot Timer to invalidate the provider at that wall-clock moment.
///
/// "Not yet promoted" means: open + normal + not-deleted + has a memberId
/// + member exists + member is NOT explicit-always-fronting + age below
/// threshold. Members already promoted via the explicit flag don't need
/// a timer — their qualification doesn't depend on the clock.
///
/// The timer is cancelled via `ref.onDispose` so provider invalidation
/// never leaks pending work.
void _scheduleThresholdTimer(
  Ref ref,
  List<FrontingSession> sessions,
  Map<String, Member> memberMap,
  DateTime now,
) {
  DateTime? earliestCrossing;
  for (final session in sessions) {
    if (session.endTime != null) continue;
    if (session.sessionType != SessionType.normal) continue;
    if (session.isDeleted) continue;
    final memberId = session.memberId;
    if (memberId == null) continue;
    final member = memberMap[memberId];
    if (member == null) continue;
    if (member.isAlwaysFronting) continue;

    final age = now.difference(session.startTime);
    if (age >= kAutoPromoteThreshold) continue;

    final crossing = session.startTime.add(kAutoPromoteThreshold);
    if (earliestCrossing == null || crossing.isBefore(earliestCrossing)) {
      earliestCrossing = crossing;
    }
  }

  if (earliestCrossing == null) return;

  // Guard against a zero/negative delay edge case (clock skew, racing
  // ticker rebuild) — schedule at least one frame out.
  var delay = earliestCrossing.difference(now);
  if (delay < Duration.zero) delay = Duration.zero;

  final timer = Timer(delay, () {
    // Provider invalidation triggers re-evaluation; the next pass will
    // find the now-promoted session and surface the member.
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);
}
