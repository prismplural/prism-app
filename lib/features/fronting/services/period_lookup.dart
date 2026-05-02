import 'package:prism_plurality/features/fronting/services/derive_periods.dart';

/// Find a [FrontingPeriod] in [periods] whose `sessionIds` exactly equals
/// the [sessionIds] set (order-independent, no superset / subset matches).
///
/// Returns null if no period matches. Used by the period detail screen to
/// resolve period-level fields (`alwaysPresentMembers`, `briefVisitors`,
/// `isOpenEnded`) from the live derived stream.
FrontingPeriod? findPeriodBySessionIds(
  List<FrontingPeriod> periods,
  List<String> sessionIds,
) {
  final target = sessionIds.toSet();
  for (final p in periods) {
    final candidate = p.sessionIds.toSet();
    if (candidate.length == target.length && candidate.containsAll(target)) {
      return p;
    }
  }
  return null;
}
