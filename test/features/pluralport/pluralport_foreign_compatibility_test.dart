import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

typedef Json = Map<String, dynamic>;

Json _document({
  List<Json> members = const [],
  List<Json> groups = const [],
  List<Json> memberships = const [],
  List<Json> fields = const [],
  List<Json> values = const [],
  List<Json> notes = const [],
  List<Json> fronts = const [],
  List<Json> assets = const [],
}) => {
  'pluralport_version': '0.1',
  'exported_at': '2026-01-01T00:00:00+00:00',
  'producer': {'app': 'Compatibility', 'app_id': 'compatibility'},
  'capabilities': {'modules': <String>[]},
  'systems': [
    {'id': 's', 'name': 'System'},
  ],
  'members': members,
  'groups': groups,
  'group_memberships': memberships,
  'custom_fields': fields,
  'custom_field_values': values,
  'notes': notes,
  'front_periods': fronts,
  'assets': assets,
  'extensions': <String, dynamic>{},
};

PluralPortBundle _bundle(Json doc, {Map<String, Uint8List>? files}) =>
    PluralPortBundle(doc, files: files ?? {});

void main() {
  test('empty-list record extensions import and survive a round trip', () {
    final doc = _document(
      members: [
        {'id': 'm', 'name': 'Member', 'extensions': <dynamic>[]},
      ],
      groups: [
        {'id': 'g', 'name': 'Group', 'extensions': <dynamic>[]},
      ],
      memberships: [
        {
          'id': 'gm',
          'group_id': 'g',
          'member_id': 'm',
          'extensions': <dynamic>[],
        },
      ],
      fields: [
        {
          'id': 'f',
          'name': 'Text',
          'field_type': 'text',
          'extensions': <dynamic>[],
        },
      ],
      values: [
        {
          'id': 'v',
          'field_id': 'f',
          'subject_type': 'member',
          'subject_id': 'm',
          'value': 'value',
          'extensions': <dynamic>[],
        },
      ],
      notes: [
        {
          'id': 'n',
          'title': 'Note',
          'body': 'Body',
          'member_id': 'm',
          'extensions': <dynamic>[],
        },
      ],
      fronts: [
        {
          'id': 'p',
          'started_at': '2026-01-01T00:00:00Z',
          'ended_at': '2026-01-01T01:00:00Z',
          'assignments': [
            {'member_id': 'm'},
          ],
          'extensions': <dynamic>[],
        },
      ],
    );
    final bundle = _bundle(doc);
    final plan = PluralPortService.previewBytes(bundle.encode());
    expect(PluralPortMapper.rows(plan.native, 'headmates'), hasLength(1));
    expect(PluralPortMapper.rows(plan.native, 'memberGroups'), hasLength(1));
    expect(
      PluralPortMapper.rows(plan.native, 'customFieldValues'),
      hasLength(1),
    );
    expect(PluralPortMapper.rows(plan.native, 'frontSessions'), hasLength(1));
    expect(
      plan.warnings.where((warning) => warning.contains('preserved_only')),
      isEmpty,
    );
    expect(
      PluralPortMapper.rows(
        plan.archive['envelope'] as Json,
        'groups',
      ).single['extensions'],
      isEmpty,
    );

    final exported = PluralPortExporter(
      plan.native,
      'local',
    ).build([plan.archive]);
    expect(
      PluralPortMapper.rows(exported.envelope, 'groups').single['extensions'],
      <dynamic>[],
    );
    expect(
      PluralPortMapper.rows(exported.envelope, 'notes').single['extensions'],
      <dynamic>[],
    );
    final reimported = PluralPortMapper.plan(exported);
    expect(PluralPortMapper.rows(reimported.native, 'headmates'), hasLength(1));
    expect(
      PluralPortMapper.rows(reimported.native, 'frontSessions'),
      hasLength(1),
    );
  });

  test('non-empty non-object extensions are rejected before app data', () {
    for (final bad in [
      <dynamic>['unexpected'],
      'not-an-object',
      42,
    ]) {
      final doc = _document(
        groups: [
          {'id': 'g', 'name': 'Group', 'extensions': bad},
        ],
      );
      expect(
        () => PluralPortService.previewBytes(_bundle(doc).encode()),
        throwsFormatException,
        reason: bad.toString(),
      );
    }
  });

  test('empty-list extensions survive optional-reference cleanup', () {
    final doc = _document(
      members: [
        {'id': 'm', 'name': 'Member'},
      ],
      notes: [
        {
          'id': 'n',
          'title': 'Note',
          'body': 'Body',
          'member_id': 'm',
          'extensions': <dynamic>[],
        },
      ],
    );
    final plan = PluralPortMapper.plan(_bundle(doc));
    final deleted = PluralPortMapper.clone(plan.native)
      ..['headmates'] = <Json>[];
    final exported = PluralPortExporter(deleted, 'local').build([plan.archive]);
    final note = PluralPortMapper.rows(exported.envelope, 'notes').single;
    expect(note['member_id'], isNull);
    expect(
      ((note['extensions'] as Map)['prism'] as Map)['removed_references'],
      isNotEmpty,
    );
  });

  test('duplicate single-value field rows keep the last native value', () {
    final doc = _document(
      members: [
        {'id': 'm', 'name': 'Member'},
      ],
      fields: [
        {'id': 'f', 'name': 'Text', 'field_type': 'text'},
      ],
      values: [
        {
          'id': 'v1',
          'field_id': 'f',
          'subject_type': 'member',
          'subject_id': 'm',
          'value': 'first',
        },
        {
          'id': 'v2',
          'field_id': 'f',
          'subject_type': 'member',
          'subject_id': 'm',
          'value': 'last',
        },
      ],
    );
    final plan = PluralPortMapper.plan(_bundle(doc));
    final nativeValues = PluralPortMapper.rows(
      plan.native,
      'customFieldValues',
    );
    expect(nativeValues, hasLength(1));
    expect(nativeValues.single['value'], 'last');
    expect(
      plan.warnings.where(
        (warning) => warning.startsWith('preserved_only: custom_field_values/'),
      ),
      hasLength(1),
    );

    final exported = PluralPortExporter(
      plan.native,
      'local',
    ).build([plan.archive]);
    expect(
      PluralPortMapper.rows(
        exported.envelope,
        'custom_field_values',
      ).map((value) => value['value']).toList(),
      ['first', 'last'],
    );
  });

  test('select options accept list and choices-object shapes', () {
    final doc = _document(
      members: [
        {'id': 'm', 'name': 'Member'},
      ],
      fields: [
        {
          'id': 'list-field',
          'name': 'List choices',
          'field_type': 'select',
          'options': ['A', 'B'],
        },
        {
          'id': 'object-field',
          'name': 'Object choices',
          'field_type': 'multiselect',
          'options': {
            'choices': ['A', 'B'],
            'unknown': {'keep': true},
          },
        },
      ],
      values: [
        {
          'id': 'list-value',
          'field_id': 'list-field',
          'subject_type': 'member',
          'subject_id': 'm',
          'value': 'A',
        },
        {
          'id': 'object-value',
          'field_id': 'object-field',
          'subject_type': 'member',
          'subject_id': 'm',
          'value': ['A', 'B'],
        },
      ],
    );
    final plan = PluralPortMapper.plan(_bundle(doc));
    expect(PluralPortMapper.rows(plan.native, 'customFields'), hasLength(2));
    expect(
      PluralPortMapper.rows(plan.native, 'customFieldValues'),
      hasLength(2),
    );
    expect(
      plan.warnings.where((warning) => warning.contains('preserved_only')),
      isEmpty,
    );

    final unchanged = PluralPortExporter(
      plan.native,
      'local',
    ).build([plan.archive]);
    final objectField = PluralPortMapper.rows(
      unchanged.envelope,
      'custom_fields',
    ).singleWhere((field) => field['name'] == 'Object choices');
    expect(objectField['options']['choices'], ['A', 'B']);
    expect(objectField['options']['unknown'], {'keep': true});

    final edited = PluralPortMapper.clone(plan.native);
    final nativeField = PluralPortMapper.rows(
      edited,
      'customFields',
    ).singleWhere((field) => field['id'] == objectField['id']);
    final config = jsonDecode(nativeField['typeConfigJson'] as String) as Json;
    ((config['options'] as List).first as Map)['label'] = 'Renamed';
    nativeField['typeConfigJson'] = jsonEncode(config);
    final exported = PluralPortExporter(edited, 'local').build([plan.archive]);
    final editedField = PluralPortMapper.rows(
      exported.envelope,
      'custom_fields',
    ).singleWhere((field) => field['id'] == objectField['id']);
    expect(editedField['options'], isA<Map>());
    expect(editedField['options']['choices'], ['Renamed', 'B']);
    expect(editedField['options']['unknown'], {'keep': true});
    expect(
      PluralPortMapper.rows(
        exported.envelope,
        'custom_field_values',
      ).singleWhere((value) => value['field_id'] == objectField['id'])['value'],
      ['Renamed', 'B'],
    );
  });

  test('archive-local uri assets resolve; remote and unsafe paths do not', () {
    final localBytes = Uint8List.fromList([1, 2, 3, 4]);
    final digest = sha256.convert(localBytes).toString();
    final doc = _document(
      members: [
        {'id': 'm', 'name': 'Member', 'avatar_asset_id': 'local'},
      ],
      assets: [
        {
          'id': 'local',
          'kind': 'avatar',
          'mime_type': 'image/png',
          'uri': 'media/avatar.png',
          'sha256': digest,
          'size_bytes': localBytes.length,
        },
        {
          'id': 'remote',
          'kind': 'avatar',
          'uri': 'https://example.invalid/x.png',
        },
        {'id': 'parent', 'kind': 'avatar', 'uri': '../secret.png'},
        {'id': 'absolute', 'kind': 'avatar', 'uri': '/absolute.png'},
        {'id': 'scheme', 'kind': 'avatar', 'uri': 'file:///tmp/x.png'},
        {'id': 'windows', 'kind': 'avatar', 'uri': 'C:/x.png'},
      ],
    );
    final bundle = _bundle(doc, files: {'media/avatar.png': localBytes});
    final plan = PluralPortMapper.plan(bundle);
    final mapped = PluralPortMapper.rows(
      plan.archive['envelope'] as Json,
      'assets',
    );
    final local = mapped.singleWhere(
      (asset) => asset['bundle_path'] == 'media/avatar.png',
    );
    expect(local['bundle_path'], 'media/avatar.png');
    expect(
      PluralPortMapper.rows(
        plan.native,
        'headmates',
      ).single['profilePhotoData'],
      base64Encode(localBytes),
    );
    for (final uri in [
      'https://example.invalid/x.png',
      '../secret.png',
      '/absolute.png',
      'file:///tmp/x.png',
      'C:/x.png',
    ]) {
      final asset = mapped.singleWhere((asset) => asset['uri'] == uri);
      expect(bundle.assetBytes(asset), isNull, reason: uri);
    }
    expect(
      plan.warnings.where((warning) => warning.startsWith('asset_uri_only')),
      hasLength(5),
    );
    expect(
      (plan.archive['files'] as Map).containsKey('media/avatar.png'),
      isTrue,
    );
    for (final unsafe in [
      '../x',
      '/x',
      'file:///x',
      'https://example.invalid/x',
      'C:/x',
      '//host/x',
      r'a\b',
      '',
    ]) {
      expect(PluralPortBundle.localBundlePath(unsafe), isNull, reason: unsafe);
    }
    expect(
      PluralPortBundle.localBundlePath('media/avatar.png'),
      'media/avatar.png',
    );

    final declaredBytes = Uint8List.fromList([9, 8, 7]);
    final declaredDigest = sha256.convert(declaredBytes).toString();
    final precedence = _bundle(
      {
        ...doc,
        'assets': [
          {
            'id': 'both',
            'kind': 'avatar',
            'bundle_path': 'media/declared.png',
            'uri': 'media/other.png',
            'sha256': declaredDigest,
            'size_bytes': declaredBytes.length,
          },
        ],
      },
      files: {
        'media/declared.png': declaredBytes,
        'media/other.png': localBytes,
      },
    );
    final precedenceAsset = PluralPortMapper.rows(
      precedence.envelope,
      'assets',
    ).single;
    expect(precedence.assetBytes(precedenceAsset), declaredBytes);

    final malformed = _bundle({
      ...doc,
      'assets': [
        {'id': 'bad', 'kind': 'avatar', 'bundle_path': 42},
        {
          'id': 'bad-sheaf',
          'kind': 'avatar',
          'extensions': {
            'sheaf': {'bundle_path': 42},
          },
        },
      ],
    });
    for (final asset in PluralPortMapper.rows(malformed.envelope, 'assets')) {
      expect(
        () => malformed.assetBytes(asset),
        throwsFormatException,
        reason: asset['id'].toString(),
      );
    }
  });
}
