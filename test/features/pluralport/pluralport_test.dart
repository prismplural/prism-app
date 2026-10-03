import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_exporter.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_preservation.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';
import 'harness.dart';

Json fixture() => {
  'openplural_version': '0.1',
  'producer': {'app': 'Example', 'app_id': 'example'},
  'systems': [
    <String, dynamic>{'id': 's', 'name': 'System'},
  ],
  'members': [
    {
      'id': 'm',
      'system_id': 's',
      'name': 'Alex',
      'description': 'Original bio',
      'created_at': '2026-01-01T00:00:00Z',
      'extensions': {
        'foreign': {
          'mood': 'calm',
          'nested': {'id': 'unaltered'},
        },
      },
    },
  ],
  'notes': [
    {
      'id': 'n',
      'system_id': 's',
      'member_id': 'm',
      'body': 'Journal',
      'title': 'Entry',
      'created_at': '2026-01-01T00:00:00Z',
    },
  ],
  'front_periods': [
    {
      'id': 'f',
      'system_id': 's',
      'started_at': '2026-01-01T00:00:00Z',
      'ended_at': '2026-01-01T01:00:00Z',
      'assignments': [
        {'member_id': 'm', 'front_role': 'primary', 'confidence': 0.72},
      ],
    },
  ],
  'extensions': {
    'foreign': {'future': 42},
  },
  'polls': {
    'definitions': [
      {'id': 'poll', 'question': 'keep this'},
    ],
  },
};
PluralPortImportPlan plan(Json json) => PluralPortService.previewBytes(
  Uint8List.fromList(utf8.encode(jsonEncode(json))),
);
Uint8List zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.add(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test(
    'editing a grouped period after a round trip keeps distinct session identities',
    () async {
      final f = PluralPortMapper.clone(fixture());
      (f['members'] as List).add(<String, dynamic>{
        'id': 'm2',
        'name': 'Second',
      });
      ((f['front_periods'] as List).single['assignments'] as List).add(
        <String, dynamic>{
          'member_id': 'm2',
          'front_role': 'cofront',
          'confidence': 0.4,
        },
      );
      final db = makeDb();
      addTearDown(db.close);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      );
      await service.importPlan(plan(f));
      final first = PluralPortExporter(
        (await makeExport(db).buildExport()).toJson(),
        'local',
      ).build(await PluralPortPreservation(db).documents());
      await service.importPlan(plan(first.envelope));
      final sessions = await db.select(db.frontingSessions).get();
      expect(sessions, hasLength(2));
      await (db.update(db.frontingSessions)
            ..where((t) => t.id.equals(sessions.last.id)))
          .write(const FrontingSessionsCompanion(notes: drift.Value('Edited')));
      final second = PluralPortExporter(
        (await makeExport(db).buildExport()).toJson(),
        'local',
      ).build(await PluralPortPreservation(db).documents());
      final next = plan(second.envelope);
      expect(
        PluralPortMapper.rows(
          next.native,
          'frontSessions',
        ).map((r) => r['id']).toSet(),
        hasLength(2),
      );
      await service.importPlan(next);
      expect(await db.select(db.frontingSessions).get(), hasLength(2));
    },
  );

  test(
    'reimporting a Prism export keeps record IDs and opaque data stable',
    () async {
      final db = makeDb();
      addTearDown(db.close);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      );
      await service.importPlan(plan(fixture()));
      for (var i = 0; i < 3; i++) {
        final bundle = PluralPortExporter(
          (await makeExport(db).buildExport()).toJson(),
          'local',
        ).build(await PluralPortPreservation(db).documents());
        final decoded = PluralPortBundle.decode(bundle.encode());
        final next = PluralPortMapper.plan(decoded);
        await service.importPlan(next);
        expect(
          await db.membersDao.getAllMembersIncludingDeleted(),
          hasLength(1),
        );
        expect(PluralPortMapper.rows(bundle.envelope, 'members'), hasLength(1));
        expect((bundle.envelope['extensions'] as Map)['foreign'], {
          'future': 42,
        });
        expect((bundle.envelope['polls'] as Map)['definitions'], hasLength(1));
      }
    },
  );
  test(
    'system profile edits retain source privacy and extension metadata',
    () async {
      final db = makeDb();
      addTearDown(db.close);
      final f = PluralPortMapper.clone(fixture());
      (f['systems'] as List).first['privacy'] = {
        'visibility': 'public',
        'custom': true,
      };
      final p = plan(f);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      );
      await service.importPlan(p, importSystemProfile: true);
      final systemId =
          PluralPortMapper.rows(
                p.archive['envelope'] as Json,
                'systems',
              ).single['id']
              as String;
      await db
          .update(db.systemSettingsTable)
          .write(
            const SystemSettingsTableCompanion(
              systemName: drift.Value('Renamed'),
            ),
          );
      final bundle = PluralPortExporter(
        (await makeExport(db).buildExport()).toJson(),
        systemId,
      ).build(await PluralPortPreservation(db).documents());
      final system = PluralPortMapper.rows(bundle.envelope, 'systems').single;
      expect(system['name'], 'Renamed');
      expect(system['privacy'], {'visibility': 'public', 'custom': true});
    },
  );
  test('foreign bundle files and legacy Sheaf asset paths remain usable', () {
    final f = fixture()
      ..['assets'] = [
        {
          'id': 'asset',
          'kind': 'image',
          'extensions': {
            'sheaf': {'bundle_path': 'media/photo.png'},
          },
        },
      ];
    final input = PluralPortBundle.decode(
      zip({
        'openplural.json': utf8.encode(jsonEncode(f)),
        'media/photo.png': [1, 2, 3],
        'foreign/config.bin': [4, 5, 6],
      }),
    );
    final p = PluralPortMapper.plan(input);
    final bundle = PluralPortExporter(p.native, 'local').build([p.archive]);
    final decoded = PluralPortBundle.decode(bundle.encode());
    expect(decoded.files['foreign/config.bin'], [4, 5, 6]);
    expect(
      decoded.assetBytes(
        PluralPortMapper.rows(decoded.envelope, 'assets').single,
      ),
      [1, 2, 3],
    );
    expect(decoded.files['media/photo.png'], [1, 2, 3]);
  });
  test(
    'choice fields, groups, chat and boards import and export together',
    () async {
      final f = fixture()
        ..['groups'] = [
          {'id': 'g', 'name': 'Group', 'system_id': 's'},
        ]
        ..['group_memberships'] = [
          {'id': 'gm', 'group_id': 'g', 'member_id': 'm'},
        ]
        ..['custom_fields'] = [
          {
            'id': 'cf',
            'name': 'Choice',
            'field_type': 'multiselect',
            'options': ['A', 'B'],
          },
        ]
        ..['custom_field_values'] = [
          {
            'id': 'cv',
            'field_id': 'cf',
            'subject_type': 'member',
            'subject_id': 'm',
            'value': ['A', 'B'],
          },
        ]
        ..['chat'] = {
          'conversations': [
            {
              'id': 'c',
              'kind': 'internal_chat',
              'title': 'Chat',
              'participant_member_ids': ['m'],
            },
          ],
          'messages': [
            {
              'id': 'msg',
              'conversation_id': 'c',
              'author_member_id': 'm',
              'body': 'Hello',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
        }
        ..['boards'] = {
          'posts': [
            {
              'id': 'b',
              'body': 'Board',
              'title': 'Title',
              'target_member_id': 'm',
              'author_member_id': 'm',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ],
        };
      final db = makeDb();
      addTearDown(db.close);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      );
      await service.importPlan(plan(f));
      final native = (await makeExport(db).buildExport()).toJson();
      for (final path in [
        'memberGroups',
        'memberGroupEntries',
        'customFields',
        'customFieldValues',
        'conversations',
        'messages',
        'memberBoardPosts',
      ]) {
        expect(PluralPortMapper.rows(native, path), hasLength(1), reason: path);
      }
      final bundle = PluralPortExporter(
        native,
        'local',
      ).build(await PluralPortPreservation(db).documents());
      expect(() => plan(bundle.envelope), returnsNormally);
      expect(
        (bundle.envelope['capabilities'] as Map)['modules'],
        containsAll(['groups', 'custom_fields', 'chat', 'boards']),
      );
      expect(
        (bundle.envelope['capabilities'] as Map)['modules'],
        isNot(contains('group_memberships')),
      );
      final fresh = PluralPortExporter(native, 'local').build([]);
      final next = plan(fresh.envelope);
      expect(
        PluralPortMapper.rows(next.native, 'customFieldValues'),
        hasLength(1),
      );
    },
  );

  test(
    'both version keys and JSON root names; conflicting declarations fail',
    () {
      for (final key in ['pluralport_version', 'openplural_version']) {
        for (final root in PluralPortBundle.roots) {
          final json = fixture()
            ..remove('openplural_version')
            ..[key] = '0.1';
          expect(
            PluralPortBundle.decode(
              zip({root: utf8.encode(jsonEncode(json))}),
            ).envelope[key],
            '0.1',
          );
        }
      }
      expect(
        () => plan(fixture()..['pluralport_version'] = '0.2'),
        throwsFormatException,
      );
      expect(
        () => plan(fixture()..['openplural_version'] = '0.2'),
        throwsFormatException,
      );
      expect(
        () => PluralPortBundle.decode(
          zip({
            'pluralport.json': utf8.encode(jsonEncode(fixture())),
            'openplural.json': utf8.encode(
              jsonEncode(fixture()..['producer'] = {'app': 'different'}),
            ),
          }),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'unsafe paths, missing references and bad hashes fail before import',
    () {
      for (final path in ['../asset', '/asset', 'a\\b', 'a/./b', 'C:/a']) {
        expect(
          () => PluralPortBundle.decode(
            zip({
              'pluralport.json': utf8.encode(jsonEncode(fixture())),
              path: [1],
            }),
          ),
          throwsFormatException,
        );
      }
      expect(() => plan(fixture()..['members'] = []), throwsFormatException);
      final bundle = PluralPortBundle(
        fixture(),
        files: {
          'assets/a': Uint8List.fromList([1]),
        },
      );
      expect(
        () =>
            bundle.assetBytes({'bundle_path': 'assets/a', 'sha256': 'invalid'}),
        throwsFormatException,
      );
    },
  );
  test(
    'duplicate entries, symbolic links and inflated size lies are rejected',
    () {
      Uint8List rewrite(
        Uint8List source,
        void Function(ByteData, int, int) edit,
      ) {
        final bytes = Uint8List.fromList(source);
        final view = ByteData.sublistView(bytes);
        for (var i = 0; i < bytes.length - 4; i++) {
          final signature = view.getUint32(i, Endian.little);
          if (signature == 0x02014b50 || signature == 0x04034b50) {
            edit(view, i, signature);
          }
        }
        return bytes;
      }

      final json = utf8.encode(jsonEncode(fixture()));
      final symlink = rewrite(
        zip({
          'pluralport.json': json,
          'asset': [1],
        }),
        (v, i, s) {
          if (s == 0x02014b50) v.setUint32(i + 38, 0xa1ff << 16, Endian.little);
        },
      );
      expect(() => PluralPortBundle.decode(symlink), throwsFormatException);
      final bomb = rewrite(
        zip({'pluralport.json': json, 'asset': List.filled(100000, 65)}),
        (v, i, s) {
          final offset = s == 0x02014b50 ? 24 : 22;
          if (v.getUint32(i + offset, Endian.little) == 100000) {
            v.setUint32(i + offset, 1, Endian.little);
          }
        },
      );
      expect(() => PluralPortBundle.decode(bomb), throwsFormatException);
      final overBudget = rewrite(
        zip({
          'pluralport.json': json,
          'opaque.bin': [1],
        }),
        (v, i, signature) {
          final offset = signature == 0x02014b50 ? 24 : 22;
          if (v.getUint32(i + offset, Endian.little) == 1) {
            v.setUint32(
              i + offset,
              PluralPortBundle.maxAsset + 1,
              Endian.little,
            );
          }
        },
      );
      expect(() => PluralPortBundle.decode(overBudget), throwsFormatException);

      final duplicate = zip({
        'pluralport.json': json,
        'assetA': [1],
        'assetB': [2],
      });
      for (var i = 0; i < duplicate.length - 6; i++) {
        if (String.fromCharCodes(duplicate.sublist(i, i + 6)) == 'assetB') {
          duplicate[i + 5] = 65;
        }
      }
      expect(() => PluralPortBundle.decode(duplicate), throwsFormatException);
    },
  );
  test('canonical export names and legacy asset fallback', () {
    final b = PluralPortBundle(
      fixture(),
      files: {
        'assets/a': Uint8List.fromList([1, 2]),
      },
    );
    expect(
      b.assetBytes({
        'extensions': {
          'sheaf': {'bundle_path': 'assets/a'},
        },
      }),
      [1, 2],
    );
    final bytes = b.encode();
    final decoded = ZipDecoder().decodeBytes(bytes);
    expect(decoded.find('pluralport.json'), isNotNull);
    expect(decoded.find('openplural.json'), isNull);
    expect(
      PluralPortBundle.decode(bytes).envelope['pluralport_version'],
      '0.1',
    );
  });
  test(
    'native import, edits, deletion, repeat import and retained extensions',
    () async {
      final db = makeDb();
      addTearDown(db.close);
      final exporter = makeExport(db), importer = makeImport(db);
      final service = PluralPortService(
        db: db,
        exporter: exporter,
        importer: importer,
      );
      final p = plan(fixture());
      await service.importPlan(p);
      final again = await service.importPlan(p);
      expect(again.membersCreated, 0);
      final member = await db.membersDao.getAllMembersIncludingDeleted();
      expect(member.where((m) => !m.isDeleted).length, 1);
      final row = member.first;
      await (db.update(db.members)..where((t) => t.id.equals(row.id))).write(
        const MembersCompanion(
          name: drift.Value('Renamed'),
          bio: drift.Value(null),
        ),
      );
      await service.importPlan(
        p,
      ); // A repeat import must not reset the edit baseline.
      final native = (await exporter.buildExport()).toJson();
      final retained = await PluralPortPreservation(db).documents();
      final output = PluralPortExporter(native, 'local-system').build(retained);
      final mapped = PluralPortMapper.rows(output.envelope, 'members').single;
      expect(mapped['name'], 'Renamed');
      expect(mapped['description'], isNull);
      expect(
        (mapped['extensions'] as Map)['foreign'],
        (fixture()['members'] as List).first['extensions']['foreign'],
      );
      expect(output.envelope['polls'], fixture()['polls']);
      expect((output.envelope['extensions'] as Map)['foreign'], {'future': 42});
      await (db.update(db.members)..where((t) => t.id.equals(row.id))).write(
        const MembersCompanion(isDeleted: drift.Value(true)),
      );
      final after = PluralPortExporter(
        (await exporter.buildExport()).toJson(),
        'local-system',
      ).build(retained);
      expect(PluralPortMapper.rows(after.envelope, 'members'), isEmpty);
      expect(() => plan(after.envelope), returnsNormally);
    },
  );
  test(
    'unrelated edits preserve birthday privacy and front assignment semantics',
    () async {
      final db = makeDb();
      addTearDown(db.close);
      final f = PluralPortMapper.clone(fixture());
      (f['members'] as List).first['birthday'] = {
        'value': '2000-01-02',
        'precision': 'day',
        'year_visible': false,
      };
      final p = plan(f);
      final service = PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      );
      await service.importPlan(p);
      final member =
          (await db.membersDao.getAllMembersIncludingDeleted()).single;
      await (db.update(db.members)..where((t) => t.id.equals(member.id))).write(
        const MembersCompanion(emoji: drift.Value('🌟')),
      );
      final session = (await db.select(db.frontingSessions).get()).single;
      await (db.update(
        db.frontingSessions,
      )..where((t) => t.id.equals(session.id))).write(
        const FrontingSessionsCompanion(notes: drift.Value('New note')),
      );
      final result = PluralPortExporter(
        (await makeExport(db).buildExport()).toJson(),
        'local',
      ).build(await PluralPortPreservation(db).documents());
      expect(
        (PluralPortMapper.rows(result.envelope, 'members').single['birthday']
            as Map)['year_visible'],
        false,
      );
      final assignment =
          (PluralPortMapper.rows(
                        result.envelope,
                        'front_periods',
                      ).single['assignments']
                      as List)
                  .single
              as Map;
      expect(assignment['front_role'], 'primary');
      expect(assignment['confidence'], 0.72);
      expect(assignment['note'], 'New note');
    },
  );
  test(
    'unsupported child records remain archived and cycles fail validation',
    () async {
      final f = fixture()
        ..['custom_fields'] = [
          {
            'id': 'field',
            'system_id': 's',
            'name': 'Future',
            'field_type': 'future',
          },
        ]
        ..['custom_field_values'] = [
          {
            'id': 'value',
            'field_id': 'field',
            'subject_type': 'member',
            'subject_id': 'm',
            'value': 'opaque',
          },
        ];
      final p = plan(f);
      expect(p.native['customFields'], isEmpty);
      expect(p.native['customFieldValues'], isEmpty);
      final db = makeDb();
      addTearDown(db.close);
      await PluralPortService(
        db: db,
        exporter: makeExport(db),
        importer: makeImport(db),
      ).importPlan(p);
      final result = PluralPortExporter(
        (await makeExport(db).buildExport()).toJson(),
        'local',
      ).build(await PluralPortPreservation(db).documents());
      expect(
        PluralPortMapper.rows(
          result.envelope,
          'custom_field_values',
        ).single['value'],
        'opaque',
      );
      final cycle = fixture()
        ..['groups'] = [
          {
            'id': 'g',
            'system_id': 's',
            'name': 'Cycle',
            'parent_group_id': 'g',
          },
        ];
      expect(() => plan(cycle), throwsFormatException);
    },
  );
  test(
    'preservation survives native backup and rejects partial synced documents',
    () async {
      final db = makeDb(), restored = makeDb();
      addTearDown(db.close);
      addTearDown(restored.close);
      await PluralPortPreservation(
        db,
      ).retain({'kind': 'test', 'payload': 'x' * 100000});
      final backup = await makeExport(db).buildExport();
      await makeImport(restored).importData(jsonEncode(backup.toJson()));
      expect(
        await PluralPortPreservation(restored).documents(),
        await PluralPortPreservation(db).documents(),
      );
      await (restored.delete(
        restored.pluralPortUnsupported,
      )..where((t) => t.chunkIndex.equals(0))).go();
      await expectLater(
        PluralPortPreservation(restored).documents(),
        throwsFormatException,
      );
    },
  );
}
