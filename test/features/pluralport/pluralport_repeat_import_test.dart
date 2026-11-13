import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_bundle.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_mapper.dart';
import 'package:prism_plurality/features/pluralport/services/pluralport_service.dart';

import 'harness.dart';

// A foreign producer writes microsecond timestamps with a numeric offset. Prism
// storage keeps whole seconds, so every one of these values comes back
// canonicalized; that shape difference is not a local edit.
const _created = '2026-01-02T03:04:05.123456+00:00';
const _updated = '2026-01-02T06:07:08.654321+00:00';
const _ended = '2026-01-02T04:05:06.987654+00:00';

// 1x1 PNG. Prism keeps the bytes an import supplied, whatever their shape.
final _avatar = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Json _document() => {
  'pluralport_version': '0.1',
  'producer': {'app': 'Sheaf', 'app_id': 'sheaf', 'exporter_version': '0.1.0'},
  'systems': [
    {'id': 'system', 'name': 'System'},
  ],
  'members': [
    {
      'id': 'member',
      'system_id': 'system',
      'name': 'Member',
      'description': 'Original bio',
      'created_at': _created,
      'avatar_asset_id': 'avatar',
      'extensions': {
        'sheaf': {'palette': 'amber'},
      },
    },
  ],
  'notes': [
    {
      'id': 'note',
      'system_id': 'system',
      'member_id': 'member',
      'title': 'Entry',
      'body': 'Body',
      'entry_date': '2026-01-02',
      'created_at': _created,
      'updated_at': _updated,
    },
  ],
  'front_periods': [
    {
      'id': 'period',
      'system_id': 'system',
      'started_at': _created,
      'ended_at': _ended,
      'assignments': [
        {
          'member_id': 'member',
          'front_role': 'primary',
          'confidence': 0.72,
          'note': 'Front note',
        },
      ],
    },
  ],
  'custom_fields': [
    {
      'id': 'field',
      'system_id': 'system',
      'name': 'Pronouns',
      'field_type': 'text',
      'created_at': _created,
    },
  ],
  'custom_field_values': [
    {
      'id': 'value',
      'field_id': 'field',
      'subject_type': 'member',
      'subject_id': 'member',
      'value': 'they/them',
    },
  ],
  'boards.posts': [
    {
      'id': 'post',
      'system_id': 'system',
      'target_member_id': 'member',
      'author_member_id': 'member',
      'title': 'Post',
      'body': 'Post body',
      'created_at': _created,
      'written_at': _updated,
    },
  ],
  'assets': [
    {
      'id': 'avatar',
      'kind': 'avatar',
      'mime_type': 'image/png',
      'bundle_path': 'assets/avatar.png',
    },
  ],
  'extensions': {
    'sheaf': {'unknown_module': true},
  },
};

