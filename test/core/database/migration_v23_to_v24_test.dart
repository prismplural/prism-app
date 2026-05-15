import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV23Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    final now = DateTime.utc(2026, 5, 15, 12).millisecondsSinceEpoch ~/ 1000;
    rawDb.execute(
      '''
      INSERT INTO members (id, name, created_at, bio, markdown_enabled)
      VALUES (?, ?, ?, ?, ?)
      ''',
      ['stale-default', 'Stale Default', now, '**bold bio**', 0],
    );
    rawDb.execute('PRAGMA user_version = 23;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v23 -> v24 bio markdown default repair', () {
    test('backfills stale false member markdown flags to true', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v23_to_v24_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v23_to_v24.db');
      await _seedV23Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 24);

      final row = await upgraded
          .customSelect(
            'SELECT markdown_enabled FROM members WHERE id = ?',
            variables: [Variable.withString('stale-default')],
          )
          .getSingle();
      expect(row.read<int>('markdown_enabled'), 1);
    });
  });
}
