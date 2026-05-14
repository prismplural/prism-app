import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';

/// Seeds a v21 database — the helper opens the file via [AppDatabase] to
/// create the current schema, then defensively drops the v22 column
/// (`sort_state`) if present and resets `PRAGMA user_version = 21` so the
/// v21→v22 migration is forced to run when the file is opened again.
///
/// The caller is responsible for inserting any test rows after the seed.
Future<void> _seedV21Db(File dbFile) async {
  // Bring the file up to the current schema via Drift.
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    // Defensive: drop the column added by v22 if present, so re-running this
    // helper on a half-migrated file still produces a v21 baseline.
    final cols = rawDb.select('PRAGMA table_info(member_groups)');
    final hasSortState = cols.any((row) => row['name'] == 'sort_state');
    if (hasSortState) {
      rawDb.execute('ALTER TABLE member_groups DROP COLUMN sort_state');
    }

    rawDb.execute('PRAGMA user_version = 21;');
  } finally {
    rawDb.close();
  }
}

/// Inserts a member_groups row directly via raw sqlite to bypass the
/// post-migration schema's required columns. `created_at` is stored as a
/// unix-seconds integer (Drift's encoding for DateTimeColumn).
void _insertGroup(raw.Database db, String id, {String name = 'g'}) {
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  db.execute(
    'INSERT INTO member_groups '
    '(id, name, display_order, group_type, created_at, is_deleted, '
    ' sync_suppressed) '
    'VALUES (?, ?, 0, 0, ?, 0, 0)',
    [id, name, nowSec],
  );
}

/// Inserts a member_group_entries row directly via raw sqlite. The optional
/// [isDeleted] flag covers soft-deleted entries.
void _insertEntry(
  raw.Database db,
  String entryId,
  String groupId, {
  bool isDeleted = false,
}) {
  db.execute(
    'INSERT INTO member_group_entries '
    '(id, group_id, member_id, is_deleted, pending_pk_op) '
    'VALUES (?, ?, ?, ?, ?)',
    [entryId, groupId, 'm_$entryId', isDeleted ? 1 : 0, 'none'],
  );
}