Uint8List _archive() {
  final files = {
    'pluralport.json': utf8.encode(jsonEncode(_document())),
    'assets/avatar.png': _avatar,
  };
  final archive = Archive();
  for (final entry in files.entries) {
    archive.add(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

PluralPortService _service(AppDatabase db, Directory directory) =>
    PluralPortService(
      db: db,
      exporter: makeExport(db),
      importer: makeImport(db, supportDirectory: directory),
      supportDirectory: () async => directory,
    );

/// Every portable record of every native-backed collection, keyed by identity
/// and reduced to one comparable string per row.
Map<String, Map<String, String>> _records(PluralPortBundle bundle) => {
  for (final entry in PluralPortMapper.collections.entries)
    entry.key: {
      for (final row in PluralPortMapper.rows(bundle.envelope, entry.key))
        row['id'] as String: canonicalJson(row),
    },
};

void main() {
  test(
    'repeating the same import keeps the preserved portable source',
    () async {
      final directory = await Directory.systemTemp.createTemp('pluralport-');
      addTearDown(() => directory.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final subject = _service(db, directory);
      final archive = _archive();

      await subject.importPlan(PluralPortService.previewBytes(archive));
      final first = await subject.exportBundle();
      await subject.importPlan(PluralPortService.previewBytes(archive));
      final second = await subject.exportBundle();

      // The second import must not re-project unchanged records through
      // `convert()`; every mapped collection exports exactly as it did before.
      expect(_records(second), _records(first));
      expect(second.files.keys.toSet(), first.files.keys.toSet());
      for (final entry in first.files.entries) {
        expect(second.files[entry.key], entry.value, reason: entry.key);
      }

      final note = PluralPortMapper.rows(second.envelope, 'notes').single;
      expect(note['created_at'], _created);
      expect(note['updated_at'], _updated);
      expect(note['body'], 'Body');
    },
  );

  test(
    'stored timestamps and assets are canonicalized without counting as edits',
    () async {
      final directory = await Directory.systemTemp.createTemp('pluralport-');
      addTearDown(() => directory.delete(recursive: true));
      final db = makeDb();
      addTearDown(db.close);
      final subject = _service(db, directory);
      final archive = _archive();

      await subject.importPlan(PluralPortService.previewBytes(archive));
      await subject.importPlan(PluralPortService.previewBytes(archive));
      final native = (await makeExport(db).buildExport()).toJson();
      // Storage did canonicalize what the source wrote.
      for (final stored in [
        PluralPortMapper.rows(native, 'notes').single['createdAt'] as String,
        PluralPortMapper.rows(native, 'headmates').single['createdAt']
            as String,
      ]) {
        expect(stored, isNot(_created));
        expect(stored, startsWith('2026-01-02T03:04:05'));
      }

      final bundle = await subject.exportBundle();
      final member = PluralPortMapper.rows(bundle.envelope, 'members').single;
      // ...which is why the unchanged record has to keep the source shape rather
      // than being rebuilt from the stored row.
      expect(member['created_at'], _created);
      expect((member['extensions'] as Map)['prism'], isNull);
      // Re-projecting the member would mint a second, hash-named avatar asset.
      final assets = PluralPortMapper.rows(bundle.envelope, 'assets');
      expect(assets, hasLength(1));
      expect(assets.single['bundle_path'], 'assets/avatar.png');
      expect(member['avatar_asset_id'], assets.single['id']);
      expect(bundle.files.keys, ['assets/avatar.png']);
      expect(
        PluralPortMapper.rows(
          bundle.envelope,
          'front_periods',
        ).single['started_at'],
        _created,
      );
    },
  );

  test('a real local edit still invalidates the preserved source', () async {
    final directory = await Directory.systemTemp.createTemp('pluralport-');
    addTearDown(() => directory.delete(recursive: true));
    final db = makeDb();
    addTearDown(db.close);
    final subject = _service(db, directory);
    final archive = _archive();

    await subject.importPlan(PluralPortService.previewBytes(archive));
    await subject.importPlan(PluralPortService.previewBytes(archive));
    final member = (await db.membersDao.getAllMembersIncludingDeleted()).single;
    await (db.update(db.members)..where((t) => t.id.equals(member.id))).write(
      const MembersCompanion(
        name: drift.Value('Renamed'),
        bio: drift.Value('Local bio'),
      ),
    );

    final bundle = await subject.exportBundle();
    final record = PluralPortMapper.rows(bundle.envelope, 'members').single;
    expect(record['name'], 'Renamed');
    expect(record['description'], 'Local bio');
    // Only the edited fields are projected; unrelated metadata, including the
    // source's sub-second timestamp and foreign extensions, stays intact.
    expect(record['created_at'], _created);
    expect((record['extensions'] as Map)['sheaf'], {'palette': 'amber'});
    expect((record['extensions'] as Map)['prism'], isA<Map>());
    expect(
      PluralPortMapper.rows(bundle.envelope, 'notes').single['created_at'],
      _created,
      reason: 'an unedited sibling record keeps the preserved source',
    );
  });

  test('repeated imports stay native-idempotent', () async {
    final directory = await Directory.systemTemp.createTemp('pluralport-');
    addTearDown(() => directory.delete(recursive: true));
    final db = makeDb();
    addTearDown(db.close);
    final subject = _service(db, directory);
    final archive = _archive();

    final created = await subject.importPlan(
      PluralPortService.previewBytes(archive),
    );
    expect(created.membersCreated, 1);
    final before = (await makeExport(db).buildExport()).toJson();
    final repeated = await subject.importPlan(
      PluralPortService.previewBytes(archive),
    );
    expect(repeated.totalRecordsCreated, 0);
    expect(repeated.membersCreated, 0);
    final after = (await makeExport(db).buildExport()).toJson();
    for (final entry in PluralPortMapper.collections.entries) {
      expect(
        PluralPortMapper.rows(after, entry.value),
        PluralPortMapper.rows(before, entry.value),
        reason: entry.key,
      );
    }
  });
}
