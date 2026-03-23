import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';

enum FrontingFixType {
  trimEarlier,
  trimLater,
  deleteDuplicate,
  mergeAdjacent,
  fillGapWithUnknown,
  leaveGap,
  splitIntoCofronting,
  swapStartEnd,
  clampToNow,
  deleteSession,
  markForManualReview,
}

class FrontingFixPlan {
  final String id;
  final FrontingFixType type;
  final String title;
  final String description;
  final List<String> affectedSessionIds;
  final List<FrontingSessionChange> changes;

  const FrontingFixPlan({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.affectedSessionIds,
    required this.changes,
  });
}
