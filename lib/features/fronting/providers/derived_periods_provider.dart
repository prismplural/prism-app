import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

/// Derived fronting periods for the unified history list view.
///
/// Memoized via Riverpod's natural caching: the provider recomputes only
/// when the upstream session stream emits a new list or the
/// [allMembersProvider] changes (the `is_always_fronting` lookup depends
/// on it). On every other rebuild the cached value is returned.
///
/// Source stream: [unifiedHistoryOverlapProvider] — the overlap query
/// from §4.6 step 1, NOT the row-paged `unifiedHistoryProvider`. The
/// difference matters: a 400-day continuous host whose session started
/// outside the recent-page would be missing from the row-paged stream
/// and the sweep would render the visible window as if the host weren't
/// fronting.
final derivedPeriodsProvider =
    Provider.autoDispose<AsyncValue<List<FrontingPeriod>>>((ref) {
  final bundleAsync = ref.watch(unifiedHistoryOverlapProvider);
  final membersAsync = ref.watch(allMembersProvider);

  return bundleAsync.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (bundle) {
      final members =
          membersAsync.whenOrNull(data: (list) => list) ?? const <Member>[];
      // Thread the provider's `rangeStart` through. Without this, a
      // 400-day continuous host (whose start was clamped by the DAO
      // query) would push the sweep's `rangeStart` 400 days back,
      // producing hundreds of midnight day-slices spanning the whole
      // interval.
      //
      // `now` is captured fresh at derivation, NOT at provider build.
      // It serves as BOTH the future-dated cutoff and the upper-bound
      // clamp for closed-session spans. The bundle no longer carries
      // a captured `rangeEnd` — that value was the root cause of the
      // captured-now class of bugs (see derive_periods.dart).
      final periods = computeDerivedPeriods(
        bundle.sessions,
        members,
        now: DateTime.now(),
        rangeStart: bundle.rangeStart,
      );
      return AsyncValue.data(periods);
    },
  );
});

/// Pure derivation entrypoint. Exposed for tests and for any future
/// surface that wants periods without going through the provider graph.
///
/// When [rangeStart] is omitted, it's inferred from the session set
/// (earliest start). The visible-window upper bound is always [now] —
/// there is no separate `rangeEnd`. The provider always passes an
/// explicit `rangeStart`; tests that want to exercise inferred-range
/// behavior can omit it.
List<FrontingPeriod> computeDerivedPeriods(
  List<FrontingSession> sessions,
  List<Member> members, {
  DateTime? now,
  Duration ephemeralThreshold = kEphemeralThreshold,
  DateTime? rangeStart,
}) {
  if (sessions.isEmpty) return const [];

  final memberMap = {for (final m in members) m.id: m};
  final nowAt = now ?? DateTime.now();

  DateTime effectiveRangeStart;
  if (rangeStart != null) {
    effectiveRangeStart = rangeStart;
  } else {
    // Range inferred from the session set: earliest start. The sweep
    // clamps every event to `[earliest, now]`. Used by tests that
    // want pure derivation without the provider's bounds.
    DateTime earliest = sessions.first.startTime;
    for (final s in sessions) {
      if (s.startTime.isBefore(earliest)) earliest = s.startTime;
    }
    effectiveRangeStart = earliest;
  }

  return deriveMaximalPeriods(DerivePeriodsInput(
    sessions: sessions,
    members: memberMap,
    rangeStart: effectiveRangeStart,
    now: nowAt,
    ephemeralThreshold: ephemeralThreshold,
  ));
}
