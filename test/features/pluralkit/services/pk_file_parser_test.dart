/// Unit tests for [parsePkExportFile], focused on the H7 hid→UUID
/// normalization of `groups[].members`, plus previously-uncovered parser
/// contracts: version gating, malformed-entry skipping, and switch member
/// ids staying as hids.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_file_parser.dart';

// Shared identity constants for the export fixtures built inline below.
const _alphaHid = 'aaaaa';
const _betaHid = 'bbbbb';
const _alphaUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _betaUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _groupUuid = '99999999-9999-4999-8999-999999999999';

/// Build a minimal valid v2 export with two members (Alpha/Beta) and a single
/// group whose `members` array is supplied by the caller (so each test can
/// vary the hid/uuid mix).
String _exportJson({
  required List<String> groupMembers,
  int version = 2,
  List<Map<String, dynamic>>? membersOverride,
  List<Map<String, dynamic>>? switchesOverride,
}) {
  return jsonEncode({
    'version': version,
    'id': 'pkfix',
    'uuid': '11111111-1111-4111-8111-111111111111',
    'name': 'Fixture System',
    'members':
        membersOverride ??
        [
          {'id': _alphaHid, 'uuid': _alphaUuid, 'name': 'Alpha'},
          {'id': _betaHid, 'uuid': _betaUuid, 'name': 'Beta'},
        ],
    'groups': [
      {
        'id': 'grpaa',
        'uuid': _groupUuid,
        'name': 'Group',
        'members': groupMembers,
      },
    ],
    'switches': switchesOverride ?? const <Map<String, dynamic>>[],
  });
}

