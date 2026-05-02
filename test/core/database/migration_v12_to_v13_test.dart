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
    rawDb.execute('PRAGMA user_version = 12;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v13 migration (comment target_time index)', () {
    test('v12 -> v13 adds the target_time range index', () async {
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
      expect(names, contains('idx_comments_target_time'));

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 14);
    });
  });
}
