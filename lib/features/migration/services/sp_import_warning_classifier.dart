/// Classifies raw SP import warning strings into human-meaningful categories.
///
/// Classification is string-based (UI-layer only). First-match wins; the rule
/// ordering below is deliberately chosen so that specific patterns precede
/// generic ones — in particular, the avatar rule precedes the "not found" rule
/// so that ZIP-error messages that embed exception text don't misroute.
library;

enum SpImportWarningKind {
  avatars,
  missingReferences,
  customFrontAdjustments,
  encryptedMessages,
  dataQuality,
  syncEmission,
  other,
}

enum SpImportWarningSeverity { info, warning, error }

class SpImportWarningCategory {
  const SpImportWarningCategory({
    required this.kind,
    required this.severity,
    required this.warnings,
  });

  final SpImportWarningKind kind;
  final SpImportWarningSeverity severity;
  final List<String> warnings;

  bool get isEmpty => warnings.isEmpty;
  int get count => warnings.length;
}

class SpImportWarningClassifier {
  /// Sorts a flat list of warning strings into categories.
  ///
  /// Order returned matches [SpImportWarningKind] declaration order so UI
  /// rendering is stable. Empty categories are omitted from the result.
  ///
  /// Classification rules (first match wins):
  ///   1. avatar + (download | zip) | zip image | avatar zip → avatars
  ///   2. encrypted                  → encryptedMessages
  ///   3. no startTime | (front history + startTime) → dataQuality
  ///   4. sync emission | replay     → syncEmission
  ///   5. handled as notes | deleted in sp | custom front | custom fronts |
  ///      custom-front | sleep session | sp sleep | sleep entries |
  ///      imported timer | timers targeted → customFrontAdjustments
  ///   6. not found | skipped | cannot determine recipient → missingReferences
  ///   7. (fallback)                 → other
  static List<SpImportWarningCategory> classify(List<String> warnings) {
    if (warnings.isEmpty) return const [];

    final buckets = <SpImportWarningKind, List<String>>{};
    for (final kind in SpImportWarningKind.values) {
      buckets[kind] = <String>[];
    }

    for (final warning in warnings) {
      final lower = warning.toLowerCase();
      final kind = _classify(lower);
      buckets[kind]!.add(warning);
    }

    return SpImportWarningKind.values
        .map((kind) {
          final ws = buckets[kind]!;
          if (ws.isEmpty) return null;
          return SpImportWarningCategory(
            kind: kind,
            severity: _severityFor(kind),
            warnings: ws,
          );
        })
        .whereType<SpImportWarningCategory>()
        .toList();
  }

  static SpImportWarningKind _classify(String lower) {
    // Rule 1: avatar + (download | zip) | zip image | avatar zip
    if ((lower.contains('avatar') &&
            (lower.contains('download') || lower.contains('zip'))) ||
        lower.contains('zip image') ||
        lower.contains('avatar zip')) {
      return SpImportWarningKind.avatars;
    }
    // Rule 2: encrypted
    if (lower.contains('encrypted')) {
      return SpImportWarningKind.encryptedMessages;
    }
    // Rule 3: no starttime | (front history + starttime)
    if (lower.contains('no starttime') ||
        (lower.contains('front history') && lower.contains('starttime'))) {
      return SpImportWarningKind.dataQuality;
    }
    // Rule 4: sync emission | replay
    if (lower.contains('sync emission') || lower.contains('replay')) {
      return SpImportWarningKind.syncEmission;
    }
    // Rule 5: handled as notes | deleted in sp | custom front | custom fronts |
    //         custom-front (hyphenated variant) | sleep session | sp sleep |
    //         sleep entries | imported timer | timers targeted
    if (lower.contains('handled as notes') ||
        lower.contains('deleted in sp') ||
        lower.contains('custom front') ||
        lower.contains('custom fronts') ||
        lower.contains('custom-front') ||
        lower.contains('sleep session') ||
        lower.contains('sp sleep') ||
        lower.contains('sleep entries') ||
        lower.contains('imported timer') ||
        lower.contains('timers targeted')) {
      return SpImportWarningKind.customFrontAdjustments;
    }
    // Rule 6: not found | skipped | cannot determine recipient
    if (lower.contains('not found') ||
        lower.contains('skipped') ||
        lower.contains('cannot determine recipient')) {
      return SpImportWarningKind.missingReferences;
    }
    // Rule 7: fallback
    return SpImportWarningKind.other;
  }

  static SpImportWarningSeverity _severityFor(SpImportWarningKind kind) {
    return switch (kind) {
      SpImportWarningKind.avatars => SpImportWarningSeverity.warning,
      SpImportWarningKind.missingReferences => SpImportWarningSeverity.warning,
      SpImportWarningKind.customFrontAdjustments =>
        SpImportWarningSeverity.info,
      SpImportWarningKind.encryptedMessages => SpImportWarningSeverity.warning,
      SpImportWarningKind.dataQuality => SpImportWarningSeverity.warning,
      SpImportWarningKind.syncEmission => SpImportWarningSeverity.error,
      SpImportWarningKind.other => SpImportWarningSeverity.warning,
    };
  }
}
