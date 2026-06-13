import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// Tests that the schema-rebuild helpers
/// (`ensureFrontingMemberCheckConstraint`, `ensurePkFrontingIndexes`) scrub
/// unrecoverable orphan rows before they install constraints/indexes that
/// would trip on those rows.
///
/// Bug context: a beta user who did a PluralKit file one-time import on an
/// older build had PK-imported rows where the member couldn't be resolved
/// (`session_type=0`, `member_id=NULL`, `pluralkit_uuid=<switch>`). The
/// per-member migration soft-deleted those rows in step 6 but left them in
/// the table. `ensureFrontingMemberCheckConstraint` rebuilds the table via
/// `Migrator.alterTable(TableMigration(...))`, which copies every row
/// regardless of `is_deleted`, so the new
/// `CHECK (session_type != 0 OR member_id IS NOT NULL)` rejected the copy
/// and aborted the migration's post-tx cleanup.
void main() {
  group('ensureFrontingMemberCheckConstraint orphan scrub', () {
    test('rescues active orphans to Unknown and purges deleted leftovers '
        'before installing CHECK', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      // Strip the v14 CHECK so we can seed pre-v14-shaped rows.
      await db.disableFrontingMemberCheckConstraintForTesting();

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Healthy normal row — must survive.
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted) '
        "VALUES ('healthy', 0, $now, NULL, 'm1', '[]', 0, 0)",
      );

      // Sleep row with NULL member_id — legitimate, must survive
      // (session_type=1 satisfies the CHECK).
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted) '
        "VALUES ('sleep', 1, $now, NULL, NULL, '[]', 0, 0)",
      );

      // Soft-deleted PK orphan — the bug case. Must be scrubbed.
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) '
        "VALUES ('pk-orphan', 0, $now, NULL, NULL, '[]', 0, 1, "
        " 'switch-abc')",
      );

      // Non-deleted orphan with no pluralkit_uuid — should be rescued to the
      // Unknown sentinel instead of being deleted.
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted) '
        "VALUES ('native-orphan', 0, $now, NULL, NULL, '[]', 0, 0)",
      );

      // Pre-condition sanity.
      final before = await db
          .customSelect('SELECT COUNT(*) AS c FROM fronting_sessions')
          .getSingle();
      expect(before.read<int>('c'), 4);

      // Action.
      await db.ensureFrontingMemberCheckConstraint();

      // Survivors.
      final survivors = await db
          .customSelect(
            'SELECT id, member_id, pluralkit_uuid '
            'FROM fronting_sessions ORDER BY id',
          )
          .get();
      final ids = survivors.map((r) => r.read<String>('id')).toList();
      expect(ids, ['healthy', 'native-orphan', 'sleep']);
      final rescued = survivors.singleWhere(
        (r) => r.read<String>('id') == 'native-orphan',
      );
      expect(rescued.read<String?>('member_id'), unknownSentinelMemberId);
      expect(
        rescued.read<String?>('pluralkit_uuid'),
        isNull,
        reason: 'rescued active orphans should drop stale PK switch ids',
      );

      final sentinel = await db.membersDao.getMemberById(
        unknownSentinelMemberId,
      );
      expect(sentinel, isNotNull);
      expect(sentinel!.name, 'Unknown');

      // CHECK is now active — inserting a fresh orphan must fail.
      expect(
        () => db.customStatement(
          'INSERT INTO fronting_sessions '
          '(id, session_type, start_time, end_time, member_id, '
          ' co_fronter_ids, is_health_kit_import, is_deleted) '
          "VALUES ('post-check', 0, $now, NULL, NULL, '[]', 0, 0)",
        ),
        throwsA(anything),
        reason:
            'CHECK (session_type != 0 OR member_id IS NOT NULL) '
            'should reject normal rows with NULL member_id',
      );
    });

    test('is a no-op when CHECK is already installed', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      // Fresh schema already has the CHECK. Calling the helper twice in a
      // row must be safe and not perform a second table rebuild (which
      // would require the scrub to run inside the second invocation).
      await db.ensureFrontingMemberCheckConstraint();
      await db.ensureFrontingMemberCheckConstraint();

      // Smoke: a healthy row still inserts.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted) '
        "VALUES ('healthy', 0, $now, NULL, 'm1', '[]', 0, 0)",
      );
    });
  });

  group('ensurePkFrontingIndexes orphan scrub', () {
    test('rescues active orphans before installing PK indexes, '
        'so duplicate orphan switch ids do not block index creation', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      // Strip CHECK and drop existing PK indexes so we can seed
      // duplicate orphans on the same pluralkit_uuid.
      await db.disableFrontingMemberCheckConstraintForTesting();
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid_orphan',
      );
      await db.customStatement(
        'DROP INDEX IF EXISTS '
        'idx_fronting_sessions_pluralkit_uuid_member_id',
      );

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Two orphan rows on the same switch — would trip the orphan
      // unique index if the scrub didn't run first.
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) '
        "VALUES ('orph-1', 0, $now, NULL, NULL, '[]', 0, 0, 'switch-x')",
      );
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) '
        "VALUES ('orph-2', 0, $now, NULL, NULL, '[]', 0, 0, 'switch-x')",
      );

      // Healthy PK row — must survive.
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) '
        "VALUES ('pk-real', 0, $now, NULL, 'm1', '[]', 0, 0, 'switch-y')",
      );

      // Action.
      await db.ensurePkFrontingIndexes();

      // Orphans rescued, healthy survives.
      final survivors = await db
          .customSelect(
            'SELECT id, member_id, pluralkit_uuid '
            'FROM fronting_sessions ORDER BY id',
          )
          .get();
      expect(survivors.map((r) => r.read<String>('id')).toList(), [
        'orph-1',
        'orph-2',
        'pk-real',
      ]);
      for (final orphanId in ['orph-1', 'orph-2']) {
        final row = survivors.singleWhere(
          (r) => r.read<String>('id') == orphanId,
        );
        expect(row.read<String?>('member_id'), unknownSentinelMemberId);
        expect(row.read<String?>('pluralkit_uuid'), isNull);
      }

      // Both indexes exist.
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name LIKE 'idx_fronting_sessions_pluralkit_uuid%'",
          )
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        containsAll([
          'idx_fronting_sessions_pluralkit_uuid_orphan',
          'idx_fronting_sessions_pluralkit_uuid_member_id',
        ]),
      );

      final sentinel = await db.membersDao.getMemberById(
        unknownSentinelMemberId,
      );
      expect(sentinel, isNotNull);
    });
  });

  // R6/C12: the Unknown sentinel uses a deterministic UUIDv5 id. If a previously
  // synced sentinel was deleted, the engine holds an absorbing tombstone for it,
  // and re-creating / re-homing onto it writes into a burned id (a silent
  // fleet-wide no-op + local Rust/Dart divergence). With a TombstoneGate wired
  // the rescue must SKIP — no member row, no emission.
  group('Unknown-sentinel orphan rescue gates on the sync tombstone', () {
    TombstoneGate gateTombstoning(Set<String> ids) {
      return TombstoneGate((table, entityId, field) async {
        if (field != 'is_deleted') return null;
        return ids.contains(entityId) ? 'true' : null;
      });
    }

    Future<void> seedActiveOrphan(AppDatabase db) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.customStatement(
        'INSERT INTO fronting_sessions '
        '(id, session_type, start_time, end_time, member_id, '
        ' co_fronter_ids, is_health_kit_import, is_deleted) '
        "VALUES ('native-orphan', 0, $now, NULL, NULL, '[]', 0, 0)",
      );
    }

    test('a tombstoned sentinel id => rescue does not create the row and '
        'emits nothing into the burned id', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.disableFrontingMemberCheckConstraintForTesting();
      await seedActiveOrphan(db);

      // Engine holds an absorbing tombstone on the sentinel id.
      db.tombstoneGate = gateTombstoning({unknownSentinelMemberId});

      final captured = <String>[];
      SyncRecordMixin.installCaptureSinkForTesting(
        (op) => captured.add('${op.table}/${op.entityId}/${op.opType.name}'),
      );
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // ensurePkFrontingIndexes calls the rescue first. The CHECK is stripped,
      // so the orphan staying NULL won't trip a constraint here; the index
      // install tolerates a single NULL-member orphan.
      await db.ensurePkFrontingIndexes();

      // The sentinel member row was NOT created (burned id).
      final sentinel = await db.membersDao.getMemberById(
        unknownSentinelMemberId,
      );
      expect(sentinel, isNull, reason: 'sentinel id is burned — do not create');

      // The orphan was NOT re-homed onto the burned id.
      final orphan = await db
          .customSelect(
            "SELECT member_id FROM fronting_sessions WHERE id = 'native-orphan'",
          )
          .getSingle();
      expect(orphan.read<String?>('member_id'), isNull);

      // No sync op was emitted into the burned id.
      expect(
        captured.where((e) => e.contains(unknownSentinelMemberId)),
        isEmpty,
        reason: 'must not emit a create into the tombstoned sentinel id',
      );
    });

    test('a live (non-tombstoned) sentinel id => rescue creates the row as '
        'usual', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.disableFrontingMemberCheckConstraintForTesting();
      await seedActiveOrphan(db);

      // Gate wired but the sentinel id is live — rescue proceeds normally.
      db.tombstoneGate = gateTombstoning({});

      await db.ensurePkFrontingIndexes();

      final sentinel = await db.membersDao.getMemberById(
        unknownSentinelMemberId,
      );
      expect(sentinel, isNotNull);
      final orphan = await db
          .customSelect(
            "SELECT member_id FROM fronting_sessions WHERE id = 'native-orphan'",
          )
          .getSingle();
      expect(orphan.read<String?>('member_id'), unknownSentinelMemberId);
    });
  });

  // The rescue rewrites synced columns (member_id, pluralkit_uuid) in raw
  // SQL, which emits no CRDT op — so it must enqueue a sync-repair for each
  // rescued session and for the sentinel member create. The drain re-reads the
  // current values and emits real ops once the engine is healthy.
  group('orphan rescue enqueues sync-repair rows', () {
    Future<List<Map<String, String>>> repairRows(AppDatabase db) async {
      final rows = await db
          .customSelect(
            'SELECT table_name, entity_id, field_names_json, reason '
            'FROM sync_migration_repairs ORDER BY table_name, entity_id',
          )
          .get();
      return [
        for (final r in rows)
          {
            'table': r.read<String>('table_name'),
            'entity': r.read<String>('entity_id'),
            'fields': r.read<String>('field_names_json'),
            'reason': r.read<String>('reason'),
          },
      ];
    }

    Future<void> seedNullMemberOrphans(AppDatabase db, List<String> ids) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final id in ids) {
        await db.customStatement(
          'INSERT OR REPLACE INTO fronting_sessions '
          '(id, session_type, start_time, end_time, member_id, '
          ' co_fronter_ids, is_health_kit_import, is_deleted) '
          "VALUES ('$id', 0, $now, NULL, NULL, '[]', 0, 0)",
        );
      }
    }

    test('enqueues a repair for each rescued session plus the sentinel '
        'member', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.disableFrontingMemberCheckConstraintForTesting();
      await seedNullMemberOrphans(db, ['orph-a', 'orph-b']);

      await db.ensureFrontingMemberCheckConstraint();

      expect(
        await repairRows(db),
        unorderedEquals([
          {
            'table': 'fronting_sessions',
            'entity': 'orph-a',
            'fields': '["member_id","pluralkit_uuid"]',
            'reason': 'fronting_orphan_rescue',
          },
          {
            'table': 'fronting_sessions',
            'entity': 'orph-b',
            'fields': '["member_id","pluralkit_uuid"]',
            'reason': 'fronting_orphan_rescue',
          },
          {
            'table': 'members',
            'entity': unknownSentinelMemberId,
            'fields': '["__create__"]',
            'reason': 'fronting_orphan_rescue',
          },
        ]),
      );
    });

    test('re-running the rescue coalesces onto the same queue rows '
        '(idempotent)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      // Strip CHECK so the rescue (via ensurePkFrontingIndexes) runs every call
      // rather than short-circuiting on the CHECK sniff.
      await db.disableFrontingMemberCheckConstraintForTesting();
      await seedNullMemberOrphans(db, ['orph-a']);

      await db.ensurePkFrontingIndexes();
      expect(await repairRows(db), hasLength(2)); // session + sentinel

      // Re-introduce the same orphan id and re-run: INSERT OR REPLACE on the
      // (table, entity, reason) PK coalesces rather than duplicating.
      await seedNullMemberOrphans(db, ['orph-a']);
      await db.ensurePkFrontingIndexes();
      expect(await repairRows(db), hasLength(2));
    });
  });
}
