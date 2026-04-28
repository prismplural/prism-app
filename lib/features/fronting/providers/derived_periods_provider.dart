import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

/// Derived fronting periods for the unified history list view.
///
/// Memoized via Riverpod's natural caching: the provider recomputes only
/// when the upstream `unifiedHistoryProvider` emits a new session list or
/// the `allMembersProvider` changes (the `is_always_fronting` lookup
/// depends on it). On every other rebuild the cached value is returned.
///
/// Range covered = the bounds inferred from the session list itself
/// (earliest start clamped to the earliest session, latest end / now). For
/// 1A this matches the behavior of the existing list which paginates by a
/// session-count window. A future refactor can switch to an explicit
/// (rangeStart, rangeEnd) family parameter when the list view gains
/// date-range scrubbing.
final derivedPeriodsProvider =
    Provider.autoDispose<AsyncValue<List<FrontingPeriod>>>((ref) {
  final sessionsAsync = ref.watch(unifiedHistoryProvider);
  final membersAsync = ref.watch(allMembersProvider);

  return sessionsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (sessions) {
      final members =
          membersAsync.whenOrNull(data: (list) => list) ?? const <Member>[];
      final periods = computeDerivedPeriods(sessions, members);
      return AsyncValue.data(periods);
    },
  );
});

/// Pure derivation entrypoint. Exposed for tests and for any future
/// surface that wants periods without going through the provider graph.
List<FrontingPeriod> computeDerivedPeriods(
  List<FrontingSession> sessions,
  List<Member> members, {
  DateTime? now,
  Duration ephemeralThreshold = kEphemeralThreshold,
}) {
  if (sessions.isEmpty) return const [];

  final memberMap = {for (final m in members) m.id: m};
  final nowAt = now ?? DateTime.now();

  // Range is inferred from the session set: earliest start to latest end
  // (or now for open-ended). The sweep clamps every event to this window
  // anyway, so a slightly oversized range is harmless.
  DateTime earliest = sessions.first.startTime;
  DateTime latest = nowAt;
  for (final s in sessions) {
    if (s.startTime.isBefore(earliest)) earliest = s.startTime;
    final end = s.endTime ?? nowAt;
    if (end.isAfter(latest)) latest = end;
  }

  return deriveMaximalPeriods(DerivePeriodsInput(
    sessions: sessions,
    members: memberMap,
    rangeStart: earliest,
    rangeEnd: latest,
    now: nowAt,
    ephemeralThreshold: ephemeralThreshold,
  ));
}
