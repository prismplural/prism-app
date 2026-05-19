import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a v25 database.
///
/// Opens via [AppDatabase] to materialize the current schema, then drops the
/// `avatar_image_data` column from `member_groups` and resets
/// `PRAGMA user_version = 25` so the v25→v26 migration is forced to run on the
/// next open.
Future<void> _seedV25Db(File dbFile, {bool withAvatarColumn = false}) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  if (!withAvatarColumn) {
    final rawDb = raw.sqlite3.open(dbFile.path);
    try {
      final cols = rawDb.select('PRAGMA table_info(member_groups)');
      final hasAvatar = cols.any((row) => row['name'] == 'avatar_image_data');
      if (hasAvatar) {
        rawDb.execute(
          'ALTER TABLE member_groups DROP COLUMN avatar_image_data',
        );
      }
    } finally {
      rawDb.close();
    }
  }

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('PRAGMA user_version = 25;');
  } finally {
    rawDb.close();
  }
}

void _insertGroup(raw.Database db, String id) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  db.execute(
    'INSERT INTO member_groups '
    '(id, name, display_order, group_type, created_at, is_deleted, '
    ' sync_suppressed, sort_state) '
    'VALUES (?, ?, 0, 0, ?, 0, 0, ?)',
    [id, id, nowSec, '{"mode":0,"order":[]}'],
  );
}

void main() {
  group('schema v25 → v26: avatar_image_data migration', () {
    test('addColumn branch: column is absent → migration adds it', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v25_to_v26_add_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/add_col.db');
      // Seed without avatar column so the addColumn branch runs.
      await _seedV25Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      // PRAGMA user_version must be 26 after migration.
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 26);

      // avatar_image_data must now be present as a nullable BLOB column.
      final cols = await upgraded
          .customSelect('PRAGMA table_info(member_groups)')
          .get();
      final avatarCol = cols.firstWhere(
        (row) => row.read<String>('name') == 'avatar_image_data',
        orElse: () => throw StateError('avatar_image_data column missing'),
      );
      // notnull == 0 means nullable.
      expect(avatarCol.read<int>('notnull'), 0);
      // dflt_value is null for this column.
      expect(avatarCol.read<String?>('dflt_value'), isNull);
    });

    test('addColumn branch: round-trip avatar bytes', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v25_to_v26_roundtrip_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/roundtrip.db');
      await _seedV25Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      // Insert a group with avatar bytes directly via raw SQL.
      final avatarBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g_avatar');
        rawDb.execute(
          'UPDATE member_groups SET avatar_image_data = ? WHERE id = ?',
          [avatarBytes, 'g_avatar'],
        );
      } finally {
        rawDb.close();
      }

      // Re-read via Drift and confirm bytes match.
      final row = await upgraded
          .customSelect(
            'SELECT avatar_image_data FROM member_groups WHERE id = ?',
            variables: [Variable.withString('g_avatar')],
          )
          .getSingle();
      final readBack = row.read<Uint8List?>('avatar_image_data');
      expect(readBack, isNotNull);
      expect(readBack, equals(avatarBytes));
    });

    test('idempotent skip branch: column already exists → migration does not error',
        () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v25_to_v26_skip_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/skip_col.db');
      // Seed WITH the avatar column still present (skip the drop step).
      await _seedV25Db(dbFile, withAvatarColumn: true);

      // Re-open — the idempotent guard must skip addColumn without error.
      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 26);

      // Sanity round-trip: insert a row, read back.
      final avatarBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g_idempotent');
        rawDb.execute(
          'UPDATE member_groups SET avatar_image_data = ? WHERE id = ?',
          [avatarBytes, 'g_idempotent'],
        );
      } finally {
        rawDb.close();
      }

      final row = await upgraded
          .customSelect(
            'SELECT avatar_image_data FROM member_groups WHERE id = ?',
            variables: [Variable.withString('g_idempotent')],
          )
          .getSingle();
      expect(row.read<Uint8List?>('avatar_image_data'), equals(avatarBytes));
    });
  });
}
