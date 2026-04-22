import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_session_validator.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_models.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_planner.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_preview.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_change_executor.dart';

class FrontingSanitizerService {
  final FrontingSessionRepository _repository;
  final FrontingSessionValidator _validator;
  final FrontingFixPlanner _planner;
  final FrontingChangeExecutor _executor;

  const FrontingSanitizerService({
    required FrontingSessionRepository repository,
    required FrontingSessionValidator validator,
    required FrontingFixPlanner planner,
    required FrontingChangeExecutor executor,
  }) : _repository = repository,
       _validator = validator,
       _planner = planner,
       _executor = executor;

  /// Scan all sessions (or a subset) for issues.
  Future<List<FrontingValidationIssue>> scan({
    String? memberId,
    DateTime? from,
    DateTime? to,
  }) async {
    final sessions = await _loadSessions(
      memberId: memberId,
      from: from,
      to: to,
    );
    final snapshots = sessions.map(toSnapshot).toList();
    final frontingSnapshots = snapshots
        .where((snapshot) => snapshot.sessionType == SessionType.normal)
        .toList();
    final sleepSnapshots = snapshots
        .where((snapshot) => snapshot.sessionType == SessionType.sleep)
        .toList();

    final issues = _validator.validate(frontingSnapshots);
    return _normalizeSleepCoveredGaps(issues, sleepSnapshots);
  }

  /// Get fix plans for a specific issue.
  Future<List<FrontingFixPlan>> plansForIssue(
    FrontingValidationIssue issue,
  ) async {
    final sessions = await _repository.getFrontingSessions();
    final snapshots = sessions.map(toSnapshot).toList();
    return _planner.plansForIssue(issue, snapshots);
  }

  /// Build a human-readable preview for a fix plan.
  FrontingFixPreview buildPreview(FrontingFixPlan plan) {
    return _planner.buildPreview(plan);
  }

  /// Apply a fix plan through normal repository mutations.
  Future<void> applyPlan(FrontingFixPlan plan) async {
    await _executor.execute(plan.changes);
  }

  Future<List<FrontingSession>> _loadSessions({
    String? memberId,
    DateTime? from,
    DateTime? to,
  }) async {
    if (memberId != null) {
      return _repository.getSessionsForMember(memberId);
    }
    final sessions = await _repository.getAllSessions();
    if (from != null && to != null) {
      return sessions
          .where((session) => _sessionOverlapsRange(session, from, to))
          .toList();
    }
    return sessions;
  }

  List<FrontingValidationIssue> _normalizeSleepCoveredGaps(
    List<FrontingValidationIssue> issues,
    List<FrontingSessionSnapshot> sleepSnapshots,
  ) {
    if (sleepSnapshots.isEmpty) return issues;

    final normalized = <FrontingValidationIssue>[];
    for (final issue in issues) {
      if (issue.type != FrontingIssueType.gap) {
        normalized.add(issue);
        continue;
      }

      normalized.addAll(_subtractSleepCoverageFromGap(issue, sleepSnapshots));
    }
    return normalized;
  }

  List<FrontingValidationIssue> _subtractSleepCoverageFromGap(
    FrontingValidationIssue issue,
    List<FrontingSessionSnapshot> sleepSnapshots,
  ) {
    final coverage = sleepSnapshots
        .map((sleep) {
          final start = sleep.start.isAfter(issue.rangeStart)
              ? sleep.start
              : issue.rangeStart;
          final effectiveEnd = sleep.end ?? issue.rangeEnd;
          final end = effectiveEnd.isBefore(issue.rangeEnd)
              ? effectiveEnd
              : issue.rangeEnd;
          return _TimeRange(start: start, end: end);
        })
        .where((range) => range.start.isBefore(range.end))
        .toList();

    if (coverage.isEmpty) return [issue];

    coverage.sort((a, b) => a.start.compareTo(b.start));
    final mergedCoverage = <_TimeRange>[];
    for (final range in coverage) {
      if (mergedCoverage.isEmpty ||
          range.start.isAfter(mergedCoverage.last.end)) {
        mergedCoverage.add(range);
        continue;
      }

      final previous = mergedCoverage.removeLast();
      final end = range.end.isAfter(previous.end) ? range.end : previous.end;
      mergedCoverage.add(_TimeRange(start: previous.start, end: end));
    }

    final uncovered = <_TimeRange>[];
    var cursor = issue.rangeStart;
    for (final covered in mergedCoverage) {
      if (covered.start.isAfter(cursor)) {
        uncovered.add(_TimeRange(start: cursor, end: covered.start));
      }
      if (covered.end.isAfter(cursor)) {
        cursor = covered.end;
      }
    }
    if (cursor.isBefore(issue.rangeEnd)) {
      uncovered.add(_TimeRange(start: cursor, end: issue.rangeEnd));
    }

    if (uncovered.isEmpty) return const [];
    if (uncovered.length == 1 &&
        uncovered.first.start == issue.rangeStart &&
        uncovered.first.end == issue.rangeEnd) {
      return [issue];
    }

    return uncovered
        .map(
          (range) => FrontingValidationIssue(
            id: '${issue.id}:${range.start.microsecondsSinceEpoch}-${range.end.microsecondsSinceEpoch}',
            type: issue.type,
            severity: issue.severity,
            sessionIds: issue.sessionIds,
            memberIds: issue.memberIds,
            rangeStart: range.start,
            rangeEnd: range.end,
            summary: issue.summary,
            details: _gapDetails(range.end.difference(range.start)),
          ),
        )
        .toList();
  }

  bool _sessionOverlapsRange(
    FrontingSession session,
    DateTime start,
    DateTime end,
  ) {
    final sessionEnd = session.endTime;
    return !session.startTime.isAfter(end) &&
        (sessionEnd == null || !sessionEnd.isBefore(start));
  }

  String _gapDetails(Duration gap) {
    return 'Gap duration: ${gap.inMinutes}m ${gap.inSeconds % 60}s';
  }

  static FrontingSessionSnapshot toSnapshot(FrontingSession s) {
    return FrontingSessionSnapshot(
      id: s.id,
      memberId: s.memberId,
      start: s.startTime,
      end: s.endTime,
      coFronterIds: s.coFronterIds,
      notes: s.notes,
      confidenceIndex: s.confidence?.index,
      sessionType: s.sessionType,
      quality: s.quality,
      isHealthKitImport: s.isHealthKitImport,
      isDeleted: s.isDeleted,
    );
  }
}

class _TimeRange {
  const _TimeRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
