import 'package:prism_plurality/domain/models/fronting_session.dart';

/// Returns true when [session] overlaps another normal fronting session for a
/// different member.
///
/// Co-fronting is emergent in the per-member schema: each row represents one
/// member's continuous presence, so there is no durable row-level
/// "co-fronting" flag. Ranges are treated as half-open `[start, end)`, and a
/// null `endTime` is open-ended.
bool sessionsCoFront(
  FrontingSession session,
  Iterable<FrontingSession> others,
) {
  if (!_isCoFrontEligible(session)) return false;
  return others.any(
    (other) =>
        other.id != session.id &&
        _isCoFrontEligible(other) &&
        other.memberId != session.memberId &&
        _rangesOverlap(session, other),
  );
}

bool _isCoFrontEligible(FrontingSession session) =>
    !session.isDeleted && !session.isSleep && session.memberId != null;

bool _rangesOverlap(FrontingSession a, FrontingSession b) {
  final aStartsBeforeBEnds =
      b.endTime == null || a.startTime.isBefore(b.endTime!);
  final bStartsBeforeAEnds =
      a.endTime == null || b.startTime.isBefore(a.endTime!);
  return aStartsBeforeBEnds && bStartsBeforeAEnds;
}
