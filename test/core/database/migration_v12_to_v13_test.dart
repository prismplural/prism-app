import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV12Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('DROP INDEX IF EXISTS idx_comments_target_time');
    // v15 (Member Boards) — drop columns added by v14→v15 to simulate older state.
    rawDb.execute('ALTER TABLE members DROP COLUMN board_last_read_at');
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN boards_enabled',
    );
    rawDb.execute(
      'ALTER TABLE system_settings DROP COLUMN sp_boards_backfilled_at',
    );
    rawDb.execute('DROP TABLE IF EXISTS member_board_posts');
    rawDb.execute('PRAGMA user_version = 12;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v12 -> current comment cleanup', () {
    test('upgrade leaves restored session-attached comment index only', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v12_to_v13_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v12_to_v13.db');
      await _seedV12Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final indexes = await upgraded
          .customSelect("PRAGMA index_list('front_session_comments')")
          .get();
      final names = indexes.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('idx_comments_session'));
      expect(names, isNot(contains('idx_comments_target_time')));

      final cols = await upgraded
          .customSelect("PRAGMA table_info('front_session_comments')")
          .get();
      final colNames = cols.map((row) => row.read<String>('name')).toSet();
      expect(colNames, contains('session_id'));
      expect(colNames, isNot(contains('target_time')));
      expect(colNames, isNot(contains('author_member_id')));

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 16);
    });
  });
}