void main() {
  group('schema v21 → v22: sort_state column + Dart-loop backfill', () {
    test('empty database: migration succeeds with no rows to backfill',
        () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v21_to_v22_empty_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/empty.db');
      await _seedV21Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 22);

      final groups = await upgraded
          .customSelect('SELECT COUNT(*) AS c FROM member_groups')
          .getSingle();
      expect(groups.read<int>('c'), 0);
    });

    test('group with 0 entries → sort_state == default empty manual', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v21_to_v22_empty_group_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/empty_group.db');
      await _seedV21Db(dbFile);

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g1');
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final row = await upgraded
          .customSelect(
            'SELECT sort_state FROM member_groups WHERE id = ?',
            variables: [Variable.withString('g1')],
          )
          .getSingle();
      expect(row.read<String>('sort_state'), '{"mode":0,"order":[]}');
    });

    test('group with 1 entry → sort_state.order has that id', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v21_to_v22_one_entry_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/one_entry.db');
      await _seedV21Db(dbFile);

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g1');
        _insertEntry(rawDb, 'e1', 'g1');
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final row = await upgraded
          .customSelect(
            'SELECT sort_state FROM member_groups WHERE id = ?',
            variables: [Variable.withString('g1')],
          )
          .getSingle();
      final rawSortState = row.read<String>('sort_state');
      final json = jsonDecode(rawSortState) as Map<String, dynamic>;
      expect(json['mode'], 0);
      expect(json['order'], ['e1']);

      // Closes the loop: the JSON the migration writes must parse cleanly
      // through the production decoder.
      final decoded = tryDecodeSortState(rawSortState);
      expect(decoded, isNotNull);
      expect(decoded!.mode, GroupSortMode.manual);
      expect(decoded.manualOrder, ['e1']);
    });

    test('group with 5 entries → JSON order length 5 in rowid order',
        () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v21_to_v22_five_entries_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/five_entries.db');
      await _seedV21Db(dbFile);

      // Insert entries with ids in non-rowid-sorted order — the backfill must
      // order by rowid (insertion order), NOT by lexicographic id.
      final inserted = <String>['e_zeta', 'e_alpha', 'e_mu', 'e_beta', 'e_nu'];
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g1');
        for (final id in inserted) {
          _insertEntry(rawDb, id, 'g1');
        }
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final row = await upgraded
          .customSelect(
            'SELECT sort_state FROM member_groups WHERE id = ?',
            variables: [Variable.withString('g1')],
          )
          .getSingle();
      final json = jsonDecode(row.read<String>('sort_state'))
          as Map<String, dynamic>;
      expect(json['mode'], 0);
      final order = (json['order'] as List).cast<String>();
      expect(order, inserted);
      expect(order.length, 5);
    });

    test('group with a soft-deleted entry → that id excluded from order',
        () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v21_to_v22_soft_deleted_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/soft_deleted.db');
      await _seedV21Db(dbFile);

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g1');
        _insertEntry(rawDb, 'e_live_a', 'g1');
        _insertEntry(rawDb, 'e_tombstoned', 'g1', isDeleted: true);
        _insertEntry(rawDb, 'e_live_b', 'g1');
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final row = await upgraded
          .customSelect(
            'SELECT sort_state FROM member_groups WHERE id = ?',
            variables: [Variable.withString('g1')],
          )
          .getSingle();
      final json = jsonDecode(row.read<String>('sort_state'))
          as Map<String, dynamic>;
      final order = (json['order'] as List).cast<String>();
      expect(order, ['e_live_a', 'e_live_b']);
      expect(order, isNot(contains('e_tombstoned')));
    });

    test('mixed: 3 groups (0/1/5 entries) → no cross-contamination', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'prism_migration_v21_to_v22_mixed_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/mixed.db');
      await _seedV21Db(dbFile);

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        _insertGroup(rawDb, 'g_empty');
        _insertGroup(rawDb, 'g_one');
        _insertGroup(rawDb, 'g_five');
        _insertEntry(rawDb, 'one_e1', 'g_one');
        for (var i = 0; i < 5; i++) {
          _insertEntry(rawDb, 'five_e$i', 'g_five');
        }
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      Future<Map<String, dynamic>> sortStateFor(String groupId) async {
        final row = await upgraded
            .customSelect(
              'SELECT sort_state FROM member_groups WHERE id = ?',
              variables: [Variable.withString(groupId)],
            )
            .getSingle();
        return jsonDecode(row.read<String>('sort_state'))
            as Map<String, dynamic>;
      }

      final empty = await sortStateFor('g_empty');
      expect(empty['mode'], 0);
      expect(empty['order'], <String>[]);

      final one = await sortStateFor('g_one');
      expect(one['order'], ['one_e1']);

      final five = await sortStateFor('g_five');
      final fiveOrder = (five['order'] as List).cast<String>();
      expect(
        fiveOrder,
        ['five_e0', 'five_e1', 'five_e2', 'five_e3', 'five_e4'],
      );
    });

    test(
      'large-group stress: 1000 entries → JSON parses, order length 1000, '
      'no duplicates',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v21_to_v22_stress_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/stress.db');
        await _seedV21Db(dbFile);

        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          _insertGroup(rawDb, 'g_big');
          rawDb.execute('BEGIN');
          for (var i = 0; i < 1000; i++) {
            _insertEntry(rawDb, 'e_$i', 'g_big');
          }
          rawDb.execute('COMMIT');
        } finally {
          rawDb.close();
        }

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        final row = await upgraded
            .customSelect(
              'SELECT sort_state FROM member_groups WHERE id = ?',
              variables: [Variable.withString('g_big')],
            )
            .getSingle();
        final rawSortState = row.read<String>('sort_state');
        final json = jsonDecode(rawSortState) as Map<String, dynamic>;
        final order = (json['order'] as List).cast<String>();
        expect(order.length, 1000);
        expect(order.toSet().length, 1000, reason: 'no duplicates');

        // Closes the loop: even a 1000-element backfill must round-trip
        // cleanly through the production decoder (sort_state has to be
        // readable on next app launch).
        final decoded = tryDecodeSortState(rawSortState);
        expect(decoded, isNotNull);
        expect(decoded!.mode, GroupSortMode.manual);
        expect(decoded.manualOrder.length, 1000);
        expect(decoded.manualOrder.first, 'e_0');
      },
    );

    test(
      'schema assertions: sort_state on member_groups with expected default; '
      'member_group_entries unchanged',
      () async {
        final tempDir = Directory.systemTemp.createTempSync(
          'prism_migration_v21_to_v22_schema_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/schema.db');
        await _seedV21Db(dbFile);

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);
        await upgraded.customSelect('SELECT 1').get();

        // member_groups must have sort_state with the documented default.
        final groupCols = await upgraded
            .customSelect('PRAGMA table_info(member_groups)')
            .get();
        final sortStateCol = groupCols.firstWhere(
          (row) => row.read<String>('name') == 'sort_state',
          orElse: () => throw StateError('sort_state column missing'),
        );
        expect(
          sortStateCol.read<String>('dflt_value'),
          // SQLite returns the column default literal as it appears in the
          // DDL — Drift wraps TEXT defaults in single quotes.
          "'{\"mode\":0,\"order\":[]}'",
        );

        // member_group_entries schema must be unchanged: enumerate the column
        // names and assert no `sort_state` appears.
        final entryCols = await upgraded
            .customSelect('PRAGMA table_info(member_group_entries)')
            .get();
        final entryColNames = entryCols
            .map((row) => row.read<String>('name'))
            .toSet();
        expect(entryColNames, isNot(contains('sort_state')));
        // Sanity: pre-existing columns are still there.
        expect(entryColNames, containsAll(<String>{'id', 'group_id', 'member_id'}));
      },
    );
  });
}
