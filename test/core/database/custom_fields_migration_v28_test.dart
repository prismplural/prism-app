import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a v27 database by opening via [AppDatabase] (to materialise all
/// current-schema tables), then stripping the three new custom_fields columns
/// and resetting PRAGMA user_version = 27 so the v27→v28 migration is forced
/// to run on the next open.
Future<void> _seedV27Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // Drift does not support DROP COLUMN on older SQLite builds, so we
    // recreate the table without the three new columns to simulate a v27 DB.
    final cols = rawDb.select('PRAGMA table_info(custom_fields)');
    final hasFieldTypeId = cols.any((r) => r['name'] == 'field_type_id');
    if (hasFieldTypeId) {
      // Recreate table without the three new columns.
      rawDb.execute('BEGIN');
      rawDb.execute('''
        CREATE TABLE custom_fields_v27 (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          field_type INTEGER NOT NULL,
          date_precision INTEGER,
          display_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
      rawDb.execute(
        'INSERT INTO custom_fields_v27 '
        'SELECT id, name, field_type, date_precision, display_order, '
        '       created_at, is_deleted '
        'FROM custom_fields',
      );
      rawDb.execute('DROP TABLE custom_fields');
      rawDb.execute('ALTER TABLE custom_fields_v27 RENAME TO custom_fields');
      rawDb.execute('COMMIT');
    }

    // Remove the new partial index if it was already created.
    rawDb.execute(
      'DROP INDEX IF EXISTS idx_custom_fields_parent',
    );

    rawDb.execute('PRAGMA user_version = 27;');
  } finally {
    rawDb.close();
  }
}

void _insertCustomField(
  raw.Database db, {
  required String id,
  required int fieldType,
  int? datePrecision,
}) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  db.execute(
    'INSERT INTO custom_fields '
    '(id, name, field_type, date_precision, display_order, created_at, is_deleted) '
    'VALUES (?, ?, ?, ?, 0, ?, 0)',
    [id, id, fieldType, datePrecision, nowSec],
  );
}

void main() {
  group('schema v27 -> v28: custom_fields columns + index', () {
    test('backfills field_type_id and leaves parent/config null', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v27_to_v28_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v27_to_v28.db');
      await _seedV27Db(dbFile);

      // Insert two rows BEFORE migration (via raw sqlite while still at v27).
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertCustomField(rawDb, id: 'field-text', fieldType: 0);
        _insertCustomField(
          rawDb,
          id: 'field-date',
          fieldType: 2,
          datePrecision: 0,
        );
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      // Version must be 28 after migration.
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 28);

      // Assert backfill and nulls on the text field.
      final textRow = await upgraded
          .customSelect(
            'SELECT field_type_id, parent_field_id, type_config_json '
            'FROM custom_fields WHERE id = ?',
            variables: [Variable.withString('field-text')],
          )
          .getSingle();
      expect(textRow.read<String>('field_type_id'), 'text');
      expect(textRow.read<String?>('parent_field_id'), isNull);
      expect(textRow.read<String?>('type_config_json'), isNull);

      // Assert backfill and nulls on the date field; date_precision is
      // untouched (stays canonical per spec).
      final dateRow = await upgraded
          .customSelect(
            'SELECT field_type_id, parent_field_id, type_config_json, date_precision '
            'FROM custom_fields WHERE id = ?',
            variables: [Variable.withString('field-date')],
          )
          .getSingle();
      expect(dateRow.read<String>('field_type_id'), 'date');
      expect(dateRow.read<String?>('parent_field_id'), isNull);
      expect(dateRow.read<String?>('type_config_json'), isNull);
      // date_precision stays canonical — NOT moved into type_config_json.
      expect(dateRow.read<int?>('date_precision'), 0);
    });

    test('idx_custom_fields_parent index exists after migration', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v27_to_v28_idx_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/idx.db');
      await _seedV27Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final rows = await upgraded.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type = 'index' AND name = 'idx_custom_fields_parent'
      ''').get();
      expect(rows, hasLength(1));
      expect(rows.first.read<String>('name'), 'idx_custom_fields_parent');
    });

    test('idempotent: columns already present does not error', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v27_to_v28_idem_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/idem.db');
      await _seedV27Db(dbFile);

      // First open — runs the migration normally.
      final first = AppDatabase(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      await first.close();

      // Reset version to 27 so migration re-runs on second open.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 27;');
      } finally {
        rawDb.close();
      }

      // Second open — idempotent path (columns already exist).
      final second = AppDatabase(NativeDatabase(dbFile));
      addTearDown(second.close);
      // Should not throw.
      await second.customSelect('SELECT 1').get();

      final version = await second
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 28);
    });

    test('color and long_text fields backfill correctly', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v27_to_v28_types_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/types.db');
      await _seedV27Db(dbFile);

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertCustomField(rawDb, id: 'field-color', fieldType: 1);
        _insertCustomField(rawDb, id: 'field-longtext', fieldType: 3);
        _insertCustomField(rawDb, id: 'field-unknown', fieldType: 99);
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final colorRow = await upgraded
          .customSelect(
            'SELECT field_type_id FROM custom_fields WHERE id = ?',
            variables: [Variable.withString('field-color')],
          )
          .getSingle();
      expect(colorRow.read<String>('field_type_id'), 'color');

      final longTextRow = await upgraded
          .customSelect(
            'SELECT field_type_id FROM custom_fields WHERE id = ?',
            variables: [Variable.withString('field-longtext')],
          )
          .getSingle();
      expect(longTextRow.read<String>('field_type_id'), 'long_text');

      final unknownRow = await upgraded
          .customSelect(
            'SELECT field_type_id FROM custom_fields WHERE id = ?',
            variables: [Variable.withString('field-unknown')],
          )
          .getSingle();
      // Unknown int maps to NULL.
      expect(unknownRow.read<String?>('field_type_id'), isNull);
    });
  });
}