void main() {
  group('group member hid → uuid translation', () {
    test('translates short IDs to UUIDs (happy path)', () async {
      final export = await parsePkExportFile(
        _exportJson(groupMembers: [_alphaHid, _betaHid]),
      );

      expect(export.groups.single.memberIds, [_alphaUuid, _betaUuid]);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('keeps already-UUID entries verbatim (live-API / old-fixture shape)',
        () async {
      final export = await parsePkExportFile(
        _exportJson(groupMembers: [_alphaUuid, _betaUuid]),
      );

      expect(export.groups.single.memberIds, [_alphaUuid, _betaUuid]);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('handles a mixed hid + uuid members array', () async {
      final export = await parsePkExportFile(
        _exportJson(groupMembers: [_alphaHid, _betaUuid]),
      );

      expect(export.groups.single.memberIds, [_alphaUuid, _betaUuid]);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('drops AND counts an unresolvable short ID', () async {
      // `zzzzz` is a well-formed hid but has no member entry in the export.
      final export = await parsePkExportFile(
        _exportJson(groupMembers: [_alphaHid, 'zzzzz']),
      );

      expect(export.groups.single.memberIds, [_alphaUuid]);
      expect(export.unresolvableGroupMemberRefs, 1);
    });

    test('tolerates uppercase and dashed hid forms', () async {
      // The export's member table uses the canonical lowercase hid; the group
      // reference is uppercase/dashed (a hand-edited or API-derived form).
      final export = await parsePkExportFile(
        _exportJson(groupMembers: ['AA-AAA', 'B-BBBB']),
      );

      expect(export.groups.single.memberIds, [_alphaUuid, _betaUuid]);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('6-char hids resolve too (new entities get 6)', () async {
      final export = await parsePkExportFile(
        _exportJson(
          groupMembers: ['abcdef'],
          membersOverride: [
            {'id': 'abcdef', 'uuid': _alphaUuid, 'name': 'Alpha'},
          ],
        ),
      );

      expect(export.groups.single.memberIds, [_alphaUuid]);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('preserves null memberIds as "unknown" without counting', () async {
      // No `members` key at all → PKGroup.memberIds == null (privacy/unknown).
      final raw = jsonEncode({
        'version': 2,
        'id': 'pkfix',
        'uuid': '11111111-1111-4111-8111-111111111111',
        'name': 'Fixture System',
        'members': [
          {'id': _alphaHid, 'uuid': _alphaUuid, 'name': 'Alpha'},
        ],
        'groups': [
          {'id': 'grpaa', 'uuid': _groupUuid, 'name': 'Group'},
        ],
        'switches': const <Map<String, dynamic>>[],
      });

      final export = await parsePkExportFile(raw);

      expect(export.groups.single.memberIds, isNull);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('empty members list stays empty (legitimately no members)', () async {
      final export = await parsePkExportFile(
        _exportJson(groupMembers: const []),
      );

      expect(export.groups.single.memberIds, isEmpty);
      expect(export.unresolvableGroupMemberRefs, 0);
    });
  });

  group('switches are parsed with hids untranslated', () {
    test('switch member IDs stay as short IDs (matcher is hid-based)',
        () async {
      // Switch matching (PkFrontingSwitchKey) and the file-switch provenance
      // id (_pkFileSwitchSourceId) compare file hids against the API's
      // short-ID `members`, so these MUST remain hids — even when an
      // identical hid→uuid mapping exists for the group path.
      final export = await parsePkExportFile(
        _exportJson(
          groupMembers: [_alphaHid],
          switchesOverride: [
            {
              'timestamp': '2026-04-01T10:00:00.123456Z',
              'members': [_alphaHid, _betaHid],
            },
          ],
        ),
      );

      expect(export.switches, hasLength(1));
      expect(export.switches.single.memberIds, [_alphaHid, _betaHid]);
      // Group path translated to UUID; switch path did not.
      expect(export.groups.single.memberIds, [_alphaUuid]);
    });

    test('switch timestamp and absent id round-trip', () async {
      final export = await parsePkExportFile(
        _exportJson(
          groupMembers: const [],
          switchesOverride: [
            {
              'timestamp': '2026-04-01T12:00:00Z',
              'members': [_alphaHid],
            },
          ],
        ),
      );

      final sw = export.switches.single;
      expect(sw.id, isNull); // exports carry no switch id
      expect(
        sw.timestamp.toUtc().toIso8601String(),
        '2026-04-01T12:00:00.000Z',
      );
      expect(sw.memberIds, [_alphaHid]);
    });
  });

  group('system / members round-trip', () {
    test('parses system and member basics', () async {
      final export = await parsePkExportFile(
        _exportJson(groupMembers: [_alphaHid]),
      );

      expect(export.system.id, 'pkfix');
      expect(export.system.name, 'Fixture System');
      expect(export.members.map((m) => m.id).toList(), [_alphaHid, _betaHid]);
      expect(export.members.map((m) => m.uuid).toList(), [
        _alphaUuid,
        _betaUuid,
      ]);
    });
  });

  group('version gating', () {
    test('rejects version != 2', () async {
      expect(
        () => parsePkExportFile(_exportJson(groupMembers: const [], version: 1)),
        throwsA(isA<PkFileParseException>()),
      );
    });

    test('rejects a missing version', () async {
      final raw = jsonEncode({
        'id': 'pkfix',
        'uuid': '11111111-1111-4111-8111-111111111111',
        'members': const [],
        'groups': const [],
        'switches': const [],
      });
      expect(
        () => parsePkExportFile(raw),
        throwsA(isA<PkFileParseException>()),
      );
    });

    test('rejects non-JSON input', () async {
      expect(
        () => parsePkExportFile('not json at all {'),
        throwsA(isA<PkFileParseException>()),
      );
    });

    test('rejects a non-object root', () async {
      expect(
        () => parsePkExportFile('[1, 2, 3]'),
        throwsA(isA<PkFileParseException>()),
      );
    });
  });

  group('malformed-entry skip behavior (pinned, not changed by this patch)', () {
    test('a malformed member entry is skipped, the rest still parse', () async {
      // PKMember.fromJson throws when `uuid`/`name` is missing → that single
      // entry is silently dropped. Alpha (well-formed) still imports. This
      // documents existing behavior; the patch does not change it.
      final export = await parsePkExportFile(
        _exportJson(
          groupMembers: [_alphaHid],
          membersOverride: [
            {'id': _alphaHid, 'uuid': _alphaUuid, 'name': 'Alpha'},
            {'id': 'badly', 'name': 'No UUID'}, // missing uuid → skipped
          ],
        ),
      );

      expect(export.members.map((m) => m.id).toList(), [_alphaHid]);
      // The dropped member never entered the hid→uuid map, so a group ref to
      // it would be counted unresolvable — but here only Alpha is referenced.
      expect(export.groups.single.memberIds, [_alphaUuid]);
      expect(export.unresolvableGroupMemberRefs, 0);
    });

    test('a switch with a non-string timestamp is skipped silently', () async {
      final export = await parsePkExportFile(
        _exportJson(
          groupMembers: const [],
          switchesOverride: [
            {'timestamp': 12345, 'members': const []}, // not a String → skip
            {
              'timestamp': '2026-04-01T10:00:00Z',
              'members': [_alphaHid],
            },
          ],
        ),
      );

      expect(export.switches, hasLength(1));
      expect(export.switches.single.memberIds, [_alphaHid]);
    });

    test('a group ref that is neither uuid nor a plausible hid is dropped',
        () async {
      // `not-a-real-id` normalizes to a non-alpha / wrong-length string, so it
      // is neither UUID-shaped nor a 5–6 alpha hid → counted unresolvable.
      final export = await parsePkExportFile(
        _exportJson(groupMembers: [_alphaHid, 'not-a-real-id']),
      );

      expect(export.groups.single.memberIds, [_alphaUuid]);
      expect(export.unresolvableGroupMemberRefs, 1);
    });
  });
}
