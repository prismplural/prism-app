import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<File> _seedV28Db(String name, {required bool dropColumn}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded
      .into(seeded.members)
      .insert(
        MembersCompanion.insert(
          id: 'member-1',
          name: 'Member One',
          createdAt: DateTime.utc(2026, 5, 27),
        ),
      );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    if (dropColumn) {
      rawDb.execute('ALTER TABLE members DROP COLUMN pk_avatar_cached_url');
    }
    rawDb.execute('PRAGMA user_version = 28');
  } finally {
    rawDb.close();
  }

  return dbFile;
}

void main() {
  group('schema v28 -> v29: PK avatar cached URL', () {
    test('adds pk_avatar_cached_url to existing member tables', () async {
      final dbFile = await _seedV28Db(
        'prism_migration_v28_to_v29_add_',
        dropColumn: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 29);

      final cols = await upgraded
          .customSelect('PRAGMA table_info(members)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('pk_avatar_cached_url'));

      final row = await upgraded.membersDao.getMemberById('member-1');
      expect(row, isNotNull);
      expect(row!.pkAvatarCachedUrl, isNull);
    });

    test('skips cleanly when dev databases already have the column', () async {
      final dbFile = await _seedV28Db(
        'prism_migration_v28_to_v29_skip_',
        dropColumn: false,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final cols = await upgraded
          .customSelect('PRAGMA table_info(members)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('pk_avatar_cached_url'));
    });
  });
}
