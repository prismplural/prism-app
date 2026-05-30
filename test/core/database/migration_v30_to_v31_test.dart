import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<File> _seedV30Db(String name) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  // Build the current schema, then close so we can reshape `members.age` back
  // into a true INTEGER column via raw SQL. The current schema declares `age`
  // as TEXT, so seeding through it would NOT exercise the v31 INTEGER → TEXT
  // transform — we must recreate the column with integer affinity first.
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // Replace the TEXT `age` column with a real INTEGER one (v30 shape).
    rawDb.execute('ALTER TABLE members DROP COLUMN age');
    rawDb.execute('ALTER TABLE members ADD COLUMN age INTEGER');

    // Confirm the column really is INTEGER before seeding, so a future schema
    // change can't silently turn this into a no-op assertion again.
    final preCols = rawDb.select('PRAGMA table_info(members)');
    final ageType = preCols.firstWhere((r) => r['name'] == 'age')['type'];
    if ((ageType as String).toUpperCase() != 'INTEGER') {
      throw StateError('Seed setup failed: age column is $ageType, not INTEGER');
    }

    // Member with an integer age.
    rawDb.execute(
      'INSERT INTO members '
      '(id, name, emoji, age, is_active, created_at, display_order, '
      ' is_admin, custom_color_enabled, pluralkit_sync_ignored, '
      ' is_always_fronting, markdown_enabled, is_deleted) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      ['member-age27', 'AgeTest', '❔', 27, 1, 1748390400, 0, 0, 0, 0, 0, 1, 0],
    );
    // Member with NULL age.
    rawDb.execute(
      'INSERT INTO members '
      '(id, name, emoji, age, is_active, created_at, display_order, '
      ' is_admin, custom_color_enabled, pluralkit_sync_ignored, '
      ' is_always_fronting, markdown_enabled, is_deleted) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      ['member-null-age', 'NullAge', '❔', null, 1, 1748390400, 0, 0, 0, 0, 0, 1, 0],
    );

    // Downgrade the stored schema version to 30 so reopening runs v30 → v31.
    rawDb.execute('PRAGMA user_version = 30');
  } finally {
    rawDb.close();
  }

  return dbFile;
}

void main() {
  group('schema v30 → v31: age column INT → TEXT', () {
    test('migrates integer age to string and preserves NULL age', () async {
      final dbFile = await _seedV30Db('prism_migration_v30_to_v31_');

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      // Verify schema version bumped.
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 31);

      // Verify the column type is now TEXT.
      final cols = await upgraded
          .customSelect('PRAGMA table_info(members)')
          .get();
      final ageCol = cols.firstWhere(
        (row) => row.read<String>('name') == 'age',
      );
      // SQLite column type after TableMigration CAST is TEXT.
      expect(ageCol.read<String>('type').toUpperCase(), contains('TEXT'));

      // Verify integer age was converted to its string form.
      final ageRow = await upgraded.membersDao.getMemberById('member-age27');
      expect(ageRow, isNotNull);
      expect(ageRow!.age, '27');

      // Verify NULL age stays NULL.
      final nullAgeRow =
          await upgraded.membersDao.getMemberById('member-null-age');
      expect(nullAgeRow, isNotNull);
      expect(nullAgeRow!.age, isNull);
    });
  });
}
