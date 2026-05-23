import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

const _seedSeconds = 1747983600; // 2026-05-23T11:00:00Z, picked deterministically.

Future<void> _seedV26Db(File dbFile) async {
  // Bootstrap at latest schema, write seconds-encoded rows, then stamp back
  // to v26. The column is INTEGER either way — only the unit flips at v27 —
  // so no DDL rollback is needed.
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
        'msg-a', 'first', _seedSeconds, 'conv-v26',
        'msg-b', 'second', _seedSeconds, 'conv-v26',
      ],
    );

    rawDb.execute('PRAGMA user_version = 26;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v26 -> v27: chat_messages.timestamp seconds -> milliseconds', () {
    test('multiplies existing timestamps by 1000', () async {
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
      expect(version.read<int>('user_version'), 27);

      final raw = await upgraded
          .customSelect(
            'SELECT id, timestamp FROM chat_messages ORDER BY id',
          )
          .get();
      expect(raw, hasLength(2));
      for (final row in raw) {
        expect(
          row.read<int>('timestamp'),
          _seedSeconds * 1000,
          reason: 'v27 stores timestamps as ms-since-epoch; seeded seconds '
              'must be multiplied by 1000',
        );
      }

      // Round-trip through the DAO: the converter must decode the migrated
      // ms-int back to the seeded wall-clock time.
      final domain = await upgraded.chatMessagesDao
          .getMessagesForConversation('conv-v26');
      expect(domain, hasLength(2));
      for (final msg in domain) {
        expect(
          msg.timestamp.toUtc(),
          DateTime.fromMillisecondsSinceEpoch(
            _seedSeconds * 1000,
            isUtc: true,
          ),
        );
      }
    });

    test('rerun on already-migrated data is a no-op', () async {
      // Crash window between UPDATE and user_version=27, and dev workflows
      // that reset user_version back to 26 with ms data.
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v26_to_v27_rerun_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/rerun.db');
      await _seedV26Db(dbFile);

      // First migration: seconds -> ms.
      final first = AppDatabase(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      await first.close();

      // Simulate the rerun scenario by stamping user_version back to 26
      // without touching the (now ms-encoded) timestamp values.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 26;');
      } finally {
        rawDb.close();
      }

      // Second migration: must NOT multiply again.
      final second = AppDatabase(NativeDatabase(dbFile));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();

      final rows = await second
          .customSelect(
            'SELECT id, timestamp FROM chat_messages ORDER BY id',
          )
          .get();
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(
          row.read<int>('timestamp'),
          _seedSeconds * 1000,
          reason: 'magnitude guard must skip rows that are already ms-encoded',
        );
      }
    });
  });
}
