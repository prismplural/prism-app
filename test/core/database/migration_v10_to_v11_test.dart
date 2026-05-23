import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV10Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded
      .into(seeded.members)
      .insert(
        MembersCompanion.insert(
          id: 'member-visible-default',
          name: 'Visible Member',
          createdAt: DateTime.utc(2026, 4, 30, 12),
        ),
      );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // v18 (members tab preferences) — drop columns added by v17→v18.
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_show_pronouns',
    );

    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_show_front_buttons',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_front_button_behavior',
    );

    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_list_view_mode',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_grouped_default_state',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN members_folder_member_visibility',
    );

    // v17 (fronting auto-promotion) — drop column added by v16→v17.
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN auto_promote_long_fronting_sessions',
    );

    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_visible');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_font');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_bold');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_italic');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_color_mode');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_color_hex');
    rawDb.execute('ALTER TABLE members DROP COLUMN pluralkit_display_name');
    // v15 (Member Boards) — drop columns added by v14→v15 to simulate older state.
    rawDb.execute('ALTER TABLE members DROP COLUMN board_last_read_at');
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN boards_enabled');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN sp_boards_backfilled_at',
    );
    rawDb.execute('DROP TABLE IF EXISTS member_board_posts');

    // Flattened v18→v19: drop pending_pk_op so onUpgrade can re-add it.

    rawDb.execute('ALTER TABLE member_group_entries DROP COLUMN pending_pk_op');

    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN bio_markdown_enabled',
    );
    // Drop columns added by v21-v25 so their migrations can re-add them when
    // stepping forward through v10 -> current.
    rawDb.execute('ALTER TABLE member_groups DROP COLUMN sort_state');
    rawDb.execute(
      'ALTER TABLE plural_kit_sync_state DROP COLUMN direction_confirmed',
    );
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN palette_source');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN palette_seed_color_hex',
    );
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN palette_mood');
    rawDb.execute('ALTER TABLE system_settings DROP COLUMN palette_contrast');
    rawDb.execute('ALTER TABLE conversations DROP COLUMN includes_all_members');
    rawDb.execute('PRAGMA user_version = 10;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v11 migration (member profile header visibility)', () {
    test('fresh schema has profile_header_visible column', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final columns = await db.customSelect('PRAGMA table_info(members)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('profile_header_visible'));
    });

    test('v10 -> v11 adds visible column defaulting to true', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v10_to_v11_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v10_to_v11.db');
      await _seedV10Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final member = await (upgraded.select(
        upgraded.members,
      )..where((m) => m.id.equals('member-visible-default'))).getSingle();
      expect(member.profileHeaderVisible, isTrue);

      final version = await upgraded.customSelect('PRAGMA user_version').get();
      expect(version.first.read<int>('user_version'), 27);
    });
  });
}
