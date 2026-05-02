import 'fronting_validation_config.dart';
import 'fronting_validation_models.dart';
import 'fronting_validation_rules.dart';

/// Facade that orchestrates all fronting-session detection rules and returns a
/// sorted, deduplicated list of [FrontingValidationIssue]s.
///
/// Always-on rules:
///   - [detectInvalidRanges] — end not strictly after start
///   - [detectSelfOverlap] — same member has overlapping sessions
///
/// Configurable rules (controlled via [FrontingValidationConfig]):
///   - [detectDuplicates] — probable duplicate sessions for the same member
///   - [detectMergeableAdjacent] — consecutive same-member sessions with tiny gap
///   - [detectFutureSessions] — sessions with a start or end in the future
///
/// Issues are sorted by [FrontingValidationIssue.rangeStart] ascending.
///
/// Cross-member overlaps are valid by design and are NOT flagged.
/// "Nobody fronting" gaps are also valid and are NOT flagged.
class FrontingSessionValidator {
  final FrontingValidationConfig config;

  const FrontingSessionValidator({
    this.config = const FrontingValidationConfig(),
  });

  List<FrontingValidationIssue> validate(
    List<FrontingSessionSnapshot> sessions, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final active = sessions.where((s) => !s.isDeleted).toList();

    final issues = <FrontingValidationIssue>[
      ...detectInvalidRanges(active),
      if (config.detectSelfOverlaps) ...detectSelfOverlap(active),
      if (config.detectDuplicates) ...detectDuplicates(active, config),
      if (config.detectMergeableAdjacent) ...detectMergeableAdjacent(active, config),
      if (config.detectFutureSessions) ...detectFutureSessions(active, effectiveNow, config),
    ];

    issues.sort((a, b) => a.rangeStart.compareTo(b.rangeStart));
    return issues;
  }
}
