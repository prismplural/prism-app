import 'package:collection/collection.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';

const _stringListEq = ListEquality<String>();

/// Canonical identity for matching file-export switches to API switches.
///
/// PluralKit export/API timestamps are compared as UTC instants at Dart's
/// microsecond precision, and member IDs are treated as a sorted set.
class PkFrontingSwitchKey implements Comparable<PkFrontingSwitchKey> {
  final DateTime timestampUtc;
  final int timestampMicrosecondsUtc;
  final List<String> memberIds;

  factory PkFrontingSwitchKey(DateTime timestamp, Iterable<String> memberIds) {
    final timestampMicrosecondsUtc = timestamp.toUtc().microsecondsSinceEpoch;
    final canonicalMemberIds = memberIds.toSet().toList()..sort();
    return PkFrontingSwitchKey._(
      timestampUtc: DateTime.fromMicrosecondsSinceEpoch(
        timestampMicrosecondsUtc,
        isUtc: true,
      ),
      timestampMicrosecondsUtc: timestampMicrosecondsUtc,
      memberIds: List.unmodifiable(canonicalMemberIds),
    );
  }

  const PkFrontingSwitchKey._({
    required this.timestampUtc,
    required this.timestampMicrosecondsUtc,
    required this.memberIds,
  });

  factory PkFrontingSwitchKey.fromFile(PkFileSwitch switchEntry) {
    return PkFrontingSwitchKey(switchEntry.timestamp, switchEntry.memberIds);
  }

  factory PkFrontingSwitchKey.fromApi(PKSwitch switchEntry) {
    return PkFrontingSwitchKey(switchEntry.timestamp, switchEntry.members);
  }

  @override
  int compareTo(PkFrontingSwitchKey other) {
    final timestampComparison = timestampMicrosecondsUtc.compareTo(
      other.timestampMicrosecondsUtc,
    );
    if (timestampComparison != 0) return timestampComparison;

    final lengthComparison = memberIds.length.compareTo(other.memberIds.length);
    if (lengthComparison != 0) return lengthComparison;

    for (var i = 0; i < memberIds.length; i++) {
      final memberComparison = memberIds[i].compareTo(other.memberIds[i]);
      if (memberComparison != 0) return memberComparison;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PkFrontingSwitchKey &&
            timestampMicrosecondsUtc == other.timestampMicrosecondsUtc &&
            _stringListEq.equals(memberIds, other.memberIds);
  }

  @override
  int get hashCode =>
      Object.hash(timestampMicrosecondsUtc, Object.hashAll(memberIds));

  @override
  String toString() {
    return 'PkFrontingSwitchKey('
        'timestampUtc: ${timestampUtc.toIso8601String()}, '
        'memberIds: $memberIds'
        ')';
  }
}

class PkFrontingSwitchMatch {
  final int fileIndex;
  final int apiIndex;
  final PkFileSwitch fileSwitch;
  final PKSwitch apiSwitch;
  final PkFrontingSwitchKey key;

  const PkFrontingSwitchMatch({
    required this.fileIndex,
    required this.apiIndex,
    required this.fileSwitch,
    required this.apiSwitch,
    required this.key,
  });

  String get apiSwitchId => apiSwitch.id;
}

class PkFileOnlySwitch {
  final int fileIndex;
  final PkFileSwitch fileSwitch;
  final PkFrontingSwitchKey key;

  const PkFileOnlySwitch({
    required this.fileIndex,
    required this.fileSwitch,
    required this.key,
  });
}

class PkApiOnlySwitch {
  final int apiIndex;
  final PKSwitch apiSwitch;
  final PkFrontingSwitchKey key;
  final bool outsideFileRange;

  const PkApiOnlySwitch({
    required this.apiIndex,
    required this.apiSwitch,
    required this.key,
    required this.outsideFileRange,
  });

  String get apiSwitchId => apiSwitch.id;
}

class PkFrontingSwitchAmbiguity {
  final PkFrontingSwitchKey key;
  final List<int> fileIndexes;
  final List<int> apiIndexes;
  final List<PkFileSwitch> fileSwitches;
  final List<PKSwitch> apiSwitches;

  PkFrontingSwitchAmbiguity({
    required this.key,
    required Iterable<int> fileIndexes,
    required Iterable<int> apiIndexes,
    required Iterable<PkFileSwitch> fileSwitches,
    required Iterable<PKSwitch> apiSwitches,
  }) : fileIndexes = List.unmodifiable(fileIndexes),
       apiIndexes = List.unmodifiable(apiIndexes),
       fileSwitches = List.unmodifiable(fileSwitches),
       apiSwitches = List.unmodifiable(apiSwitches);

