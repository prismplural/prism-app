import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Migration test for themeCornerStyle — schema v55 → v56.
///
/// Adds `theme_corner_style INTEGER NOT NULL DEFAULT 0` to `system_settings`
/// for the corner style (rounded / angular) UI preference.
void main() {
  group('migration v55 → v56 (themeCornerStyle)', () {
    test('fresh database has theme_corner_style column defaulting to 0',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Force schema creation.
      await db.customSelect('SELECT 1').get();

      final colInfo = await db.customSelect(
        "SELECT name, dflt_value FROM pragma_table_info('system_settings') "
        "WHERE name = 'theme_corner_style'",
      ).get();

      expect(colInfo, hasLength(1));
      expect(colInfo.first.read<String>('name'), 'theme_corner_style');
      expect(colInfo.first.read<String>('dflt_value'), '0');
    });

    test('upgrade from v55 adds column and preserves existing row', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v56_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/upgrade.db');

      // Stub a v55 system_settings table without the new column.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 55;');
        rawDb.execute('''
          CREATE TABLE system_settings (
            id TEXT NOT NULL DEFAULT 'singleton' PRIMARY KEY,
            system_name TEXT,
            show_quick_front INTEGER NOT NULL DEFAULT 1,
            accent_color_hex TEXT NOT NULL DEFAULT '#AF8EE9',
            per_member_accent_colors INTEGER NOT NULL DEFAULT 0,
            terminology INTEGER NOT NULL DEFAULT 0,
            custom_terminology TEXT,
            custom_plural_terminology TEXT,
            locale_override TEXT,
            terminology_use_english INTEGER NOT NULL DEFAULT 0,
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
            gif_search_enabled INTEGER NOT NULL DEFAULT 1,
            voice_notes_enabled INTEGER NOT NULL DEFAULT 1,
            sleep_suggestion_enabled INTEGER NOT NULL DEFAULT 0,
            sleep_suggestion_hour INTEGER NOT NULL DEFAULT 22,
            sleep_suggestion_minute INTEGER NOT NULL DEFAULT 0,
            wake_suggestion_enabled INTEGER NOT NULL DEFAULT 0,
            wake_suggestion_after_hours REAL NOT NULL DEFAULT 8.0,
            quick_switch_threshold_seconds INTEGER NOT NULL DEFAULT 30,
            identity_generation INTEGER NOT NULL DEFAULT 0,
            chat_logs_front INTEGER NOT NULL DEFAULT 0,
            has_completed_onboarding INTEGER NOT NULL DEFAULT 0,
            sync_theme_enabled INTEGER NOT NULL DEFAULT 0,
            timing_mode INTEGER NOT NULL DEFAULT 0,
            habits_badge_enabled INTEGER NOT NULL DEFAULT 1,
            notes_enabled INTEGER NOT NULL DEFAULT 1,
            system_description TEXT,
            system_color TEXT,
            system_tag TEXT,
            system_avatar_data BLOB,
            reminders_enabled INTEGER NOT NULL DEFAULT 1,
            gif_consent_state INTEGER NOT NULL DEFAULT 0,
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
        rawDb.execute(
          'INSERT INTO system_settings (id, system_name, theme_style) '
          "VALUES ('singleton', 'Test System', 1)",
        );
      } finally {
        rawDb.close();
      }

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      await db.customSelect('SELECT 1').get();

      final rows = await db.customSelect(
        'SELECT id, system_name, theme_style, theme_corner_style '
        'FROM system_settings',
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 'singleton');
      expect(rows.single.read<String?>('system_name'), 'Test System');
      // Existing row: theme_style preserved, new column defaults to 0 (rounded).
      expect(rows.single.read<int>('theme_style'), 1);
      expect(rows.single.read<int>('theme_corner_style'), 0);
    });
  });
}
