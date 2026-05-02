import 'package:prism_plurality/domain/models/fronting_session.dart';

enum FrontingIssueType {
  selfOverlap,
  duplicate,
  mergeableAdjacent,
  invalidRange,
  futureSession,
}

enum FrontingIssueSeverity { info, warning, error }

class FrontingValidationIssue {
  final String id;
  final FrontingIssueType type;
  final FrontingIssueSeverity severity;
  final List<String> sessionIds;
  final List<String> memberIds;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String summary;
  final String? details;

  const FrontingValidationIssue({
    required this.id,
    required this.type,
    required this.severity,
    required this.sessionIds,
    required this.memberIds,
    required this.rangeStart,
    required this.rangeEnd,
    required this.summary,
    this.details,
  });
}

/// Lightweight snapshot of a session for validator input.
/// Decouples validation from the full domain model.
class FrontingSessionSnapshot {
  final String id;
  final String? memberId;
  final DateTime start;
  final DateTime? end; // null = active
  final String? notes;
  final int? confidenceIndex;
  final SessionType sessionType;
  final SleepQuality? quality;
  final bool isHealthKitImport;
  final bool isDeleted;

  const FrontingSessionSnapshot({
    required this.id,
    required this.memberId,
    required this.start,
    this.end,
    this.notes,
    this.confidenceIndex,
    this.sessionType = SessionType.normal,
    this.quality,
    this.isHealthKitImport = false,
    this.isDeleted = false,
  });
}

extension FrontingSessionSnapshotConversion on FrontingSession {
  FrontingSessionSnapshot toSnapshot() => FrontingSessionSnapshot(
    id: id,
    memberId: memberId,
    start: startTime,
    end: endTime,
    notes: notes,
    confidenceIndex: confidence?.index,
    sessionType: sessionType,
    quality: quality,
    isHealthKitImport: isHealthKitImport,
    isDeleted: isDeleted,
  );
}