  int get fileCount => fileIndexes.length;
  int get apiCount => apiIndexes.length;
  List<String> get apiSwitchIds =>
      List.unmodifiable(apiSwitches.map((switchEntry) => switchEntry.id));
}

class PkFrontingSwitchMatchResult {
  final List<PkFrontingSwitchMatch> exactMatches;
  final List<PkFileOnlySwitch> fileOnlySwitches;
  final List<PkApiOnlySwitch> apiOnlySwitches;
  final List<PkApiOnlySwitch> apiOnlyInsideFileRange;
  final List<PkApiOnlySwitch> apiOnlyOutsideFileRange;
  final List<PkFrontingSwitchAmbiguity> ambiguousKeys;

  PkFrontingSwitchMatchResult._({
    required Iterable<PkFrontingSwitchMatch> exactMatches,
    required Iterable<PkFileOnlySwitch> fileOnlySwitches,
    required Iterable<PkApiOnlySwitch> apiOnlySwitches,
    required Iterable<PkApiOnlySwitch> apiOnlyInsideFileRange,
    required Iterable<PkApiOnlySwitch> apiOnlyOutsideFileRange,
    required Iterable<PkFrontingSwitchAmbiguity> ambiguousKeys,
  }) : exactMatches = List.unmodifiable(exactMatches),
       fileOnlySwitches = List.unmodifiable(fileOnlySwitches),
       apiOnlySwitches = List.unmodifiable(apiOnlySwitches),
       apiOnlyInsideFileRange = List.unmodifiable(apiOnlyInsideFileRange),
       apiOnlyOutsideFileRange = List.unmodifiable(apiOnlyOutsideFileRange),
       ambiguousKeys = List.unmodifiable(ambiguousKeys);

  int get exactMatchCount => exactMatches.length;
  int get fileOnlyCount => fileOnlySwitches.length;
  int get apiOnlyCount => apiOnlySwitches.length;
  int get apiOnlyInsideFileRangeCount => apiOnlyInsideFileRange.length;
  int get apiOnlyOutsideFileRangeCount => apiOnlyOutsideFileRange.length;
  int get ambiguousCount => ambiguousKeys.length;
  bool get hasApiOnlyOutsideFileRange => apiOnlyOutsideFileRange.isNotEmpty;

  /// True when every file switch has a unique API id and there are no
  /// unmatched API switches within the file's timestamp range.
  ///
  /// API-only switches outside the file range are reported separately as a
  /// stale/partial-file signal and do not by themselves make file switch
  /// canonicalization unsafe.
  bool get canonicalizationSafe =>
      ambiguousKeys.isEmpty &&
      fileOnlySwitches.isEmpty &&
      apiOnlyInsideFileRange.isEmpty;

  Map<int, String> get apiSwitchIdsByFileIndex {
    return Map.unmodifiable({
      for (final match in exactMatches) match.fileIndex: match.apiSwitchId,
    });
  }
}

class PkFrontingSwitchMatcher {
  const PkFrontingSwitchMatcher();

