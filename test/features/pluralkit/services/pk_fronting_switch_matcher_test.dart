import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_fronting_switch_matcher.dart';

PkFileSwitch _fileSwitch({
  required DateTime timestamp,
  required List<String> memberIds,
}) {
  return PkFileSwitch(timestamp: timestamp, memberIds: memberIds);
}

PKSwitch _apiSwitch({
  required String id,
  required DateTime timestamp,
  required List<String> memberIds,
}) {
  return PKSwitch(id: id, timestamp: timestamp, members: memberIds);
}

void main() {
  const matcher = PkFrontingSwitchMatcher();

  test('matches exact UTC instant and member-id set to API switch id', () {
    final fileSwitches = [
      _fileSwitch(
        timestamp: DateTime.parse('2026-01-01T05:00:00-05:00'),
        memberIds: ['bbbbb', 'aaaaa', 'aaaaa'],
      ),
    ];
    final apiSwitches = [
      _apiSwitch(
        id: 'api-switch-1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        memberIds: ['aaaaa', 'bbbbb'],
      ),
    ];

    final result = matcher.compare(
      fileSwitches: fileSwitches,
      apiSwitches: apiSwitches,
    );

    expect(result.exactMatchCount, 1);
    expect(result.apiSwitchIdsByFileIndex, {0: 'api-switch-1'});
    expect(result.fileOnlyCount, 0);
    expect(result.apiOnlyCount, 0);
    expect(result.ambiguousCount, 0);
    expect(result.canonicalizationSafe, isTrue);
    expect(result.exactMatches.single.key.memberIds, ['aaaaa', 'bbbbb']);
    expect(
      result.exactMatches.single.key.timestampUtc,
      DateTime.utc(2026, 1, 1, 10),
    );
  });

  test('duplicate exact keys on either side are ambiguous and not guessed', () {
    final fileSwitch = _fileSwitch(
      timestamp: DateTime.utc(2026, 1, 1, 10),
      memberIds: ['aaaaa'],
    );
    final apiSwitch = _apiSwitch(
      id: 'api-switch-1',
      timestamp: DateTime.utc(2026, 1, 1, 10),
      memberIds: ['aaaaa'],
    );

    final duplicateApi = matcher.compare(
      fileSwitches: [fileSwitch],
      apiSwitches: [
        apiSwitch,
        _apiSwitch(
          id: 'api-switch-2',
          timestamp: DateTime.utc(2026, 1, 1, 10),
          memberIds: ['aaaaa'],
        ),
      ],
    );

    expect(duplicateApi.exactMatchCount, 0);
    expect(duplicateApi.apiSwitchIdsByFileIndex, isEmpty);
    expect(duplicateApi.ambiguousCount, 1);
    expect(duplicateApi.ambiguousKeys.single.fileIndexes, [0]);
    expect(duplicateApi.ambiguousKeys.single.apiIndexes, [0, 1]);
    expect(duplicateApi.ambiguousKeys.single.apiSwitchIds, [
      'api-switch-1',
      'api-switch-2',
    ]);
    expect(duplicateApi.canonicalizationSafe, isFalse);

    final duplicateFile = matcher.compare(
      fileSwitches: [fileSwitch, fileSwitch],
      apiSwitches: [apiSwitch],
    );

    expect(duplicateFile.exactMatchCount, 0);
    expect(duplicateFile.apiSwitchIdsByFileIndex, isEmpty);
    expect(duplicateFile.ambiguousCount, 1);
    expect(duplicateFile.ambiguousKeys.single.fileIndexes, [0, 1]);
    expect(duplicateFile.ambiguousKeys.single.apiIndexes, [0]);
    expect(duplicateFile.canonicalizationSafe, isFalse);
  });

  test('file-only switch is reported as an unsafe mismatch', () {
    final result = matcher.compare(
      fileSwitches: [
        _fileSwitch(
          timestamp: DateTime.utc(2026, 1, 1, 10),
          memberIds: ['aaaaa'],
        ),
      ],
      apiSwitches: const [],
    );

    expect(result.exactMatchCount, 0);
    expect(result.fileOnlyCount, 1);
    expect(result.fileOnlySwitches.single.fileIndex, 0);
    expect(result.apiOnlyCount, 0);
    expect(result.canonicalizationSafe, isFalse);
  });

  test('API-only switches outside file range are stale-file warnings', () {
    final fileSwitches = [
      _fileSwitch(
        timestamp: DateTime.utc(2026, 1, 1, 10),
        memberIds: ['aaaaa'],
      ),
      _fileSwitch(
        timestamp: DateTime.utc(2026, 1, 2, 10),
        memberIds: ['bbbbb'],
      ),
    ];
    final apiSwitches = [
      _apiSwitch(
        id: 'api-switch-1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        memberIds: ['aaaaa'],
      ),
      _apiSwitch(
        id: 'api-switch-2',
        timestamp: DateTime.utc(2026, 1, 2, 10),
        memberIds: ['bbbbb'],
      ),
      _apiSwitch(
        id: 'newer-api-switch',
        timestamp: DateTime.utc(2026, 1, 3, 10),
        memberIds: ['ccccc'],
      ),
    ];

    final result = matcher.compare(
      fileSwitches: fileSwitches,
      apiSwitches: apiSwitches,
    );

    expect(result.exactMatchCount, 2);
    expect(result.fileOnlyCount, 0);
    expect(result.apiOnlyCount, 1);
    expect(result.apiOnlyInsideFileRangeCount, 0);
    expect(result.apiOnlyOutsideFileRangeCount, 1);
    expect(result.hasApiOnlyOutsideFileRange, isTrue);
    expect(
      result.apiOnlyOutsideFileRange.single.apiSwitchId,
      'newer-api-switch',
    );
    expect(result.apiOnlyOutsideFileRange.single.outsideFileRange, isTrue);
    expect(result.canonicalizationSafe, isTrue);
  });

  test('microsecond timestamps are preserved instead of truncated', () {
    final fileTimestamp = DateTime.utc(2026, 1, 1, 10, 0, 0, 123, 456);
    final apiTimestamp = DateTime.utc(2026, 1, 1, 10, 0, 0, 123);

    final result = matcher.compare(
      fileSwitches: [
        _fileSwitch(timestamp: fileTimestamp, memberIds: ['aaaaa']),
      ],
      apiSwitches: [
        _apiSwitch(
          id: 'api-switch-1',
          timestamp: apiTimestamp,
          memberIds: ['aaaaa'],
        ),
      ],
    );

    expect(result.exactMatchCount, 0);
    expect(result.fileOnlyCount, 1);
    expect(result.apiOnlyCount, 1);
    expect(
      result.fileOnlySwitches.single.key.timestampMicrosecondsUtc,
      fileTimestamp.microsecondsSinceEpoch,
    );
    expect(
      result.fileOnlySwitches.single.key.timestampMicrosecondsUtc % 1000,
      456,
    );
    expect(
      result.fileOnlySwitches.single.key.timestampUtc,
      DateTime.utc(2026, 1, 1, 10, 0, 0, 123, 456),
    );
    expect(result.canonicalizationSafe, isFalse);
  });
}
