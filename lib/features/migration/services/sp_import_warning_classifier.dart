/// Classifies raw SP import warning strings into human-meaningful categories.
///
/// Classification is string-based (UI-layer only). First-match wins; specific
/// patterns precede generic ones — the avatar rule runs before "not found" so
/// that ZIP-error messages embedding exception text don't misroute.
library;

import 'package:prism_plurality/features/migration/services/sp_importer.dart';

enum SpImportWarningKind {
  avatars,
  retiredMedia,
  missingReferences,
  duplicateMembers,
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
  /// Return order matches [SpImportWarningKind] declaration order so the UI
  /// renders categories stably. Empty categories are omitted.
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
    if (ImportResult.isRetiredMediaWarning(lower)) {
      return SpImportWarningKind.retiredMedia;
    }
    if ((lower.contains('avatar') &&
            (lower.contains('download') || lower.contains('zip'))) ||
        lower.contains('zip image') ||
        lower.contains('avatar zip')) {
      return SpImportWarningKind.avatars;
    }
    if (lower.contains('encrypted')) {
      return SpImportWarningKind.encryptedMessages;
    }
    if (lower.contains('no starttime') ||
        (lower.contains('front history') && lower.contains('starttime'))) {
      return SpImportWarningKind.dataQuality;
    }
    if (lower.contains('sync emission') || lower.contains('replay')) {
      return SpImportWarningKind.syncEmission;
    }
    if (lower.contains('shares a pluralkit link')) {
      return SpImportWarningKind.duplicateMembers;
    }
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
    if (lower.contains('not found') ||
        lower.contains('skipped') ||
        lower.contains('cannot determine recipient')) {
      return SpImportWarningKind.missingReferences;
    }
    return SpImportWarningKind.other;
  }

  static SpImportWarningSeverity _severityFor(SpImportWarningKind kind) {
    return switch (kind) {
      SpImportWarningKind.avatars => SpImportWarningSeverity.warning,
      SpImportWarningKind.retiredMedia => SpImportWarningSeverity.warning,
      SpImportWarningKind.missingReferences => SpImportWarningSeverity.warning,
      SpImportWarningKind.duplicateMembers => SpImportWarningSeverity.warning,
      SpImportWarningKind.customFrontAdjustments =>
        SpImportWarningSeverity.info,
      SpImportWarningKind.encryptedMessages => SpImportWarningSeverity.warning,
      SpImportWarningKind.dataQuality => SpImportWarningSeverity.warning,
      SpImportWarningKind.syncEmission => SpImportWarningSeverity.error,
      SpImportWarningKind.other => SpImportWarningSeverity.warning,
    };
  }
}
