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
    return _validator.validate(snapshots);
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
    if (from != null && to != null) {
      return _repository.getSessionsBetween(from, to);
    }
    return _repository.getFrontingSessions();
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
    );
  }
}
