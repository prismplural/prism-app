import 'package:prism_plurality/domain/models/models.dart';

/// Hint payload passed via go_router `state.extra` when navigating from a
/// list row to the period detail screen. Lets the header render
/// immediately without waiting for the per-session reads to resolve.
///
/// Period bounds are the FULL period extent (not the day-clamped slice
/// rendered on the list row), so a midnight-crossing period shows its
/// real range on the detail screen.
class PeriodDetailArgs {
  const PeriodDetailArgs({
    required this.activeMembers,
    required this.start,
    required this.end,
    required this.isOpenEnded,
    required this.alwaysPresentMembers,
  });

  final List<Member> activeMembers;
  final DateTime start;
  final DateTime end;
  final bool isOpenEnded;
  final List<Member> alwaysPresentMembers;
}
