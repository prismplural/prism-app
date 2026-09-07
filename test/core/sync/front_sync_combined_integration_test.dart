import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/pk_front_orphan_projection_repair.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/features/migration/services/group_chat_visibility_sync_reemit_service.dart';
import 'package:prism_plurality/features/migration/services/migration_sync_repair_service.dart';
import 'package:prism_plurality/features/migration/services/oversized_inline_image_reemit_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _insertWinner(AppDatabase db) => db
    .into(db.members)
    .insert(
      MembersCompanion.insert(
        id: 'local-winner',
        name: 'Actual fronter',
        createdAt: DateTime.utc(2026, 9, 7),
        pluralkitUuid: const Value('member-stable-uuid'),
        pluralkitId: const Value('abcde'),
      ),
    );

Future<void> _recordAlias(AppDatabase db) =>
    db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'remote-member-id',
      pkUuid: 'member-stable-uuid',
      pkId: 'abcde',
      targetRowId: 'local-winner',
    );

Future<int> _deliver(
  AppDatabase db,
  SyncAdapterWithCompletion wrapped,
  List<ConsumerDelivery> deliveries,
) => applyConsumerDeliveriesHealingUnappliable(
  db,
  wrapped.adapter,
  SyncQuarantineService(db.syncQuarantineDao),
  deliveries,
);

const _requiredFrontFields = <String, dynamic>{
  'start_time': '2026-09-07T12:00:00.000Z',
  'session_type': 0,
  'is_deleted': false,
};

Future<List<Map<String, dynamic>>> _drainRepairs(AppDatabase db) async {
  final repairs = <Map<String, dynamic>>[];
  await MigrationSyncRepairService(
    db: db,
    recordReconcile:
        ({required table, required entityId, required fields}) async {
          repairs.add({'table': table, 'entity': entityId, 'fields': fields});
        },
  ).drain();
  return repairs;
}

