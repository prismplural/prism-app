import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

Future<void> _seedV8Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded
      .into(seeded.frontingSessions)
      .insert(
        FrontingSessionsCompanion.insert(
          id: 'session-v8',
          startTime: DateTime.utc(2026, 4, 29, 12),
          memberId: const Value('member-1'),
          notes: const Value('existing row'),
          pluralkitUuid: const Value('api-switch-uuid'),
        ),
      );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('ALTER TABLE fronting_sessions DROP COLUMN pk_import_source');
    rawDb.execute(
      'ALTER TABLE fronting_sessions DROP COLUMN pk_file_switch_id',
    );
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_source');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_layout');
    rawDb.execute('ALTER TABLE members DROP COLUMN profile_header_image_data');
    rawDb.execute('ALTER TABLE members DROP COLUMN pk_banner_image_data');
    rawDb.execute('ALTER TABLE members DROP COLUMN pk_banner_cached_url');
    rawDb.execute('PRAGMA user_version = 8;');
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v9 migration (PK fronting file-origin metadata)', () {
    test('fresh schema has nullable PK file metadata columns', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final columns = await db
          .customSelect('PRAGMA table_info(fronting_sessions)')
          .get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      expect(names, contains('pk_import_source'));
      expect(names, contains('pk_file_switch_id'));

      await db
          .into(db.frontingSessions)
          .insert(
            FrontingSessionsCompanion.insert(
              id: 'native-session',
              startTime: DateTime.utc(2026, 4, 29, 12),
            ),
          );

      final row = await (db.select(
        db.frontingSessions,
      )..where((s) => s.id.equals('native-session'))).getSingle();
      expect(row.pkImportSource, isNull);
      expect(row.pkFileSwitchId, isNull);
    });

    test(
      'v8 -> v9 adds nullable columns without changing existing rows',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v8_to_v9_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v8_to_v9.db');
        await _seedV8Db(dbFile);

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        final columns = await upgraded
            .customSelect('PRAGMA table_info(fronting_sessions)')
            .get();
        final names = columns.map((row) => row.read<String>('name')).toSet();
        expect(names, contains('pk_import_source'));
        expect(names, contains('pk_file_switch_id'));

        final row = await (upgraded.select(
          upgraded.frontingSessions,
        )..where((s) => s.id.equals('session-v8'))).getSingle();
        expect(row.pluralkitUuid, 'api-switch-uuid');
        expect(row.pkImportSource, isNull);
        expect(row.pkFileSwitchId, isNull);

        final version = await upgraded
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.first.read<int>('user_version'), 10);
      },
    );
  });
}
