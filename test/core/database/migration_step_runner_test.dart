import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// The migration step-runner makes the Drift onUpgrade chain
/// transactional, idempotent, and resumable via per-step `PRAGMA user_version`
/// stamping. These tests pin the three guarantees the runner provides:
///
///  1. an already-applied partial DDL stamped at a stale version unwedges on
///     the next launch instead of throwing "duplicate column name" /
///     "table already exists";
///  2. a kill mid-chain leaves `user_version` at the last *completed* step's
///     target, and re-opening finishes the chain;
///  3. every step is idempotent — re-running the whole chain over an
///     already-current-shaped DB is a no-op with an identical schema.

/// Opens a fresh current-schema DB, then returns its file with `user_version`
/// rewound to [version] (the new tables/columns above [version] stay in place,
/// which is exactly the wedged-install shape: committed DDL, stale stamp).
Future<File> _seedCurrentDb(String name) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  final dbFile = File('${tempDir.path}/db.sqlite');
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();
  return dbFile;
}

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<Set<String>> _tables(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

/// Captures a comparable schema fingerprint: every table plus its column set.
Future<Map<String, Set<String>>> _schemaFingerprint(AppDatabase db) async {
  final out = <String, Set<String>>{};
  for (final table in await _tables(db)) {
    if (table.startsWith('sqlite_')) continue;
    out[table] = await _columns(db, table);
  }
  return out;
}

void main() {
  group('F20 migration step-runner', () {
    test(
        'wedged install: a partial ADD COLUMN + table-create stamped at a stale '
        'version completes the chain with no duplicate-column / table-exists '
        'error', () async {
      final dbFile = await _seedCurrentDb('prism_f20_wedged_');

      // Simulate a process death inside the final v37->v38 flatten leg after it
      // added some DDL but before it stamped: the new columns/tables are
      // committed, but the version still says 37. (The 0.13.0 fold collapses the
      // wave's intermediate dev versions into the v32->v37 and v37->v38 flatten
      // legs, so 37 is the wedge boundary that re-runs the sync_generation /
      // pk_identity_sync_aliases / sync_op_outbox DDL.) A pre-runner chain would
      // re-run the raw ADD COLUMN / CREATE TABLE and throw "duplicate column
      // name" / "table already exists", boot-looping forever.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 37');
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);
      // Must not throw on open.
      await upgraded.customSelect('SELECT 1').get();

      final version =
          await upgraded.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
      // The already-present columns/tables survive and the chain reaches head.
      expect(await _columns(upgraded, 'member_groups'),
          contains('sync_generation'));
      expect(await _tables(upgraded), contains('sync_op_outbox'));
      expect(await _tables(upgraded), contains('pk_identity_sync_aliases'));
    });

    test(
        'per-step stamping: a kill mid-chain leaves user_version at the last '
        'completed step, and re-opening completes the chain', () async {
      final dbFile = await _seedCurrentDb('prism_f20_stamp_');

      // Rewind to v37 and drop everything the final v37->v38 flatten leg re-adds,
      // so that leg has real work and its stamp is observable. (The 0.13.0 fold
      // collapses the wave's intermediate dev versions into the v32->v37 and
      // v37->v38 flatten legs, so v37 is the boundary at which the last leg's
      // sync_generation / pk_identity_sync_aliases / sync_op_outbox DDL re-runs.)
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('ALTER TABLE member_groups DROP COLUMN sync_generation');
        rawDb.execute(
          'ALTER TABLE member_group_entries DROP COLUMN sync_generation',
        );
        rawDb.execute('DROP TABLE IF EXISTS pk_identity_sync_aliases');
        rawDb.execute('DROP TABLE IF EXISTS sync_op_outbox');
        rawDb.execute('PRAGMA user_version = 37');
      } finally {
        rawDb.close();
      }

      // Fault-inject a failure just before the v37->v38 step: nothing past the
      // current stamp has run yet, so the runner throws before applying it. The
      // first open propagates the injected error.
      final wedged = AppDatabase(NativeDatabase(dbFile))
        ..debugFailMigrationStepTo = 38;
      await expectLater(
        wedged.customSelect('SELECT 1').get(),
        throwsA(isA<StateError>()),
      );
      await wedged.close();

      // The stamp still sits at the last completed step's target (37) — the
      // failing v37->v38 step never committed its transaction, so neither its
      // DDL nor its PRAGMA landed.
      final afterCrash = raw.sqlite3.open(dbFile.path);
      try {
        final ver =
            afterCrash.select('PRAGMA user_version').first['user_version'];
        expect(ver, 37);
        // The failing step's column/table did not land.
        final cols = afterCrash
            .select('PRAGMA table_info(member_groups)')
            .map((r) => r['name'] as String)
            .toSet();
        expect(cols, isNot(contains('sync_generation')));
        final tables = afterCrash
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((r) => r['name'] as String)
            .toSet();
        expect(tables, isNot(contains('pk_identity_sync_aliases')));
      } finally {
        afterCrash.close();
      }

      // Re-open without the fault: the chain resumes at 37 and finishes.
      final resumed = AppDatabase(NativeDatabase(dbFile));
      addTearDown(resumed.close);
      await resumed.customSelect('SELECT 1').get();
      final version =
          await resumed.customSelect('PRAGMA user_version').getSingle();
      expect(
        version.read<int>('user_version'),
        AppDatabase.currentSchemaVersion,
      );
      expect(await _columns(resumed, 'member_groups'),
          contains('sync_generation'));
      expect(await _tables(resumed), contains('pk_identity_sync_aliases'));
      expect(await _tables(resumed), contains('sync_op_outbox'));
    });

    test(
        'idempotency sweep: re-running the chain from every step boundary over '
        'an already-current-shaped DB is a no-op with an identical schema',
        () async {
      // One looped test over the data-driven step list: for each step `from`,
      // rewind a current-shaped DB to that version and open twice. The first
      // open runs the chain (every applicable step's idempotency guard fires
      // against already-present DDL); the second open re-runs it after another
      // rewind, and the resulting schema must be byte-for-byte identical with
      // no throw on either pass.
      final probe = await _seedCurrentDb('prism_f20_bounds_');
      final probeDb = AppDatabase(NativeDatabase(probe));
      final froms = probeDb.debugMigrationStepBounds
          .map((b) => b.$1)
          .toSet()
          .toList()
        ..sort();
      await probeDb.close();

      for (final from in froms) {
        final dbFile = await _seedCurrentDb('prism_f20_sweep_${from}_');

        Future<void> rewind() async {
          final rawDb = raw.sqlite3.open(dbFile.path);
          try {
            rawDb.execute('PRAGMA user_version = $from');
          } finally {
            rawDb.close();
          }
        }

        await rewind();
        final first = AppDatabase(NativeDatabase(dbFile));
        await first.customSelect('SELECT 1').get();
        final firstSchema = await _schemaFingerprint(first);
        final firstVersion = (await first
                .customSelect('PRAGMA user_version')
                .getSingle())
            .read<int>('user_version');
        await first.close();

        await rewind();
        final second = AppDatabase(NativeDatabase(dbFile));
        // The whole point of the step runner: re-running already-applied steps must not
        // throw "duplicate column name" / "table already exists".
        await second.customSelect('SELECT 1').get();
        final secondSchema = await _schemaFingerprint(second);
        final secondVersion = (await second
                .customSelect('PRAGMA user_version')
                .getSingle())
            .read<int>('user_version');
        await second.close();

        expect(firstVersion, AppDatabase.currentSchemaVersion,
            reason: 'first open from v$from should reach head');
        expect(secondVersion, AppDatabase.currentSchemaVersion,
            reason: 're-open from v$from should reach head');
        expect(secondSchema, firstSchema,
            reason: 'schema must be identical after re-running from v$from');
      }
    });
  });
}
