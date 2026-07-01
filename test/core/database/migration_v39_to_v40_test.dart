import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a current-schema DB, then forces the pre-v40 covering shape of
/// `idx_members_pluralkit_id` and stamps user_version=39 so reopening runs the
/// v39 -> v40 migration. Optionally seeds a soft-deleted member holding a short
/// id (the recycled-short-id tombstone case).
Future<File> _seedV39Db(
  String name, {
  bool seedDeletedShortIdHolder = false,
}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  if (seedDeletedShortIdHolder) {
    await seeded.into(seeded.members).insert(
          MembersCompanion.insert(
            id: 'deleted-holder',
            name: 'Old Holder',
            emoji: const drift.Value('🔴'),
            createdAt: DateTime(2026, 1, 1),
            pluralkitUuid: const drift.Value('uuid-old'),
            pluralkitId: const drift.Value('abcde'),
            isDeleted: const drift.Value(true),
          ),
        );
  }
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // Restore the pre-v40 shape: covering (no is_deleted filter).
    rawDb.execute('DROP INDEX IF EXISTS idx_members_pluralkit_id');
    rawDb.execute(
      'CREATE UNIQUE INDEX idx_members_pluralkit_id '
      'ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
    );
    // A real v39 DB predates the F4 create-push lease column, which v40 adds.
    rawDb.execute('ALTER TABLE members DROP COLUMN create_push_started_at');
    rawDb.execute('PRAGMA user_version = 39');
  } finally {
    rawDb.close();
  }
  return dbFile;
}

Future<String?> _indexSql(AppDatabase db, String name) async {
  final row = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE name = ?",
        variables: [drift.Variable<String>(name)],
      )
      .getSingleOrNull();
  return row?.read<String?>('sql');
}

void main() {
  group('schema v39 -> v40: pluralkit_id index narrows to active-only', () {
    test('rebuilds idx_members_pluralkit_id with an is_deleted = 0 filter',
        () async {
      final dbFile = await _seedV39Db('prism_migration_v39_to_v40_shape_');

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version =
          await upgraded.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );

      final memberShortIdSql =
          await _indexSql(upgraded, 'idx_members_pluralkit_id');
      expect(memberShortIdSql, isNotNull);
      expect(memberShortIdSql, contains('is_deleted = 0'));

      // v40 also adds the F4 create-push lease column.
      final memberCols = await upgraded
          .customSelect("SELECT name FROM pragma_table_info('members')")
          .get();
      expect(
        memberCols.map((r) => r.read<String>('name')),
        contains('create_push_started_at'),
      );

      // The uuid index is intentionally left covering tombstones.
      final memberUuidSql =
          await _indexSql(upgraded, 'idx_members_pluralkit_uuid');
      expect(memberUuidSql, isNotNull);
      expect(memberUuidSql, isNot(contains('is_deleted')));
    });

    test(
        'a soft-deleted tombstone\'s recycled short id no longer blocks a live '
        'member that now owns it', () async {
      final dbFile = await _seedV39Db(
        'prism_migration_v39_to_v40_recycle_',
        seedDeletedShortIdHolder: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      // A DIFFERENT live member takes the recycled short id — under the old
      // covering index this insert threw SQLITE_CONSTRAINT_UNIQUE.
      await upgraded.into(upgraded.members).insert(
            MembersCompanion.insert(
              id: 'live-holder',
              name: 'New Holder',
              emoji: const drift.Value('🟢'),
              createdAt: DateTime(2026, 2, 1),
              pluralkitUuid: const drift.Value('uuid-new'),
              pluralkitId: const drift.Value('abcde'),
            ),
          );

      final deleted = await (upgraded.select(upgraded.members)
            ..where((m) => m.id.equals('deleted-holder')))
          .getSingle();
      expect(deleted.isDeleted, isTrue);
      expect(deleted.pluralkitUuid, 'uuid-old',
          reason: 'the tombstone keeps its real uuid (uuid index untouched)');

      final live = await (upgraded.select(upgraded.members)
            ..where((m) => m.id.equals('live-holder')))
          .getSingle();
      expect(live.pluralkitId, 'abcde');
      expect(live.isDeleted, isFalse);
    });

    test('two ACTIVE members still cannot share a short id', () async {
      final dbFile = await _seedV39Db('prism_migration_v39_to_v40_active_dup_');

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      await upgraded.into(upgraded.members).insert(
            MembersCompanion.insert(
              id: 'active-1',
              name: 'A',
              createdAt: DateTime(2026, 2, 1),
              pluralkitId: const drift.Value('zzzzz'),
            ),
          );

      await expectLater(
        upgraded.into(upgraded.members).insert(
              MembersCompanion.insert(
                id: 'active-2',
                name: 'B',
                createdAt: DateTime(2026, 2, 1),
                pluralkitId: const drift.Value('zzzzz'),
              ),
            ),
        throwsA(
          isA<Object>()
              .having((e) => e.toString(), 'message', contains('UNIQUE')),
        ),
      );
    });
  });
}
