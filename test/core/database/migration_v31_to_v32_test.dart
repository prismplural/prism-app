import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a database at the current schema, seeds one conversation, then stamps
/// `user_version = 31` (optionally dropping the new column) so reopening runs
/// the v31 → v32 migration chain. Mirrors migration_v28_to_v29_test.
Future<File> _seedV31Db(String name, {required bool dropColumn}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded
      .into(seeded.conversations)
      .insert(
        ConversationsCompanion.insert(
          id: 'conv-1',
          createdAt: DateTime.utc(2026, 5, 27),
          lastActivityAt: DateTime.utc(2026, 5, 27),
        ),
      );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    if (dropColumn) {
      rawDb.execute(
        'ALTER TABLE conversations DROP COLUMN archived_for_everyone',
      );
    }
    rawDb.execute('PRAGMA user_version = 31');
  } finally {
    rawDb.close();
  }

  return dbFile;
}

void main() {
  group('schema v31 -> v32: conversations.archived_for_everyone', () {
    test('adds archived_for_everyone defaulting to false', () async {
      final dbFile = await _seedV31Db(
        'prism_migration_v31_to_v32_add_',
        dropColumn: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), greaterThanOrEqualTo(32));

      final cols = await upgraded
          .customSelect('PRAGMA table_info(conversations)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('archived_for_everyone'));

      final row = await upgraded
          .customSelect(
            'SELECT archived_for_everyone FROM conversations WHERE id = ?',
            variables: [Variable<String>('conv-1')],
          )
          .getSingle();
      expect(row.read<int>('archived_for_everyone'), 0);
    });

    test('idempotent: skips cleanly when the column already exists', () async {
      // dropColumn:false leaves the v32-shaped column in place while the
      // user_version says 31 — exercises the migration's PRAGMA guard.
      final dbFile = await _seedV31Db(
        'prism_migration_v31_to_v32_skip_',
        dropColumn: false,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final cols = await upgraded
          .customSelect('PRAGMA table_info(conversations)')
          .get();
      final names = cols.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('archived_for_everyone'));
    });
  });
}
