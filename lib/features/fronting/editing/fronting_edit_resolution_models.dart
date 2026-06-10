import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SessionType;
import 'package:prism_plurality/features/fronting/utils/session_time_bounds.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

/// How to resolve an overlap during editing.
/// In the per-member model, cross-member overlaps are valid and never prompted.
/// Only same-member self-overlaps reach resolution — the user can trim or cancel.
enum OverlapResolution { trim, cancel }

/// Strategy for handling the gap left when deleting a session.
enum FrontingDeleteStrategy {
  extendPrevious,
  extendNext,
  splitBetweenNeighbors,
  convertToUnknown,
  leaveGap;

  String get label => switch (this) {
    extendPrevious => 'Extend previous session',
    extendNext => 'Extend next session',
    splitBetweenNeighbors => 'Split time between neighbors',
    convertToUnknown => 'Convert to unknown fronter',
    leaveGap => 'Leave gap',
  };

  String get description => switch (this) {
    extendPrevious =>
      'The previous session will be extended to cover this time.',
    extendNext => 'The next session will be pulled back to cover this time.',
    splitBetweenNeighbors =>
      'The previous and next sessions will each take half.',
    convertToUnknown => 'Keep the time slot but remove the fronter.',
    leaveGap => 'Delete the session and leave a gap in the timeline.',
  };
}

/// How to handle a gap created by editing.
enum GapResolution { fillWithUnknown, leaveGap, cancel }

/// Info about a gap that would be created by an edit.
class GapInfo {
  final DateTime start;
  final DateTime end;
  final String? beforeSessionId;
  final String? afterSessionId;

  const GapInfo({
    required this.start,
    required this.end,
    this.beforeSessionId,
    this.afterSessionId,
  });

  Duration get duration => end.difference(start);
}

/// Context for a delete operation.
class FrontingDeleteContext {
  final FrontingSessionSnapshot session;
  final FrontingSessionSnapshot? previous;
  final FrontingSessionSnapshot? next;

  const FrontingDeleteContext({
    required this.session,
    this.previous,
    this.next,
  });

  List<FrontingDeleteStrategy> get availableStrategies {
    if (session.sessionType == SessionType.sleep) {
      return const [FrontingDeleteStrategy.leaveGap];
    }

    final strategies = <FrontingDeleteStrategy>[];
    if (previous != null) strategies.add(FrontingDeleteStrategy.extendPrevious);
    strategies.add(FrontingDeleteStrategy.convertToUnknown);
    strategies.add(FrontingDeleteStrategy.leaveGap);
    return strategies;
  }
}

/// Context for deleting a derived period.
///
/// Sessions fully inside get deleted, sessions overlapping one boundary
/// get trimmed, sessions straddling both get split. The chosen strategy
/// decides what fills the cleared slice.
class FrontingDeletePeriodContext {
  final DateTime periodStart;

  /// For an ongoing period this is the substituted "now" — callers
  /// should pass a fresh `DateTime.now()` at delete time, not the
  /// derivation-time bound, or a session that just ended will be
  /// classified as straddle-end and leave a microsecond ghost row
  /// after the slice.
  final DateTime periodEnd;

  /// Period reaches the trailing edge of the timeline with an open
  /// contributor. Drives `clearEnd` semantics for extendPrevious and
  /// `end: null` for the convertToUnknown row.
  final bool isOngoing;

  final List<FrontingSessionSnapshot> sessionsInPeriod;

  /// Sessions ending exactly at periodStart. Extended under
  /// extendPrevious.
  final List<FrontingSessionSnapshot> previousSessions;

  /// Sessions starting exactly at periodEnd. Reserved for parity with
  /// previousSessions; extendNext isn't surfaced today.
  final List<FrontingSessionSnapshot> nextSessions;

  const FrontingDeletePeriodContext({
    required this.periodStart,
    required this.periodEnd,
    required this.isOngoing,
    this.sessionsInPeriod = const [],
    this.previousSessions = const [],
    this.nextSessions = const [],
  });

  /// A session that starts before the slice and ends within it — i.e.
  /// a "previous side" extendPrevious can actually extend. Both-
  /// straddlers don't count: they're left intact, so their presence
  /// doesn't make the option meaningful on its own.
  bool get hasStraddleStartOnly {
    for (final s in sessionsInPeriod) {
      if (!s.start.isBefore(periodStart)) continue;
      final eff = s.end ?? farFutureSessionEnd;
      if (!eff.isAfter(periodEnd)) return true;
    }
    return false;
  }

  bool get hasStraddleEnd {
    for (final s in sessionsInPeriod) {
      if (s.end == null) return true;
      if (s.end!.isAfter(periodEnd)) return true;
    }
    return false;
  }

  List<FrontingDeleteStrategy> get availableStrategies {
    // Don't offer extendPrevious when only both-straddlers exist —
    // they're left intact under the strategy and the tap would be a
    // no-op.
    final hasPrev = previousSessions.isNotEmpty || hasStraddleStartOnly;
    final strategies = <FrontingDeleteStrategy>[];
    if (hasPrev) strategies.add(FrontingDeleteStrategy.extendPrevious);
    strategies.add(FrontingDeleteStrategy.convertToUnknown);
    strategies.add(FrontingDeleteStrategy.leaveGap);
    return strategies;
  }
}

/// Result of pre-save validation.
class FrontingEditValidationResult {
  final bool canSaveDirectly;
  final List<FrontingValidationIssue> issues;
  final List<FrontingSessionSnapshot> overlappingSessions;
  final List<GapInfo> gapsCreated;
  final List<FrontingSessionSnapshot> duplicates;

  const FrontingEditValidationResult({
    required this.canSaveDirectly,
    this.issues = const [],
    this.overlappingSessions = const [],
    this.gapsCreated = const [],
    this.duplicates = const [],
  });
}
