import 'package:prism_plurality/domain/models/fronting_session.dart'
    show SessionType;
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

/// How to resolve an overlap during editing.
enum OverlapResolution { trim, makeCoFronting, cancel }

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
    if (next != null) strategies.add(FrontingDeleteStrategy.extendNext);
    if (previous != null && next != null && session.end != null) {
      strategies.add(FrontingDeleteStrategy.splitBetweenNeighbors);
    }
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
