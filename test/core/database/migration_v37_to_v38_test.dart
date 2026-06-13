import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Seeds a database at the current schema with the fixtures every part of the
/// folded v37 -> v38 leg touches, then stamps `user_version = 37` (optionally
/// reverting the v38-shaped schema) so reopening runs the migration. The single
/// leg folds CRDT remediation wave 2 (families 4/5/6):
///   1. F03/F10 — clear pending PK switch-deletion stamps on linked tombstones.
///   2. R1/F14  — add the LOCAL-ONLY `sync_generation` incarnation columns.
///   3. F23     — create `pk_identity_sync_aliases` + its lookup index.
///   4. F25     — purge stale self-aliases from `pk_group_sync_aliases`.
///
/// `revertV38Schema:false` leaves the v38-shaped columns/table in place while
/// the version counter says 37 — exercising every idempotency guard (C11: each
/// new step must be re-runnable / safe on dev DBs created at the current schema).
Future<File> _seedV37Db(String name, {required bool revertV38Schema}) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();

  // --- Part 1 (F03/F10): fronting-session delete-stamp fixtures. ---
  // (a) Canonicalization victim: PK-linked tombstone with a stamped intent —
  // both stamps must be cleared.
  await seeded.customStatement(
    'INSERT INTO fronting_sessions '
    '(id, session_type, start_time, member_id, is_deleted, pluralkit_uuid, '
    ' delete_intent_epoch, delete_push_started_at) '
    "VALUES ('victim_a', 0, 1000, 'm1', 1, 'sw-uuid-a', 7, NULL)",
  );
  // (b) Same with an in-flight push already started — both stamps cleared.
  await seeded.customStatement(
    'INSERT INTO fronting_sessions '
    '(id, session_type, start_time, member_id, is_deleted, pluralkit_uuid, '
    ' delete_intent_epoch, delete_push_started_at) '
    "VALUES ('victim_b', 0, 1000, 'm1', 1, 'sw-uuid-b', 9, 1717000000000)",
  );
  // (c) A live PK-linked row with a stray intent stamp (NOT is_deleted) must be
  // left UNTOUCHED — the repair only targets tombstones.
  await seeded.customStatement(
    'INSERT INTO fronting_sessions '
    '(id, session_type, start_time, member_id, is_deleted, pluralkit_uuid, '
    ' delete_intent_epoch, delete_push_started_at) '
    "VALUES ('live_linked', 0, 3000, 'm3', 0, 'sw-uuid-d', 5, NULL)",
  );
  // (d) A tombstone with NO PK link but a stray intent stamp must be left
  // untouched (not a PluralKit switch deletion).
  await seeded.customStatement(
    'INSERT INTO fronting_sessions '
    '(id, session_type, start_time, member_id, is_deleted, pluralkit_uuid, '
    ' delete_intent_epoch, delete_push_started_at) '
    "VALUES ('unlinked_tomb', 0, 4000, 'm4', 1, NULL, 5, NULL)",
  );

  // --- Part 2 (R1/F14): a group + entry to assert the default-0 backfill. ---
  await seeded.customStatement(
    'INSERT INTO member_groups (id, name, display_order, group_type, '
    'created_at, is_deleted, sync_suppressed, sort_state) '
    "VALUES ('g1', 'G1', 0, 0, 0, 0, 0, '{\"mode\":0,\"order\":[]}')",
  );
  await seeded.customStatement(
    'INSERT INTO member_group_entries (id, group_id, member_id, is_deleted, '
    "pending_pk_op) VALUES ('e1', 'g1', 'm1', 0, 'none')",
  );

  // --- Part 4 (F25): stale-self-alias + a legit loser alias. ---
  // The device's own 'pk-group-U' row was soft-deleted on group delete and its
  // uuid NULLed, so the v3->v4 cleanup never purged the surviving self-alias.
  await seeded.customStatement(
    'INSERT INTO member_groups (id, name, display_order, group_type, '
    'created_at, is_deleted, sync_suppressed, sort_state, pluralkit_uuid) '
    "VALUES ('pk-group-uuid-stale', 'Stale', 0, 0, 0, 1, 0, "
    "'{\"mode\":0,\"order\":[]}', NULL)",
  );
  await seeded.customStatement(
    'INSERT INTO pk_group_sync_aliases '
    '(legacy_entity_id, pk_group_uuid, canonical_entity_id, created_at) '
    "VALUES ('pk-group-uuid-stale', 'uuid-stale', 'pk-group:uuid-stale', 0)",
  );
  // Legit loser alias: a random loser row id, NOT the self-id form — survives.
  await seeded.customStatement(
    'INSERT INTO pk_group_sync_aliases '
    '(legacy_entity_id, pk_group_uuid, canonical_entity_id, created_at) '
    "VALUES ('random-loser-id', 'uuid-live', 'pk-group:uuid-live', 0)",
  );
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    if (revertV38Schema) {
      rawDb.execute('ALTER TABLE member_groups DROP COLUMN sync_generation');
      rawDb.execute(
        'ALTER TABLE member_group_entries DROP COLUMN sync_generation',
      );
      rawDb.execute('DROP TABLE IF EXISTS pk_identity_sync_aliases');
    }
    rawDb.execute('PRAGMA user_version = 37');
  } finally {
    rawDb.close();
  }

  return dbFile;
}

