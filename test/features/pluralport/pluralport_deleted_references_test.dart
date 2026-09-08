import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

Json _source() => {
  'pluralport_version': '0.1',
  'producer': {'app': 'Foreign', 'app_id': 'foreign'},
  'systems': [
    {'id': 'system', 'name': 'System'},
  ],
  'members': [
    {'id': 'member', 'system_id': 'system', 'name': 'Deleted member'},
  ],
  'assets': [
    {'id': 'asset', 'kind': 'image', 'uri': 'https://example.invalid/image'},
  ],
  'front_events': [
    {
      'id': 'event',
      'system_id': 'system',
      'at': '2026-01-01T00:00:00Z',
      'assignments': [
        {'member_id': 'member', 'front_role': 'primary'},
      ],
    },
  ],
  'front_comments': [
    {
      'id': 'comment',
      'system_id': 'system',
      'front_event_id': 'event',
      'author_member_id': 'member',
      'target_time': '2026-01-01T00:00:00Z',
      'body': 'Keep the historical comment.',
      'created_at': '2026-01-01T00:00:00Z',
    },
  ],
  'taxonomy_terms': [
    {'id': 'term', 'system_id': 'system', 'kind': 'tag', 'name': 'Known tag'},
  ],
  'taxonomy_assignments': [
    {
      'id': 'taxonomy-member',
      'term_id': 'term',
      'subject_type': 'member',
      'subject_id': 'member',
    },
    {
      'id': 'taxonomy-custom',
      'term_id': 'term',
      'subject_type': 'custom',
      'subject_id': 'opaque-custom-id',
    },
  ],
  'chat': {
    'conversations': [
      {
        'id': 'conversation',
        'system_id': 'system',
        'kind': 'internal_chat',
        'creator_member_id': 'member',
        'participant_member_ids': ['member'],
      },
    ],
    'messages': [
      {
        'id': 'message',
        'conversation_id': 'conversation',
        'author_member_id': 'member',
        'body': 'Keep this source record archived.',
        'created_at': '2026-01-01T00:00:00Z',
      },
    ],
    'attachments': [
      {'id': 'attachment', 'message_id': 'message', 'asset_id': 'asset'},
    ],
    'reactions': [
      {
        'id': 'reaction',
        'message_id': 'message',
        'member_id': 'member',
        'value': '❤',
      },
    ],
  },
  'relationships': {
    'types': [
      {'id': 'type', 'system_id': 'system', 'name': 'partner'},
    ],
    'edges': [
      {
        'id': 'edge',
        'system_id': 'system',
        'type_id': 'type',
        'from_member_id': 'member',
        'to_member_id': 'member',
      },
    ],
  },
  'extensions': {
    'foreign': {
      'unknown_module': {'member_id': 'member', 'keep': true},
    },
  },
};

PluralPortImportPlan _plan(Json source) => PluralPortService.previewBytes(
  Uint8List.fromList(utf8.encode(jsonEncode(source))),
);

List<Json> _detached(Json envelope) =>
    (((envelope['extensions'] as Map)['prism'] as Map)['detached_records']
            as List)
        .cast<Json>();

void main() {
  test(
    'deleting bound native rows detaches known portable dependents without touching opaque data',
    () {
      final imported = _plan(_source());
      final clean = PluralPortExporter(
        imported.native,
        'local',
      ).build([imported.archive]);
      expect(() => _plan(clean.envelope), returnsNormally);
      expect(
        PluralPortMapper.rows(clean.envelope, 'front_events'),
        hasLength(1),
      );
      expect(
        PluralPortMapper.rows(clean.envelope, 'taxonomy_assignments'),
        hasLength(2),
      );

      // The imported member, conversation, and message bindings disappeared
      // from the native export after a local deletion. The preserved graph must
      // remain valid for reimport without treating opaque data as native data.
      final deletedNative = PluralPortMapper.clone(imported.native)
        ..['headmates'] = <Json>[]
        ..['conversations'] = <Json>[]
        ..['messages'] = <Json>[];
      final exported = PluralPortExporter(
        deletedNative,
        'local',
      ).build([imported.archive]);

      expect(PluralPortMapper.rows(exported.envelope, 'members'), isEmpty);
      expect(PluralPortMapper.rows(exported.envelope, 'front_events'), isEmpty);
      expect(
        PluralPortMapper.rows(
          exported.envelope,
          'taxonomy_assignments',
        ).map((row) => row['subject_type']),
        ['custom'],
      );
      expect(
        PluralPortMapper.rows(exported.envelope, 'chat.attachments'),
        isEmpty,
      );
      expect(
        PluralPortMapper.rows(exported.envelope, 'chat.reactions'),
        isEmpty,
      );
      expect(
        PluralPortMapper.rows(exported.envelope, 'relationships.edges'),
        isEmpty,
      );
      final comment = PluralPortMapper.rows(
        exported.envelope,
        'front_comments',
      ).single;
      expect(comment['front_event_id'], isNull);
      expect(comment['author_member_id'], isNull);
      expect(
        ((comment['extensions'] as Map)['prism'] as Map)['removed_references'],
        isNotEmpty,
      );
      expect(
        ((exported.envelope['extensions'] as Map)['foreign']
            as Map)['unknown_module'],
        {'member_id': 'member', 'keep': true},
      );

      final paths = _detached(
        exported.envelope,
      ).map((entry) => (entry['source'] as Map)['record_path']).toSet();
      expect(
        paths,
        containsAll([
          'front_events',
          'taxonomy_assignments',
          'chat.attachments',
          'chat.reactions',
          'relationships.edges',
        ]),
      );
      expect(() => _plan(exported.envelope), returnsNormally);

      final reimported = _plan(exported.envelope);
      final repeated = PluralPortExporter(
        reimported.native,
        'local',
      ).build([reimported.archive]);
      expect(PluralPortMapper.rows(repeated.envelope, 'members'), isEmpty);
      expect(_detached(repeated.envelope), _detached(exported.envelope));
      expect(() => _plan(repeated.envelope), returnsNormally);
    },
  );
}
