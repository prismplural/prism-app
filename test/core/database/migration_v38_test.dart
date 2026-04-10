import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  group('migration v37 → v38 (gif_search_enabled)', () {
    test('fresh database has gif_search_enabled column defaulting to true',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db.customSelect(
        'SELECT gif_search_enabled FROM system_settings',
      ).get();

      // Fresh database has no rows in system_settings — verify column exists
      // by checking the query doesn't throw. If there were a default row we'd
      // also verify the value.
      expect(rows, isEmpty);

      // Verify column type info through table_info pragma.
      final colInfo = await db.customSelect(
        "SELECT name, dflt_value FROM pragma_table_info('system_settings') "
        "WHERE name = 'gif_search_enabled'",
      ).get();

      expect(colInfo, hasLength(1));
      expect(colInfo.first.read<String>('name'), 'gif_search_enabled');
      // Default is 1 (true in SQLite).
      expect(colInfo.first.read<String>('dflt_value'), '1');
    });

    test('upgrade from v37 adds gif_search_enabled column', () async {
      final tempDir = Directory.systemTemp.createTempSync('prism_migration_v38_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/upgrade.db');

      // Create a raw database at schema version 37 with a minimal
      // system_settings table that lacks the gif_search_enabled column.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 37;');
        // Minimal system_settings table matching v37 schema (no gif_search_enabled).
        rawDb.execute('''
          CREATE TABLE system_settings (
            id TEXT NOT NULL PRIMARY KEY DEFAULT 'singleton',
            system_name TEXT,
            show_quick_front INTEGER NOT NULL DEFAULT 1,
            accent_color_hex TEXT NOT NULL DEFAULT '#AF8EE9',
            per_member_accent_colors INTEGER NOT NULL DEFAULT 0,
            terminology INTEGER NOT NULL DEFAULT 0,
            custom_terminology TEXT,
            custom_plural_terminology TEXT,
            sharing_id TEXT,
            fronting_reminders_enabled INTEGER NOT NULL DEFAULT 0,
            fronting_reminder_interval_minutes INTEGER NOT NULL DEFAULT 60,
            theme_mode INTEGER NOT NULL DEFAULT 0,
            theme_brightness INTEGER NOT NULL DEFAULT 0,
            theme_style INTEGER NOT NULL DEFAULT 0,
            chat_enabled INTEGER NOT NULL DEFAULT 1,
            polls_enabled INTEGER NOT NULL DEFAULT 1,
            habits_enabled INTEGER NOT NULL DEFAULT 1,
            sleep_tracking_enabled INTEGER NOT NULL DEFAULT 1,
            quick_switch_threshold_seconds INTEGER NOT NULL DEFAULT 30,
            identity_generation INTEGER NOT NULL DEFAULT 0,
            chat_logs_front INTEGER NOT NULL DEFAULT 0,
            has_completed_onboarding INTEGER NOT NULL DEFAULT 0,
            sync_theme_enabled INTEGER NOT NULL DEFAULT 0,
            timing_mode INTEGER NOT NULL DEFAULT 0,
            habits_badge_enabled INTEGER NOT NULL DEFAULT 1,
            notes_enabled INTEGER NOT NULL DEFAULT 1,
            system_description TEXT,
            system_avatar_data BLOB,
            reminders_enabled INTEGER NOT NULL DEFAULT 1,
            font_scale REAL NOT NULL DEFAULT 1.0,
            font_family INTEGER NOT NULL DEFAULT 0,
            pin_lock_enabled INTEGER NOT NULL DEFAULT 0,
            biometric_lock_enabled INTEGER NOT NULL DEFAULT 0,
            auto_lock_delay_seconds INTEGER NOT NULL DEFAULT 0,
            display_font_in_app_bar INTEGER NOT NULL DEFAULT 1,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            previous_accent_color_hex TEXT NOT NULL DEFAULT '',
            nav_bar_items TEXT NOT NULL DEFAULT '',
            nav_bar_overflow_items TEXT NOT NULL DEFAULT '',
            sync_navigation_enabled INTEGER NOT NULL DEFAULT 1,
            chat_badge_preferences TEXT NOT NULL DEFAULT '{}'
          )
        ''');
      } finally {
        rawDb.close();
      }

      // Open through Drift — this triggers the v37→v38 migration.
      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Verify the column now exists by querying pragma.
      final colInfo = await db.customSelect(
        "SELECT name, dflt_value FROM pragma_table_info('system_settings') "
        "WHERE name = 'gif_search_enabled'",
      ).get();

      expect(colInfo, hasLength(1));
      expect(colInfo.first.read<String>('dflt_value'), '1');
    });
  });
}
