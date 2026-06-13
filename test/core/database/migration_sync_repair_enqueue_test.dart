import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// The historical migration steps still rewrite synced columns, but the
/// 0.13.0 schema fold collapsed the wave's intermediate versions into the
/// v32->v37 / v37->v38 flatten legs, which makes those historical steps
/// unreachable for real installs (they jump v32->v38). The in-migration repair
/// enqueue is therefore dead and was dropped; convergence for already-diverged
/// installs is handled at runtime by MigrationSyncRepairService's one-time
/// blanket backfill (covered by its own test). These tests seed a v21 DB, run
/// the v21->current upgrade, and assert the data rewrites still happen while the
/// repair queue stays EMPTY (no in-migration enqueue).

Future<void> _seedV21Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    final cols = rawDb.select('PRAGMA table_info(member_groups)');
    if (cols.any((row) => row['name'] == 'sort_state')) {
      rawDb.execute('ALTER TABLE member_groups DROP COLUMN sort_state');
    }
    for (final column in [
      'palette_source',
      'palette_seed_color_hex',
      'palette_mood',
      'palette_contrast',
    ]) {
      rawDb.execute('ALTER TABLE system_settings DROP COLUMN $column');
    }
    final convCols = rawDb.select('PRAGMA table_info(conversations)');
    if (convCols.any((row) => row['name'] == 'includes_all_members')) {
      rawDb.execute(
        'ALTER TABLE conversations DROP COLUMN includes_all_members',
      );
    }
    rawDb.execute('PRAGMA user_version = 21;');
  } finally {
    rawDb.close();
  }
}

void _insertGroup(raw.Database db, String id) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  db.execute(
    'INSERT INTO member_groups '
    '(id, name, display_order, group_type, created_at, is_deleted, '
    ' sync_suppressed) VALUES (?, ?, 0, 0, ?, 0, 0)',
    [id, 'group $id', nowSec],
  );
}

void _insertMember(raw.Database db, String id, {required int markdownEnabled}) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  db.execute(
    'INSERT INTO members '
    '(id, name, created_at, is_admin, display_order, is_active, is_deleted, '
    ' markdown_enabled) VALUES (?, ?, ?, 0, 0, 1, 0, ?)',
    [id, 'Member $id', nowSec, markdownEnabled],
  );
}

void _insertConversation(
  raw.Database db,
  String id, {
  String? creatorId,
  List<String> participantIds = const [],
}) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  db.execute(
    'INSERT INTO conversations '
    '(id, created_at, last_activity_at, title, creator_id, participant_ids, '
    ' is_direct_message, is_deleted) VALUES (?, ?, ?, ?, ?, ?, 0, 0)',
    [id, nowSec, nowSec, null, creatorId, jsonEncode(participantIds)],
  );
}

Future<List<Map<String, Object?>>> _repairs(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT table_name, entity_id, field_names_json, reason '
        'FROM sync_migration_repairs '
        'ORDER BY table_name, entity_id, reason',
      )
      .get();
  return rows
      .map(
        (r) => <String, Object?>{
          'table': r.read<String>('table_name'),
          'entity_id': r.read<String>('entity_id'),
          'fields': jsonDecode(r.read<String>('field_names_json')),
          'reason': r.read<String>('reason'),
        },
      )
      .toList();
}

void main() {
  group('F28: migration rewrites enqueue sync repairs', () {
    test(
      'v21→current performs the data rewrites but enqueues no in-migration '
      'repairs post-flatten',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_f28_enqueue_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final dbFile = File('${tempDir.path}/db.sqlite');
        await _seedV21Db(dbFile);

        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          _insertGroup(rawDb, 'g1');
          // markdown_enabled = 0 will be flipped to 1 by the migration.
          _insertMember(rawDb, 'm_off', markdownEnabled: 0);
          // Already enabled — must NOT be enqueued (WHERE no longer matches).
          _insertMember(rawDb, 'm_on', markdownEnabled: 1);
          // An everyone-group conversation (>2 participants, no DM heuristic).
          _insertConversation(
            rawDb,
            'c_everyone',
            creatorId: 'm_on',
            participantIds: const ['m_on', 'm_off', 'extra'],
          );
        } finally {
          rawDb.close();
        }

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        // Data rewrites happened.
        final mOff = await upgraded
            .customSelect(
              'SELECT markdown_enabled FROM members WHERE id = ?',
              variables: [Variable.withString('m_off')],
            )
            .getSingle();
        expect(mOff.read<bool>('markdown_enabled'), isTrue);

        final everyone = await upgraded
            .customSelect(
              'SELECT includes_all_members FROM conversations WHERE id = ?',
              variables: [Variable.withString('c_everyone')],
            )
            .getSingle();
        expect(everyone.read<bool>('includes_all_members'), isTrue);

        // No in-migration enqueue post-flatten: the historical steps that
        // performed the rewrites are unreachable for real installs, so the
        // repair queue stays empty. Convergence for diverged installs is via
        // MigrationSyncRepairService's runtime blanket backfill.
        expect(await _repairs(upgraded), isEmpty);
      },
    );

    test('a clean current-schema DB enqueues nothing', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      expect(await _repairs(db), isEmpty);
    });
  });
}