  PkFrontingSwitchMatchResult compare({
    required List<PkFileSwitch> fileSwitches,
    required List<PKSwitch> apiSwitches,
  }) {
    final fileByKey = <PkFrontingSwitchKey, List<_IndexedFileSwitch>>{};
    final apiByKey = <PkFrontingSwitchKey, List<_IndexedApiSwitch>>{};

    for (var i = 0; i < fileSwitches.length; i++) {
      final fileSwitch = fileSwitches[i];
      final key = PkFrontingSwitchKey.fromFile(fileSwitch);
      fileByKey
          .putIfAbsent(key, () => <_IndexedFileSwitch>[])
          .add(_IndexedFileSwitch(index: i, switchEntry: fileSwitch, key: key));
    }

    for (var i = 0; i < apiSwitches.length; i++) {
      final apiSwitch = apiSwitches[i];
      final key = PkFrontingSwitchKey.fromApi(apiSwitch);
      apiByKey
          .putIfAbsent(key, () => <_IndexedApiSwitch>[])
          .add(_IndexedApiSwitch(index: i, switchEntry: apiSwitch, key: key));
    }

    final keys = <PkFrontingSwitchKey>{
      ...fileByKey.keys,
      ...apiByKey.keys,
    }.toList()..sort();

    final fileRange = _FileSwitchRange.from(fileByKey.values);
    final exactMatches = <PkFrontingSwitchMatch>[];
    final fileOnlySwitches = <PkFileOnlySwitch>[];
    final apiOnlySwitches = <PkApiOnlySwitch>[];
    final apiOnlyInsideFileRange = <PkApiOnlySwitch>[];
    final apiOnlyOutsideFileRange = <PkApiOnlySwitch>[];
    final ambiguousKeys = <PkFrontingSwitchAmbiguity>[];

    for (final key in keys) {
      final fileEntries = fileByKey[key] ?? const <_IndexedFileSwitch>[];
      final apiEntries = apiByKey[key] ?? const <_IndexedApiSwitch>[];

      if (fileEntries.length > 1 || apiEntries.length > 1) {
        ambiguousKeys.add(
          PkFrontingSwitchAmbiguity(
            key: key,
            fileIndexes: fileEntries.map((entry) => entry.index),
            apiIndexes: apiEntries.map((entry) => entry.index),
            fileSwitches: fileEntries.map((entry) => entry.switchEntry),
            apiSwitches: apiEntries.map((entry) => entry.switchEntry),
          ),
        );
        continue;
      }

      if (fileEntries.length == 1 && apiEntries.length == 1) {
        exactMatches.add(
          PkFrontingSwitchMatch(
            fileIndex: fileEntries.single.index,
            apiIndex: apiEntries.single.index,
            fileSwitch: fileEntries.single.switchEntry,
            apiSwitch: apiEntries.single.switchEntry,
            key: key,
          ),
        );
        continue;
      }

      if (fileEntries.length == 1) {
        fileOnlySwitches.add(
          PkFileOnlySwitch(
            fileIndex: fileEntries.single.index,
            fileSwitch: fileEntries.single.switchEntry,
            key: key,
          ),
        );
        continue;
      }

      if (apiEntries.length == 1) {
        final outsideFileRange = fileRange?.isOutside(key) ?? false;
        final apiOnly = PkApiOnlySwitch(
          apiIndex: apiEntries.single.index,
          apiSwitch: apiEntries.single.switchEntry,
          key: key,
          outsideFileRange: outsideFileRange,
        );
        apiOnlySwitches.add(apiOnly);
        if (outsideFileRange) {
          apiOnlyOutsideFileRange.add(apiOnly);
        } else {
          apiOnlyInsideFileRange.add(apiOnly);
        }
      }
    }

    return PkFrontingSwitchMatchResult._(
      exactMatches: exactMatches,
      fileOnlySwitches: fileOnlySwitches,
      apiOnlySwitches: apiOnlySwitches,
      apiOnlyInsideFileRange: apiOnlyInsideFileRange,
      apiOnlyOutsideFileRange: apiOnlyOutsideFileRange,
      ambiguousKeys: ambiguousKeys,
    );
  }
}

class _IndexedFileSwitch {
  final int index;
  final PkFileSwitch switchEntry;
  final PkFrontingSwitchKey key;

  const _IndexedFileSwitch({
    required this.index,
    required this.switchEntry,
    required this.key,
  });
}

class _IndexedApiSwitch {
  final int index;
  final PKSwitch switchEntry;
  final PkFrontingSwitchKey key;

  const _IndexedApiSwitch({
    required this.index,
    required this.switchEntry,
    required this.key,
  });
}

class _FileSwitchRange {
  final int minTimestampMicrosecondsUtc;
  final int maxTimestampMicrosecondsUtc;

  const _FileSwitchRange({
    required this.minTimestampMicrosecondsUtc,
    required this.maxTimestampMicrosecondsUtc,
  });

  static _FileSwitchRange? from(
    Iterable<List<_IndexedFileSwitch>> fileEntriesByKey,
  ) {
    int? minTimestampMicrosecondsUtc;
    int? maxTimestampMicrosecondsUtc;

    for (final entries in fileEntriesByKey) {
      for (final entry in entries) {
        final timestamp = entry.key.timestampMicrosecondsUtc;
        if (minTimestampMicrosecondsUtc == null ||
            timestamp < minTimestampMicrosecondsUtc) {
          minTimestampMicrosecondsUtc = timestamp;
        }
        if (maxTimestampMicrosecondsUtc == null ||
            timestamp > maxTimestampMicrosecondsUtc) {
          maxTimestampMicrosecondsUtc = timestamp;
        }
      }
    }

    if (minTimestampMicrosecondsUtc == null ||
        maxTimestampMicrosecondsUtc == null) {
      return null;
    }

    return _FileSwitchRange(
      minTimestampMicrosecondsUtc: minTimestampMicrosecondsUtc,
      maxTimestampMicrosecondsUtc: maxTimestampMicrosecondsUtc,
    );
  }

  bool isOutside(PkFrontingSwitchKey key) {
    return key.timestampMicrosecondsUtc < minTimestampMicrosecondsUtc ||
        key.timestampMicrosecondsUtc > maxTimestampMicrosecondsUtc;
  }
}
