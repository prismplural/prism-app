import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_preservation.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

import 'harness.dart';

Json fixture() => {
  'pluralport_version': '0.1',
  'producer': {'app': 'Foreign', 'app_id': 'foreign'},
  'systems': [
    {
      'id': 's',
      'name': 'System',
      'settings': {
        'id': 'm',
        'member_id': 'm',
        'asset_id': 'missing',
        'nested': [
          {'id': 'm', 'member_id': 'unresolved'},
        ],
      },
    },
  ],
  'members': [
    {
      'id': 'm',
      'system_id': 's',
      'name': 'Member',
      'custom_property': {
        'id': 'm',
        'member_id': 'm',
        'asset_id': 'unresolved',
        'items': [
          {'id': 'm', 'member_id': 'unresolved'},
        ],
      },
    },
  ],
  'assets': [
    {'id': 'asset', 'kind': 'image', 'uri': 'https://example.invalid/image'},
  ],
  'groups': [
    {
      'id': 'group',
      'system_id': 's',
      'name': 'Group',
      'avatar_asset_id': 'asset',
    },
  ],
  'custom_fields': [
    {
      'id': 'field',
      'system_id': 's',
      'name': 'Payload',
      'field_type': 'text',
      'options': {'id': 'm', 'member_id': 'm', 'asset_id': 'unresolved'},
    },
  ],
  'custom_field_values': [
    {
      'id': 'value',
      'field_id': 'field',
      'subject_type': 'member',
      'subject_id': 'm',
      'value': {
        'id': 'm',
        'member_id': 'm',
        'asset_id': 'unresolved',
        'nested': [
          {'id': 'm', 'member_id': 'unresolved'},
        ],
      },
    },
  ],
  'front_periods': [
    {
      'id': 'period',
      'system_id': 's',
      'started_at': '2026-01-01T00:00:00Z',
      'assignments': [
        {
          'member_id': 'm',
          'front_role': 'member',
          'metadata': {'id': 'm', 'member_id': 'unresolved'},
        },
      ],
    },
  ],
  'taxonomy_terms': [
    {'id': 'term', 'system_id': 's', 'kind': 'custom', 'name': 'Term'},
  ],
  'taxonomy_assignments': [
    {
      'id': 'assignment',
      'term_id': 'term',
      'subject_type': 'custom',
      'subject_id': 'm',
      'payload': {'id': 'm', 'member_id': 'unresolved'},
    },
  ],
  'future_module': {
    'records': [
      {
        'id': 'm',
        'member_id': 'm',
        'asset_id': 'unresolved',
        'children': [
          {'id': 'm', 'member_id': 'unresolved'},
        ],
      },
    ],
  },
  'extensions': {
    'foreign': {'id': 'm', 'member_id': 'm', 'asset_id': 'unresolved'},
  },
};

PluralPortImportPlan plan(Json json) => PluralPortService.previewBytes(
  Uint8List.fromList(utf8.encode(jsonEncode(json))),
);

void expectOpaque(Json envelope) {
  final system = (envelope['systems'] as List).firstWhere(
    (system) => system['settings'] != null,
  );
  expect(system['settings']['id'], 'm');
  final member = (envelope['members'] as List).single;
  expect(member['custom_property']['member_id'], 'm');
  expect(member['custom_property']['items'][0]['id'], 'm');
  final field = (envelope['custom_fields'] as List).single;
  expect(field['options']['id'], 'm');
  expect(field['options']['asset_id'], 'unresolved');
  final value = (envelope['custom_field_values'] as List).single['value'];
  expect(value['id'], 'm');
  expect(value['member_id'], 'm');
  expect(value['nested'][0]['member_id'], 'unresolved');
  final assignment = (envelope['taxonomy_assignments'] as List).single;
  expect(assignment['subject_id'], 'm');
  expect(assignment['payload']['id'], 'm');
  expect((envelope['future_module'] as Map)['records'][0]['member_id'], 'm');
  expect((envelope['extensions'] as Map)['foreign']['asset_id'], 'unresolved');
}

void main() {
  test('accepts empty front-event assignments for a switch-out', () {
    final json = fixture()
      ..['front_events'] = [
        {
          'id': 'switch-out',
          'system_id': 's',
          'at': '2026-01-01T00:00:00Z',
          'assignments': [],
        },
      ];
    expect(() => plan(json), returnsNormally);
  });

  test(
    'preserves arbitrary JSON while remapping declared graph references',
    () async {
      final db = makeDb();
      addTearDown(db.close);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      );

      await service.importPlan(plan(fixture()));
      final native = (await makeExport(db).buildExport()).toJson();
      final memberId = PluralPortMapper.rows(native, 'headmates').single['id'];
      final retained = (await PluralPortPreservation(db).documents()).single;
      final envelope = retained['envelope'] as Json;

      expectOpaque(envelope);
      expect(
        (envelope['front_periods'] as List)
            .single['assignments'][0]['member_id'],
        memberId,
      );
      expect(
        (envelope['custom_field_values'] as List).single['subject_id'],
        memberId,
      );
      expect(
        (envelope['groups'] as List).single['avatar_asset_id'],
        (envelope['assets'] as List).single['id'],
      );

      final exported = PluralPortExporter(native, 'local').build([retained]);
      expectOpaque(exported.envelope);
      final reimported = plan(exported.envelope);
      expectOpaque(reimported.archive['envelope'] as Json);
    },
  );
}
