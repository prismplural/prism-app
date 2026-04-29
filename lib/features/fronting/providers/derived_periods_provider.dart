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
      // Thread the provider's bounds through. Without this, a 400-day
      // continuous host (whose start was clamped by the DAO query)
      // would push the sweep's `rangeStart` 400 days back, producing
      // hundreds of midnight day-slices spanning the whole interval.
      //
      // `now` is captured fresh at derivation, NOT at provider build.
      // The future-dated cutoff inside `deriveMaximalPeriods` keys off
      // `input.now` so a row inserted after subscription (start ≈ live
      // wall clock, but > captured-at-build now) round-trips cleanly.
      // Open sessions still extend to `max(now, rangeEnd)` which is
      // simply `now` here since `rangeEnd` is itself ≈ now.
      final periods = computeDerivedPeriods(
        bundle.sessions,
        members,
        now: DateTime.now(),
        rangeStart: bundle.rangeStart,
        rangeEnd: bundle.rangeEnd,
      );
      return AsyncValue.data(periods);
    },
  );
});

/// Pure derivation entrypoint. Exposed for tests and for any future
/// surface that wants periods without going through the provider graph.
///
/// When [rangeStart] / [rangeEnd] are omitted, they're inferred from the
/// session set (earliest start / latest end). The provider always passes
/// explicit bounds; tests that want to exercise inferred-range behavior
/// can omit them.
List<FrontingPeriod> computeDerivedPeriods(
  List<FrontingSession> sessions,
  List<Member> members, {
  DateTime? now,
  Duration ephemeralThreshold = kEphemeralThreshold,
  DateTime? rangeStart,
  DateTime? rangeEnd,
}) {
  if (sessions.isEmpty) return const [];

  final memberMap = {for (final m in members) m.id: m};
  final nowAt = now ?? DateTime.now();

  DateTime effectiveRangeStart;
  DateTime effectiveRangeEnd;
  if (rangeStart != null && rangeEnd != null) {
    effectiveRangeStart = rangeStart;
    effectiveRangeEnd = rangeEnd;
  } else {
    // Range inferred from the session set: earliest start to latest end
    // (or now for open-ended). The sweep clamps every event to this
    // window. Used by tests that want pure derivation without the
    // provider's bounds.
    DateTime earliest = sessions.first.startTime;
    DateTime latest = nowAt;
    for (final s in sessions) {
      if (s.startTime.isBefore(earliest)) earliest = s.startTime;
      final end = s.endTime ?? nowAt;
      if (end.isAfter(latest)) latest = end;
    }
    effectiveRangeStart = rangeStart ?? earliest;
    effectiveRangeEnd = rangeEnd ?? latest;
  }

  return deriveMaximalPeriods(DerivePeriodsInput(
    sessions: sessions,
    members: memberMap,
    rangeStart: effectiveRangeStart,
    rangeEnd: effectiveRangeEnd,
    now: nowAt,
    ephemeralThreshold: ephemeralThreshold,
  ));
}
