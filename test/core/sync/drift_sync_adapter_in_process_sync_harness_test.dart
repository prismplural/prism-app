import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

void main() {
  late bool previousMultipleDbWarningSetting;

  setUpAll(() {
    previousMultipleDbWarningSetting =
        drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    // This harness intentionally keeps isolated source and target in-memory
    // databases open at once to mimic two synced peers.
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDbWarningSetting;
  });

  test('in-process sync harness replays a PK member-group entry when its '
      'missing member arrives later', () async {
    final sourceDb = AppDatabase(NativeDatabase.memory());
    final targetDb = AppDatabase(NativeDatabase.memory());
    addTearDown(sourceDb.close);
    addTearDown(targetDb.close);

    final sourceAdapter = buildSyncAdapterWithCompletion(sourceDb).adapter;
    final targetQuarantine = SyncQuarantineService(targetDb.syncQuarantineDao);
    final targetAdapter = buildSyncAdapterWithCompletion(
      targetDb,
      quarantine: targetQuarantine,
    );
    final now = DateTime.utc(2026, 5, 22, 12);

    await sourceDb
        .into(sourceDb.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'source-local-group',
            name: 'Core',
            createdAt: now,
            pluralkitUuid: const drift.Value('pk-group-1'),
          ),
        );
    await sourceDb
        .into(sourceDb.members)
        .insert(
          MembersCompanion.insert(
            id: 'source-member-1',
            name: 'Alice',
            createdAt: now,
            pluralkitUuid: const drift.Value('pk-member-1'),
          ),
        );
    await sourceDb
        .into(sourceDb.memberGroupEntries)
        .insert(
          MemberGroupEntriesCompanion.insert(
            id: 'source-local-entry',
            groupId: 'source-local-group',
            memberId: 'source-member-1',
            pkGroupUuid: const drift.Value('pk-group-1'),
            pkMemberUuid: const drift.Value('pk-member-1'),
          ),
        );

    final sourceGroup = await (sourceDb.select(
      sourceDb.memberGroups,
    )..where((t) => t.id.equals('source-local-group'))).getSingle();
    final sourceMember = await (sourceDb.select(
      sourceDb.members,
    )..where((t) => t.id.equals('source-member-1'))).getSingle();
    final sourceEntry = await (sourceDb.select(
      sourceDb.memberGroupEntries,
    )..where((t) => t.id.equals('source-local-entry'))).getSingle();

    final groupChange = _changeFromRow(
      sourceAdapter,
      tableName: 'member_groups',
      row: sourceGroup,
    );
    final entryChange = _changeFromRow(
      sourceAdapter,
      tableName: 'member_group_entries',
      row: sourceEntry,
    );
    final memberChange = _changeFromRow(
      sourceAdapter,
      tableName: 'members',
      row: sourceMember,
    );
    final entryId = entryChange['entity_id'] as String;
    final entryFields = entryChange['fields'] as Map<String, dynamic>;

    expect(groupChange['entity_id'], 'pk-group:pk-group-1');
    expect(entryId, isNot('source-local-entry'));
    expect(entryFields['group_id'], 'source-local-group');
    expect(entryFields['pk_group_uuid'], 'pk-group-1');
    expect(entryFields['pk_member_uuid'], 'pk-member-1');

    await _deliverRemoteChanges(targetDb, targetAdapter, [groupChange]);
    await _deliverRemoteChanges(targetDb, targetAdapter, [entryChange]);

    expect(
      await (targetDb.select(
        targetDb.memberGroupEntries,
      )..where((t) => t.id.equals(entryId))).getSingleOrNull(),
      isNull,
      reason: 'the entry must wait until pk-member-1 resolves locally',
    );
    final deferred = await targetDb.pkGroupEntryDeferredSyncOpsDao.getById(
      'member_group_entries:$entryId',
    );
    expect(deferred, isNotNull);
    expect(deferred!.reason, contains('member:pk-member-1'));
    expect(deferred.retryCount, 1);
    expect(await targetDb.syncQuarantineDao.getAll(), isEmpty);

    await _deliverRemoteChanges(targetDb, targetAdapter, [memberChange]);

    final appliedEntry = await (targetDb.select(
      targetDb.memberGroupEntries,
    )..where((t) => t.id.equals(entryId))).getSingle();
    expect(appliedEntry.groupId, 'pk-group:pk-group-1');
    expect(appliedEntry.memberId, 'source-member-1');
    expect(appliedEntry.pkGroupUuid, 'pk-group-1');
    expect(appliedEntry.pkMemberUuid, 'pk-member-1');
    expect(
      await targetDb.pkGroupEntryDeferredSyncOpsDao.getById(
        'member_group_entries:$entryId',
      ),
      isNull,
    );
    expect(await targetDb.syncQuarantineDao.getAll(), isEmpty);

    final targetEntryEntity = targetAdapter.adapter.entityForTable(
      'member_group_entries',
    )!;
    final targetEntryFields = targetEntryEntity.toSyncFields(appliedEntry);
    expect(targetEntryFields['pk_group_uuid'], entryFields['pk_group_uuid']);
    expect(targetEntryFields['pk_member_uuid'], entryFields['pk_member_uuid']);
  });
}

Map<String, dynamic> _changeFromRow(
  DriftSyncAdapter adapter, {
  required String tableName,
  required dynamic row,
}) {
  final entity = adapter.entityForTable(tableName)!;
  return {
    'table': entity.tableName,
    'entity_id': entity.entityIdFor(row),
    'is_delete': false,
    'fields': entity.toSyncFields(row),
  };
}

Future<ApplyResult> _deliverRemoteChanges(
  AppDatabase db,
  SyncAdapterWithCompletion adapter,
  List<Map<String, dynamic>> changes,
) async {
  adapter.beginSyncBatch();
  final result = await applyRemoteChanges(
    db,
    adapter.adapter,
    SyncEvent.fromJson({'type': 'RemoteChanges', 'changes': changes}),
  );
  await adapter.completeSyncBatch();
  return result;
}
