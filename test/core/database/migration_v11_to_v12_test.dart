import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV11Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded
      .into(seeded.members)
      .insert(
        MembersCompanion.insert(
          id: 'member-name-style-default',
          name: 'Styled Member',
          createdAt: DateTime.utc(2026, 4, 30, 12),
        ),
      );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_font');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_bold');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_italic');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_color_mode');
    rawDb.execute('ALTER TABLE members DROP COLUMN name_style_color_hex');
    // v15 (Member Boards) — drop columns added by v14→v15 to simulate older state.
    rawDb.execute('ALTER TABLE members DROP COLUMN board_last_read_at');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN boards_enabled',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN sp_boards_backfilled_at',
    );
    rawDb.execute('DROP TABLE IF EXISTS member_board_posts');

    rawDb.execute('PRAGMA user_version = 11;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v12 migration (member name styles)', () {
    test('fresh schema has member name style columns', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final columns = await db.customSelect('PRAGMA table_info(members)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('name_style_font'));
      expect(names, contains('name_style_bold'));
      expect(names, contains('name_style_italic'));
      expect(names, contains('name_style_color_mode'));
      expect(names, contains('name_style_color_hex'));
    });

    test('v11 -> v12 adds name style defaults', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v11_to_v12_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v11_to_v12.db');
      await _seedV11Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final member = await (upgraded.select(
        upgraded.members,
      )..where((m) => m.id.equals('member-name-style-default'))).getSingle();
      expect(member.nameStyleFont, 0);
      expect(member.nameStyleBold, isTrue);
      expect(member.nameStyleItalic, isFalse);
      expect(member.nameStyleColorMode, 0);
      expect(member.nameStyleColorHex, isNull);

      final version = await upgraded.customSelect('PRAGMA user_version').get();
      expect(version.first.read<int>('user_version'), 16);
    });
  });
}
