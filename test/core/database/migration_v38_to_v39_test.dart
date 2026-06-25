import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<File> _seedV38Db(
  String name, {
  required bool dropMemberNameDisplayColumn,
  int? memberNameDisplay,
}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.customStatement(
    "INSERT OR IGNORE INTO system_settings (id) VALUES ('singleton')",
  );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    if (memberNameDisplay != null) {
      rawDb.execute(
        "UPDATE system_settings SET member_name_display = ? WHERE id = 'singleton'",
        [memberNameDisplay],
      );
    }
    if (dropMemberNameDisplayColumn) {
      rawDb.execute(
        'ALTER TABLE system_settings DROP COLUMN member_name_display',
      );
    }
    rawDb.execute('PRAGMA user_version = 38');
  } finally {
    rawDb.close();
  }

  return dbFile;
}

Future<Set<String>> _systemSettingsColumns(AppDatabase db) async {
  final rows = await db
      .customSelect('PRAGMA table_info(system_settings)')
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<int> _memberNameDisplay(AppDatabase db) async {
  final row = await db
      .customSelect(
        "SELECT member_name_display FROM system_settings WHERE id = 'singleton'",
      )
      .getSingle();
  return row.read<int>('member_name_display');
}

void main() {
  group('schema v38 -> v39: member name display setting', () {
    test('adds member_name_display with display default', () async {
      final dbFile = await _seedV38Db(
        'prism_migration_v38_to_v39_apply_',
        dropMemberNameDisplayColumn: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
      expect(
        await _systemSettingsColumns(upgraded),
        contains('member_name_display'),
      );
      expect(await _memberNameDisplay(upgraded), 0);
    });

    test('is idempotent on a v39-shaped db stamped at v38', () async {
      final dbFile = await _seedV38Db(
        'prism_migration_v38_to_v39_idempotent_',
        dropMemberNameDisplayColumn: false,
        memberNameDisplay: 1,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
      expect(await _memberNameDisplay(upgraded), 1);
    });
  });
}
