import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  group('PK group sync DateTime encoding', () {
    test('PkGroupEntryDeferredSyncOpsDao.upsert round-trips DateTime without '
        'drifting into year ~58,000', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final before = DateTime.now();
      await db.pkGroupEntryDeferredSyncOpsDao.upsert(
        PkGroupEntryDeferredSyncOpsCompanion.insert(
          id: 'deferred-roundtrip',
          entityType: 'member_group_entries',
          entityId: 'entry-roundtrip',
          fieldsJson: jsonEncode({
            'pk_group_uuid': 'pk-g-1',
            'pk_member_uuid': 'pk-m-1',
            'is_deleted': false,
          }),
          reason: 'test-reason',
          createdAt: DateTime.now(),
        ),
      );

      final rows = await db.pkGroupEntryDeferredSyncOpsDao.getAll();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(
        row.createdAt.year,
        inInclusiveRange(before.year - 1, before.year + 1),
        reason: 'Drift should decode createdAt as seconds-since-epoch.',
      );
      expect(row.entityId, 'entry-roundtrip');
    });

    test('PkGroupEntryDeferredSyncOpsDao.markRetried stamps lastRetryAt to '
        'current wall clock and increments retryCount', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final before = DateTime.now();
      await db.pkGroupEntryDeferredSyncOpsDao.upsert(
        PkGroupEntryDeferredSyncOpsCompanion.insert(
          id: 'deferred-retry',
          entityType: 'member_group_entries',
          entityId: 'entry-retry',
          fieldsJson: jsonEncode({
            'pk_group_uuid': 'pk-g-1',
            'pk_member_uuid': 'pk-m-1',
            'is_deleted': false,
          }),
          reason: 'test-reason',
          createdAt: DateTime.now(),
          lastRetryAt: const Value(null),
        ),
      );

      await db.pkGroupEntryDeferredSyncOpsDao.markRetried('deferred-retry');
      await db.pkGroupEntryDeferredSyncOpsDao.markRetried('deferred-retry');

      final rows = await db.pkGroupEntryDeferredSyncOpsDao.getAll();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.lastRetryAt, isNotNull);
      expect(
        row.lastRetryAt!.year,
        inInclusiveRange(before.year - 1, before.year + 1),
        reason: 'lastRetryAt should decode as seconds-since-epoch.',
      );
      expect(row.retryCount, 2);
    });

    test('PkGroupSyncAliasesDao.upsertAlias round-trips createdAt within '
        'the current year', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final before = DateTime.now();
      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: 'legacy-entity',
        pkGroupUuid: 'pk-g-uuid-1',
        canonicalEntityId: 'pk-group:pk-g-uuid-1',
      );

      final row = await db.pkGroupSyncAliasesDao.getByLegacyEntityId(
        'legacy-entity',
      );
      expect(row, isNotNull);
      expect(
        row!.createdAt.year,
        inInclusiveRange(before.year - 1, before.year + 1),
        reason: 'Alias createdAt should decode as seconds-since-epoch.',
      );
      expect(row.canonicalEntityId, 'pk-group:pk-g-uuid-1');
    });

    test('_deferPkBackedMemberGroupEntryOp writes seconds-encoded createdAt '
        'via the adapter applyFields path', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final entriesEntity = adapter.entities.singleWhere(
        (entity) => entity.tableName == 'member_group_entries',
      );

      final before = DateTime.now();
      // Unresolved PK refs trigger the deferred-op write via applyFields.
      await entriesEntity.applyFields('entry-deferred', {
        'pk_group_uuid': 'missing-group',
        'pk_member_uuid': 'missing-member',
        'is_deleted': false,
      });

      final rows = await db.pkGroupEntryDeferredSyncOpsDao.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.entityId, 'entry-deferred');
      expect(
        rows.single.createdAt.year,
        inInclusiveRange(before.year - 1, before.year + 1),
        reason:
            'Adapter-written deferred op createdAt should be seconds-encoded.',
      );
    });

    test(
      '_deferPkBackedMemberGroupEntryOp preserves createdAt on repeated defer',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final entriesEntity = adapter.entities.singleWhere(
          (entity) => entity.tableName == 'member_group_entries',
        );

        await entriesEntity.applyFields('entry-redeferred', {
          'pk_group_uuid': 'missing-group',
          'pk_member_uuid': 'missing-member',
          'is_deleted': false,
        });
        final first = (await db.pkGroupEntryDeferredSyncOpsDao.getAll()).single;

        await Future<void>.delayed(const Duration(milliseconds: 5));
        await entriesEntity.applyFields('entry-redeferred', {
          'pk_group_uuid': 'missing-group',
          'pk_member_uuid': 'missing-member',
          'group_id': 'new-sender-hint',
          'member_id': 'new-sender-hint',
          'is_deleted': false,
        });

        final second =
            (await db.pkGroupEntryDeferredSyncOpsDao.getAll()).single;
        expect(second.id, first.id);
        expect(second.createdAt, first.createdAt);
        expect(second.fieldsJson, contains('new-sender-hint'));
      },
    );

    test('_recordPkGroupAliasIfNeeded writes seconds-encoded createdAt when '
        'applyFields materializes an aliased PK group row', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final groupsEntity = adapter.entities.singleWhere(
        (entity) => entity.tableName == 'member_groups',
      );

      final before = DateTime.now();
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'local-existing-id',
              name: 'Existing',
              createdAt: before,
              pluralkitUuid: const Value('pk-g-uuid-alias'),
            ),
          );
      // Apply an incoming PK group payload under a non-canonical entity id
      // so the adapter records an alias for the legacy id.
      await groupsEntity.applyFields('random-legacy-id', {
        'name': 'Imported',
        'display_order': 0,
        'group_type': 0,
        'created_at': before.toIso8601String(),
        'pluralkit_uuid': 'pk-g-uuid-alias',
        'is_deleted': false,
      });

      final aliasRow = await db.pkGroupSyncAliasesDao.getByLegacyEntityId(
        'random-legacy-id',
      );
      expect(aliasRow, isNotNull);
      expect(aliasRow!.pkGroupUuid, 'pk-g-uuid-alias');
      expect(
        aliasRow.createdAt.year,
        inInclusiveRange(before.year - 1, before.year + 1),
        reason: 'Adapter-recorded alias createdAt should be seconds-encoded.',
      );
    });
  });
}