Future<Map<String, ({int? epoch, int? pushAt})>> _readStamps(
  AppDatabase db,
) async {
  final rows = await db
      .customSelect(
        'SELECT id, delete_intent_epoch, delete_push_started_at '
        'FROM fronting_sessions',
      )
      .get();
  return {
    for (final r in rows)
      r.read<String>('id'): (
        epoch: r.read<int?>('delete_intent_epoch'),
        pushAt: r.read<int?>('delete_push_started_at'),
      ),
  };
}

Future<Set<String>> _aliasIds(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT legacy_entity_id FROM pk_group_sync_aliases')
      .get();
  return rows.map((r) => r.read<String>('legacy_entity_id')).toSet();
}

void main() {
  group('schema v37 -> v38: CRDT remediation wave 2 (families 4/5/6)', () {
    test('applies all four parts on a v37 database', () async {
      final dbFile = await _seedV37Db(
        'prism_migration_v37_to_v38_apply_',
        revertV38Schema: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version =
          await upgraded.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), greaterThanOrEqualTo(38));

      // Part 1 (F03/F10): PK-linked tombstones cleared; others untouched.
      final stamps = await _readStamps(upgraded);
      expect(stamps['victim_a'], (epoch: null, pushAt: null));
      expect(stamps['victim_b'], (epoch: null, pushAt: null));
      expect(stamps['live_linked'], (epoch: 5, pushAt: null));
      expect(stamps['unlinked_tomb'], (epoch: 5, pushAt: null));

      final deletedLinked = await upgraded
          .customSelect(
            'SELECT id FROM fronting_sessions '
            'WHERE is_deleted = 1 AND pluralkit_uuid IS NOT NULL '
            'AND delete_intent_epoch IS NOT NULL',
          )
          .get();
      expect(deletedLinked, isEmpty,
          reason: 'no PK-linked tombstone may carry a delete intent post-v38');

      // Part 2 (R1/F14): both sync_generation columns exist, default 0.
      final groupCols = (await upgraded
              .customSelect('PRAGMA table_info(member_groups)')
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(groupCols, contains('sync_generation'));
      final entryCols = (await upgraded
              .customSelect('PRAGMA table_info(member_group_entries)')
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(entryCols, contains('sync_generation'));

      final groupGen = await upgraded
          .customSelect(
            'SELECT sync_generation FROM member_groups WHERE id = ?',
            variables: [const Variable<String>('g1')],
          )
          .getSingle();
      expect(groupGen.read<int>('sync_generation'), 0);
      final entryGen = await upgraded
          .customSelect(
            'SELECT sync_generation FROM member_group_entries WHERE id = ?',
            variables: [const Variable<String>('e1')],
          )
          .getSingle();
      expect(entryGen.read<int>('sync_generation'), 0);

      // Part 3 (F23): the new table + its lookup index exist.
      final tables = (await upgraded
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(tables, contains('pk_identity_sync_aliases'));
      final indexes = (await upgraded
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(indexes, contains('idx_pk_identity_sync_aliases_identity'));

      // Part 4 (F25): stale self-alias purged; legit loser alias intact.
      final aliases = await _aliasIds(upgraded);
      expect(aliases, isNot(contains('pk-group-uuid-stale')));
      expect(aliases, contains('random-loser-id'));
    });

    test('idempotent: re-running on a v38-shaped DB is safe', () async {
      // revertV38Schema:false leaves the v38 columns/table in place while the
      // version counter says 37, so the migration re-runs every guard (PRAGMA
      // column checks, createTableIfAbsent, the two idempotent DELETE/UPDATEs)
      // against already-migrated data.
      final dbFile = await _seedV37Db(
        'prism_migration_v37_to_v38_idempotent_',
        revertV38Schema: false,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      final version =
          await upgraded.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), greaterThanOrEqualTo(38));

      final groupCols = (await upgraded
              .customSelect('PRAGMA table_info(member_groups)')
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(groupCols, contains('sync_generation'));

      final tables = (await upgraded
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .get())
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(tables, contains('pk_identity_sync_aliases'));

      final aliases = await _aliasIds(upgraded);
      expect(aliases, isNot(contains('pk-group-uuid-stale')));
      expect(aliases, contains('random-loser-id'));
    });

    test('idempotent statements match zero rows on a re-run', () async {
      // C11: re-running the two DATA statements against already-migrated data
      // must touch no rows (their WHERE predicates self-exclude).
      final dbFile = await _seedV37Db(
        'prism_migration_v37_to_v38_norows_',
        revertV38Schema: true,
      );

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      await upgraded.customStatement(
        'UPDATE fronting_sessions '
        'SET delete_intent_epoch = NULL, delete_push_started_at = NULL '
        'WHERE is_deleted = 1 '
        '  AND pluralkit_uuid IS NOT NULL '
        '  AND delete_intent_epoch IS NOT NULL',
      );
      final stampChanges =
          await upgraded.customSelect('SELECT changes() AS n').getSingle();
      expect(stampChanges.read<int>('n'), 0,
          reason: 'stamp-clear re-run matches zero rows');

      await upgraded.customStatement(
        'DELETE FROM pk_group_sync_aliases '
        "WHERE legacy_entity_id = 'pk-group-' || pk_group_uuid",
      );
      final purgeChanges =
          await upgraded.customSelect('SELECT changes() AS n').getSingle();
      expect(purgeChanges.read<int>('n'), 0,
          reason: 'self-alias purge re-run matches zero rows');
    });
  });
}
