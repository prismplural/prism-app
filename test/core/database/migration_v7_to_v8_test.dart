import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Pins the v7 → v8 migration: three additive `system_settings` columns for
/// the Phase 1B fronting preferences (docs/plans/fronting-preferences-1B.md).
///
/// Mirrors the pattern in `migration_v7_test.dart`: open the DB once at
/// the current schema, then downgrade the file to v7 by stripping the v8
/// columns + bumping `user_version` back to 7. Re-opening triggers Drift's
/// onUpgrade through the v7→v8 block.
Future<void> _seedV7Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('PRAGMA user_version = 7;');
    rawDb.execute('ALTER TABLE fronting_sessions DROP COLUMN pk_import_source');
    rawDb.execute(
      'ALTER TABLE fronting_sessions DROP COLUMN pk_file_switch_id',
    );
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_source');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_layout');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_image_data');
    rawDb.execute('ALTER TABLE members DROP COLUMN pk_banner_image_data');
    rawDb.execute('ALTER TABLE members DROP COLUMN pk_banner_cached_url');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN fronting_list_view_mode',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN add_front_default_behavior',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN quick_front_default_behavior',
    );
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v8 migration (fronting preferences 1B)', () {
    test(
      'fresh v8 schema has the three preference columns with default values',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final cols = await db
            .customSelect('PRAGMA table_info(system_settings)')
            .get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        expect(colNames, contains('fronting_list_view_mode'));
        expect(colNames, contains('add_front_default_behavior'));
        expect(colNames, contains('quick_front_default_behavior'));

        // Defaults: combinedPeriods (0), additive (0), additive (0).
        final settings = await db.systemSettingsDao.getSettings();
        expect(
          settings.frontingListViewMode,
          0,
          reason: 'fresh install must default to combinedPeriods (0)',
        );
        expect(
          settings.addFrontDefaultBehavior,
          0,
          reason: 'fresh install must default to additive (0)',
        );
        expect(
          settings.quickFrontDefaultBehavior,
          0,
          reason: 'fresh install must default to additive (0)',
        );
      },
    );

    test(
      'v7 → v8 upgrade adds the three columns without dropping existing data',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v7_to_v8_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v7_to_v8.db');
        await _seedV7Db(dbFile);

        // Sanity: write a row at v7 so we can prove no data loss across the
        // upgrade. Columns we touch here must exist at v7.
        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          rawDb.execute(
            'INSERT OR REPLACE INTO system_settings '
            '(id, system_name, accent_color_hex, '
            ' pending_fronting_migration_mode, '
            ' pending_fronting_migration_cleanup_substate) '
            'VALUES '
            "('singleton', 'TestSystem', '#112233', 'complete', '')",
          );
        } finally {
          rawDb.close();
        }

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        // The three new columns must now exist.
        final cols = await upgraded
            .customSelect('PRAGMA table_info(system_settings)')
            .get();
        final colNames = cols.map((r) => r.read<String>('name')).toSet();
        expect(colNames, contains('fronting_list_view_mode'));
        expect(colNames, contains('add_front_default_behavior'));
        expect(colNames, contains('quick_front_default_behavior'));

        // Existing data must survive the upgrade.
        final settings = await upgraded.systemSettingsDao.getSettings();
        expect(settings.systemName, 'TestSystem');
        expect(settings.accentColorHex, '#112233');

        // Defaults must apply to the existing row's brand-new columns.
        expect(
          settings.frontingListViewMode,
          0,
          reason: 'existing row must default to combinedPeriods (0)',
        );
        expect(
          settings.addFrontDefaultBehavior,
          0,
          reason: 'existing row must default to additive (0)',
        );
        expect(
          settings.quickFrontDefaultBehavior,
          0,
          reason: 'existing row must default to additive (0)',
        );

        // Confirm the schema version bumped through all current migrations.
        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.first.read<int>('user_version'), 10);
      },
    );
  });
}
