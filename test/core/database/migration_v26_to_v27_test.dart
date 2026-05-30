import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

const _seedSeconds = 1747983600; // 2026-05-23T11:00:00Z.

Future<void> _seedV26Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute(
      'INSERT INTO conversations (id, created_at, last_activity_at, title) '
      'VALUES (?, ?, ?, ?)',
      ['conv-v26', _seedSeconds, _seedSeconds, 'V26 conversation'],
    );
    rawDb.execute(
      'INSERT INTO chat_messages '
      '(id, content, timestamp, conversation_id) '
      'VALUES (?, ?, ?, ?), (?, ?, ?, ?)',
      [
        'msg-a',
        'first',
        _seedSeconds,
        'conv-v26',
        'msg-b',
        'second',
        _seedSeconds,
        'conv-v26',
      ],
    );

    rawDb.execute('DROP TABLE IF EXISTS app_preference_values;');
    rawDb.execute('DROP TABLE IF EXISTS member_profile_preference_values;');
    rawDb.execute('DROP INDEX IF EXISTS idx_app_preference_values_deleted;');
    rawDb.execute('DROP INDEX IF EXISTS idx_member_profile_pref_member_key;');
    rawDb.execute(
      'DROP INDEX IF EXISTS idx_member_profile_pref_member_deleted_key;',
    );
    rawDb.execute('PRAGMA user_version = 26;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v26 -> v27', () {
    test('multiplies existing chat timestamps by 1000', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v26_to_v27_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v26_to_v27.db');
      await _seedV26Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), greaterThanOrEqualTo(27));

      final rawRows = await upgraded
          .customSelect('SELECT id, timestamp FROM chat_messages ORDER BY id')
          .get();
      expect(rawRows, hasLength(2));
      for (final row in rawRows) {
        expect(row.read<int>('timestamp'), _seedSeconds * 1000);
      }

      final domain = await upgraded.chatMessagesDao.getMessagesForConversation(
        'conv-v26',
      );
      expect(domain, hasLength(2));
      for (final msg in domain) {
        expect(
          msg.timestamp.toUtc(),
          DateTime.fromMillisecondsSinceEpoch(_seedSeconds * 1000, isUtc: true),
        );
      }
    });

    test('creates app and member profile preference tables', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v26_to_v27_prefs_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/prefs.db');
      await _seedV26Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final appColumns = await upgraded
          .customSelect('PRAGMA table_info(app_preference_values)')
          .get();
      expect(
        appColumns.map((row) => row.read<String>('name')),
        containsAll(['key', 'value_type', 'value_json', 'is_deleted']),
      );
      final appDeleted = appColumns.singleWhere(
        (row) => row.read<String>('name') == 'is_deleted',
      );
      expect(appDeleted.read<int>('notnull'), 1);
      expect(appDeleted.read<String>('dflt_value'), '0');

      final memberColumns = await upgraded
          .customSelect('PRAGMA table_info(member_profile_preference_values)')
          .get();
      expect(
        memberColumns.map((row) => row.read<String>('name')),
        containsAll([
          'id',
          'member_id',
          'key',
          'value_type',
          'value_json',
          'is_deleted',
        ]),
      );
      final memberDeleted = memberColumns.singleWhere(
        (row) => row.read<String>('name') == 'is_deleted',
      );
      expect(memberDeleted.read<int>('notnull'), 1);
      expect(memberDeleted.read<String>('dflt_value'), '0');
    });

    test('rerun on already-migrated chat data is a no-op', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v26_to_v27_rerun_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/rerun.db');
      await _seedV26Db(dbFile);

      final first = AppDatabase(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      await first.close();

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 26;');
      } finally {
        rawDb.close();
      }

      final second = AppDatabase(NativeDatabase(dbFile));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();

      final rows = await second
          .customSelect('SELECT id, timestamp FROM chat_messages ORDER BY id')
          .get();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.read<int>('timestamp'), _seedSeconds * 1000);
      }
    });

    test('creates preference value indexes', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v26_to_v27_indexes_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/prefs_indexes.db');
      await _seedV26Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final rows = await upgraded.customSelect('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'index'
          AND name IN (
            'idx_app_preference_values_deleted',
            'idx_member_profile_pref_member_key',
            'idx_member_profile_pref_member_deleted_key'
          )
      ''').get();

      expect(
        rows.map((row) => row.read<String>('name')).toSet(),
        equals({
          'idx_app_preference_values_deleted',
          'idx_member_profile_pref_member_key',
          'idx_member_profile_pref_member_deleted_key',
        }),
      );
    });
  });
}
