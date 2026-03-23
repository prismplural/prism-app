enum FrontingTimingMode {
  flexible,
  strict;

  Duration get gapThreshold => switch (this) {
    FrontingTimingMode.flexible => const Duration(minutes: 5),
    FrontingTimingMode.strict => Duration.zero,
  };

  Duration get adjacentMergeThreshold => const Duration(seconds: 60);
}

class FrontingValidationConfig {
  final FrontingTimingMode timingMode;
  final Duration duplicateTolerance;
  final Duration futureTolerance;
  final bool detectGaps;
  final bool detectDuplicates;
  final bool detectMergeableAdjacent;
  final bool detectFutureSessions;

  const FrontingValidationConfig({
    this.timingMode = FrontingTimingMode.flexible,
    this.duplicateTolerance = const Duration(seconds: 60),
    this.futureTolerance = Duration.zero,
    this.detectGaps = true,
    this.detectDuplicates = true,
    this.detectMergeableAdjacent = true,
    this.detectFutureSessions = true,
  });

  Duration get reportableGapThreshold => timingMode.gapThreshold;
  Duration get mergeableGapThreshold => timingMode.adjacentMergeThreshold;
}
