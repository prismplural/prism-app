import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a v20 database with three rows in plural_kit_sync_state covering
/// the backfill cases specified in the v20 → v21 migration plan:
///   (a) fully set up:    is_connected=1, mapping_acknowledged=1
///   (b) mid-setup:       is_connected=1, mapping_acknowledged=0
///   (c) disconnected:    is_connected=0, mapping_acknowledged=0
Future<void> _seedV20Db(File dbFile) async {
  // Bring the file up to the current schema via Drift.
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  // Drop the new column and reset the version to v20 to simulate a v20 DB.
  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // Remove the column added by v21 so the migration has to add it back.
    rawDb.execute(
      'ALTER TABLE plural_kit_sync_state DROP COLUMN direction_confirmed',
    );

    // Insert three test rows directly.
    rawDb.execute(
      '''
      INSERT INTO plural_kit_sync_state
        (id, is_connected, mapping_acknowledged)
      VALUES
        ('pk_config_a', 1, 1),
        ('pk_config_b', 1, 0),
        ('pk_config_c', 0, 0)
      ''',
    );

    rawDb.execute('PRAGMA user_version = 20;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v20 → v21: direction_confirmed column + backfill', () {
    test(
      'adds direction_confirmed and backfills based on mapping_acknowledged',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v20_to_v21_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v20_to_v21.db');
        await _seedV20Db(dbFile);

        // Open the DB — this triggers the v20 → v21 migration.
        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        // Verify the schema version advanced to 21.
        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 21);

        // Verify the column exists.
        final cols = await upgraded
            .customSelect('PRAGMA table_info(plural_kit_sync_state)')
            .get();
        expect(
          cols.map((row) => row.read<String>('name')).toSet(),
          contains('direction_confirmed'),
        );

        // (a) fully set up: mapping_acknowledged=1 → direction_confirmed=1
        final rowA = await upgraded
            .customSelect(
              'SELECT direction_confirmed FROM plural_kit_sync_state WHERE id = ?',
              variables: [Variable.withString('pk_config_a')],
            )
            .getSingle();
        expect(
          rowA.read<int>('direction_confirmed'),
          1,
          reason: 'fully-set-up row should have direction_confirmed=1',
        );

        // (b) mid-setup: mapping_acknowledged=0 → direction_confirmed=0
        final rowB = await upgraded
            .customSelect(
              'SELECT direction_confirmed FROM plural_kit_sync_state WHERE id = ?',
              variables: [Variable.withString('pk_config_b')],
            )
            .getSingle();
        expect(
          rowB.read<int>('direction_confirmed'),
          0,
          reason: 'mid-setup row should have direction_confirmed=0',
        );

        // (c) disconnected: mapping_acknowledged=0 → direction_confirmed=0
        final rowC = await upgraded
            .customSelect(
              'SELECT direction_confirmed FROM plural_kit_sync_state WHERE id = ?',
              variables: [Variable.withString('pk_config_c')],
            )
            .getSingle();
        expect(
          rowC.read<int>('direction_confirmed'),
          0,
          reason: 'disconnected row should have direction_confirmed=0',
        );
      },
    );

    test('fresh install: direction_confirmed defaults to 0', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.customStatement(
        "INSERT INTO plural_kit_sync_state (id) VALUES ('pk_config')",
      );

      final row = await db
          .customSelect(
            'SELECT direction_confirmed FROM plural_kit_sync_state WHERE id = ?',
            variables: [Variable.withString('pk_config')],
          )
          .getSingle();
      expect(
        row.read<int>('direction_confirmed'),
        0,
        reason: 'fresh-install default must be 0 so the wizard is shown',
      );
    });
  });
}
