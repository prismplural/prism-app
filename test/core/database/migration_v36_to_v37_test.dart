import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a database at the current schema, inserts one PK-backed group + entry,
/// then stamps `user_version = 36` (optionally dropping the new column) so
/// reopening runs the v36 → v37 migration chain. Mirrors
/// migration_v31_to_v32_test. The new column is the local-only
/// `member_group_entries.created_at` recency stamp (2026-06 PK audit H6b).
Future<File> _seedV36Db(String name, {required bool dropColumn}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.customStatement(
    'INSERT INTO member_groups (id, name, display_order, group_type, '
    'created_at, is_deleted, sync_suppressed, sort_state) '
    "VALUES ('g1', 'G1', 0, 0, 0, 0, 0, '{\"mode\":0,\"order\":[]}')",
  );
  await seeded.customStatement(
    'INSERT INTO member_group_entries (id, group_id, member_id, is_deleted, '
    "pending_pk_op) VALUES ('e1', 'g1', 'm1', 0, 'none')",
  );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    if (dropColumn) {
      rawDb.execute(
        'ALTER TABLE member_group_entries DROP COLUMN created_at',
      );
    }
    rawDb.execute('PRAGMA user_version = 36');
  } finally {
    rawDb.close();
  }

  return dbFile;
}

void main() {
  group('schema v36 -> v37: member_group_entries.created_at', () {
    test('adds created_at and backfills existing rows to non-null', () async {
      final dbFile = await _seedV36Db(
        'prism_migration_v36_to_v37_add_',
        dropColumn: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version =
          await upgraded.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), greaterThanOrEqualTo(37));

      final cols = await upgraded
          .customSelect('PRAGMA table_info(member_group_entries)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('created_at'));

      // The pre-existing row must be backfilled to a non-null stamp so the
      // grace check has a real value (the migration backfills NULLs to now).
      final row = await upgraded
          .customSelect(
            'SELECT created_at FROM member_group_entries WHERE id = ?',
            variables: [const Variable<String>('e1')],
          )
          .getSingle();
      expect(row.read<int?>('created_at'), isNotNull,
          reason: 'v37 migration must backfill existing rows (H6b)');
    });

    test('idempotent: skips cleanly when the column already exists', () async {
      // dropColumn:false leaves the v37-shaped column in place while the
      // user_version says 36 — exercises the migration's PRAGMA guard.
      final dbFile = await _seedV36Db(
        'prism_migration_v36_to_v37_skip_',
        dropColumn: false,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final cols = await upgraded
          .customSelect('PRAGMA table_info(member_group_entries)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('created_at'));
    });
  });
}
