import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';

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
}