void main() {
  test('alias-first split delivery materializes the validated local member and '
      'raw rehydration cannot undo it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await _insertWinner(db);
    await _recordAlias(db);
    final wrapped = buildSyncAdapterWithCompletion(db);

    expect(
      await _deliver(db, wrapped, const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'front',
          isDelete: false,
          fields: {'member_id': 'remote-member-id', 'notes': 'deferred'},
        ),
      ]),
      1,
      reason: 'durably deferred input is safe to acknowledge',
    );
    expect(await db.select(db.frontingSessions).get(), isEmpty);

    expect(
      await _deliver(db, wrapped, const [
        ConsumerDelivery(
          id: 2,
          table: 'fronting_sessions',
          entityId: 'front',
          isDelete: false,
          fields: _requiredFrontFields,
        ),
      ]),
      1,
    );
    var front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'local-winner');
    expect(front.notes, 'deferred');

    await _deliver(db, wrapped, const [
      ConsumerDelivery(
        id: 3,
        table: 'fronting_sessions',
        entityId: 'front',
        isDelete: false,
        fields: {
          ..._requiredFrontFields,
          'member_id': 'remote-member-id',
          'notes': 'hydrated-again',
        },
      ),
    ]);
    front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'local-winner');
    expect(front.notes, 'hydrated-again');
    expect(await _drainRepairs(db), isEmpty);
  });

  test(
    'front-first delivery is repaired when validated alias evidence arrives',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await _insertWinner(db);
      final wrapped = buildSyncAdapterWithCompletion(db);

      await _deliver(db, wrapped, const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'front',
          isDelete: false,
          fields: {..._requiredFrontFields, 'member_id': 'remote-member-id'},
        ),
      ]);
      expect(
        (await db.select(db.frontingSessions).get()).single.memberId,
        'remote-member-id',
      );

      await _recordAlias(db);
      final repaired = await PkFrontOrphanProjectionRepair(db).run();
      expect(repaired.repaired, 1);
      expect(
        (await db.select(db.frontingSessions).get()).single.memberId,
        'local-winner',
      );
      expect(await _drainRepairs(db), isEmpty);
    },
  );

  test(
    'retained engine identity repairs history and survives later raw hydration',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await _insertWinner(db);
      final wrapped = buildSyncAdapterWithCompletion(db);
      await _deliver(db, wrapped, const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'front',
          isDelete: false,
          fields: {..._requiredFrontFields, 'member_id': 'remote-member-id'},
        ),
      ]);

      final result = await PkFrontOrphanProjectionRepair(db).run(
        readWinningField:
            ({required table, required entityId, required field}) async =>
                switch (field) {
                  'is_deleted' => 'false',
                  'pluralkit_uuid' => '"member-stable-uuid"',
                  _ => null,
                },
      );
      expect(result.repaired, 1);
      final retainedAlias = await db.pkIdentitySyncAliasesDao
          .getByLegacyEntityId('members', 'remote-member-id');
      expect(retainedAlias?.pkUuid, 'member-stable-uuid');
      expect(retainedAlias?.targetRowId, 'local-winner');

      await _deliver(db, wrapped, const [
        ConsumerDelivery(
          id: 2,
          table: 'fronting_sessions',
          entityId: 'front',
          isDelete: false,
          fields: {
            ..._requiredFrontFields,
            'member_id': 'remote-member-id',
            'notes': 'hydrated-again',
          },
        ),
      ]);
      expect(
        (await db.select(db.frontingSessions).get()).single.memberId,
        'local-winner',
      );
      expect(await _drainRepairs(db), isEmpty);
    },
  );

  test('tombstoned or missing engine evidence preserves raw history without '
      'Unknown reconciliation', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    await _insertWinner(db);
    final wrapped = buildSyncAdapterWithCompletion(db);
    for (final entry in const [
      ('tombstoned', 'gone'),
      ('missing', 'unknown'),
    ]) {
      await _deliver(db, wrapped, [
        ConsumerDelivery(
          id: entry.$1 == 'tombstoned' ? 1 : 2,
          table: 'fronting_sessions',
          entityId: entry.$1,
          isDelete: false,
          fields: {..._requiredFrontFields, 'member_id': entry.$2},
        ),
      ]);
    }

    final result = await PkFrontOrphanProjectionRepair(db).run(
      readWinningField:
          ({required table, required entityId, required field}) async {
            if (entityId == 'gone' && field == 'is_deleted') return 'true';
            return null;
          },
    );
    expect(result.repaired, 0);
    expect(result.engineTombstoned, 1);
    expect(result.noEvidence, 1);
    expect(
      (await db.select(db.frontingSessions).get()).map((row) => row.memberId),
      containsAll(<String>{'gone', 'unknown'}),
    );
    expect(await _drainRepairs(db), isEmpty);
  });

  test(
    'healthy catch-up hydrates before its bounded orphan recovery',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final calls = <String>[];

      await runPostHealthySyncCatchUp(
        handle: const _FakePrismSyncHandle(),
        db: db,
        failureLabel: 'combined integration catch-up failed',
        onResume: (_) async => calls.add('hydrate'),
        repairPkFrontOrphans: (_, _) async {
          calls.add('repair');
          return const PkFrontOrphanProjectionRepairResult();
        },
        reemitGroupChatVisibility: (_, _) async {
          calls.add('visibility');
          return const GroupChatVisibilitySyncReemitResult();
        },
        reemitOversizedInlineImages: (_, _) async =>
            const OversizedInlineImageReemitResult(),
        repairQuarantinedPushBatches: (_) async {},
        drainMigrationSyncRepairs: (_, _) async =>
            const MigrationSyncRepairResult(),
        catchUpPk: (_, _) async => const PkGroupSyncV2CatchupResult(),
        drain: (_) async {},
      );

      expect(calls, ['hydrate', 'repair', 'visibility']);
    },
  );
}
