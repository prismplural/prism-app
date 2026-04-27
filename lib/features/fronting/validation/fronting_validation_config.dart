import 'package:prism_plurality/domain/models/system_settings.dart';

// FrontingTimingMode is defined in domain/models/system_settings.dart
export 'package:prism_plurality/domain/models/system_settings.dart'
    show FrontingTimingMode;

class FrontingValidationConfig {
  final FrontingTimingMode timingMode;
  final Duration duplicateTolerance;
  final Duration futureTolerance;
  final bool detectDuplicates;
  final bool detectMergeableAdjacent;
  final bool detectFutureSessions;
  final bool detectSelfOverlaps;

  const FrontingValidationConfig({
    this.timingMode = FrontingTimingMode.flexible,
    this.duplicateTolerance = const Duration(seconds: 60),
    this.futureTolerance = Duration.zero,
    this.detectDuplicates = true,
    this.detectMergeableAdjacent = true,
    this.detectFutureSessions = true,
    this.detectSelfOverlaps = true,
  });

  Duration get mergeableGapThreshold => timingMode.adjacentMergeThreshold;
}
