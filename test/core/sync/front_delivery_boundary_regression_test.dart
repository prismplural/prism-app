import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/features/migration/services/migration_sync_repair_service.dart';

void main() {
  test('split front create survives ack, restart, and later fields', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final wrapped = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    await wrapped.adapter.applyFields('members', 'real-member', {
      'name': 'Actual fronter',
      'created_at': '2026-09-07T10:00:00.000Z',
    });

    Future<void> drain(List<DrainChunk> chunks) async {
      wrapped.beginSyncBatch();
      await runRemoteDeliveryDrain(
        take: (_) async => chunks.isEmpty
            ? const DrainChunk(
                deliveries: [],
                maxId: 0,
                spillUpToId: 0,
                overCap: false,
              )
            : chunks.first,
        ack: (_) async => chunks.removeAt(0),
        applyChanges: (deliveries) => applyConsumerDeliveriesHealingUnappliable(
          db,
          wrapped.adapter,
          quarantine,
          deliveries,
        ),
        quarantineSpill: (rows) =>
            quarantineConsumerDeliverySpill(quarantine, rows),
      );
      await wrapped.completeSyncBatch();
    }

    await drain([
      const DrainChunk(
        deliveries: [
          ConsumerDelivery(
            id: 200,
            table: 'fronting_sessions',
            entityId: 'front-1',
            isDelete: false,
            fields: {
              'member_id': 'real-member',
              'notes': 'kept across restart',
            },
          ),
        ],
        maxId: 200,
        spillUpToId: 0,
        overCap: false,
      ),
    ]);
    expect(await db.select(db.frontingSessions).get(), isEmpty);
    expect(
      await db.syncQuarantineDao.getDeferredConsumerDeliveries(
        'fronting_sessions',
        'front-1',
      ),
      isNotEmpty,
    );

    // Deferred state must survive adapter replacement.
    final afterRestart = buildSyncAdapterWithCompletion(db);
    afterRestart.beginSyncBatch();
    final accepted = await applyConsumerDeliveriesHealingUnappliable(
      db,
      afterRestart.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 201,
          table: 'fronting_sessions',
          entityId: 'front-1',
          isDelete: false,
          fields: {
            'start_time': '2026-09-07T12:00:00.000Z',
            'session_type': 0,
            'is_deleted': false,
          },
        ),
      ],
    );
    await afterRestart.completeSyncBatch();

    expect(accepted, 1);
    final front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'real-member');
    expect(front.notes, 'kept across restart');
    expect(
      await db.syncQuarantineDao.getDeferredConsumerDeliveries(
        'fronting_sessions',
        'front-1',
      ),
      isEmpty,
    );
    final repairs = <Map<String, dynamic>>[];
    await MigrationSyncRepairService(
      db: db,
      recordReconcile:
          ({required table, required entityId, required fields}) async {
            repairs.add({'table': table, 'entity': entityId, 'fields': fields});
          },
    ).drain();
    expect(
      repairs.where((repair) => repair['table'] == 'fronting_sessions'),
      isEmpty,
      reason: 'an incomplete projection must not enqueue an Unknown repair',
    );
  });

  test('delete absorbs a deferred sparse create', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final wrapped = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);

    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'burned-front',
          isDelete: false,
          fields: {'member_id': 'member-a'},
        ),
      ],
    );
    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 2,
          table: 'fronting_sessions',
          entityId: 'burned-front',
          isDelete: true,
          fields: {},
        ),
      ],
    );

    expect(await db.select(db.frontingSessions).get(), isEmpty);
    expect(
      await db.syncQuarantineDao.getDeferredConsumerDeliveries(
        'fronting_sessions',
        'burned-front',
      ),
      isEmpty,
    );

    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 3,
          table: 'fronting_sessions',
          entityId: 'burned-front',
          isDelete: false,
          fields: {
            'start_time': '2026-09-07T12:00:00.000Z',
            'session_type': 0,
            'member_id': 'member-a',
          },
        ),
      ],
    );
    expect(
      await db.select(db.frontingSessions).get(),
      isEmpty,
      reason: 'a delayed complete fragment must not revive a deleted id',
    );
  });

  test('complete sleep create permits an intentional null member', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final wrapped = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);

    final accepted = await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'sleep-front',
          isDelete: false,
          fields: {
            'start_time': '2026-09-07T12:00:00.000Z',
            'session_type': 1,
            'member_id': null,
          },
        ),
      ],
    );

    expect(accepted, 1);
    final sleep = (await db.select(db.frontingSessions).get()).single;
    expect(sleep.sessionType, 1);
    expect(sleep.memberId, isNull);
  });

  test('later hydrated fields override stale deferred values', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final wrapped = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'newer-front',
          isDelete: false,
          fields: {'member_id': 'stale-member', 'notes': 'stale'},
        ),
      ],
    );
    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 2,
          table: 'fronting_sessions',
          entityId: 'newer-front',
          isDelete: false,
          fields: {
            'start_time': '2026-09-07T12:00:00.000Z',
            'session_type': 0,
            'member_id': 'current-member',
            'notes': 'current',
          },
        ),
      ],
    );

    final front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'current-member');
    expect(front.notes, 'current');
  });

  test(
    'concurrent deferred replay cannot overwrite a later delivery',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final wrapped = buildSyncAdapterWithCompletion(db);
      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      for (final id in ['stale-member', 'current-member']) {
        await wrapped.adapter.applyFields('members', id, {
          'name': id,
          'created_at': '2026-09-07T10:00:00.000Z',
        });
      }
      await quarantine.deferConsumerDelivery(
        entityType: 'fronting_sessions',
        entityId: 'racing-front',
        fields: const {
          'start_time': '2026-09-07T12:00:00.000Z',
          'session_type': 0,
          'member_id': 'stale-member',
          'notes': 'stale',
        },
        overCap: true,
      );

      final currentApply = applyConsumerDeliveriesHealingUnappliable(
        db,
        wrapped.adapter,
        quarantine,
        const [
          ConsumerDelivery(
            id: 2,
            table: 'fronting_sessions',
            entityId: 'racing-front',
            isDelete: false,
            fields: {
              'start_time': '2026-09-07T12:00:00.000Z',
              'session_type': 0,
              'member_id': 'current-member',
              'notes': 'current',
            },
          ),
        ],
      );
      final replay = repairConsumerDeliverySpillQuarantineRows(
        db,
        wrapped,
        db.syncQuarantineDao,
      );
      await Future.wait([currentApply, replay]);

      final front = (await db.select(db.frontingSessions).get()).single;
      expect(front.memberId, 'current-member');
      expect(front.notes, 'current');
      expect(
        await db.syncQuarantineDao.getDeferredConsumerDeliveries(
          'fronting_sessions',
          'racing-front',
        ),
        isEmpty,
      );
    },
  );

  test(
    'strict pairing refuses an incomplete front without deferring it',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final wrapped = buildSyncAdapterWithCompletion(db);
      final quarantine = SyncQuarantineService(db.syncQuarantineDao);

      await expectLater(
        applyConsumerDeliveriesHealingUnappliable(
          db,
          wrapped.adapter,
          quarantine,
          const [
            ConsumerDelivery(
              id: 1,
              table: 'fronting_sessions',
              entityId: 'strict-front',
              isDelete: false,
              fields: {'start_time': '2026-09-07T12:00:00.000Z'},
            ),
          ],
          strict: true,
        ),
        throwsA(isA<StrictApplyFailure>()),
      );
      expect(await db.select(db.frontingSessions).get(), isEmpty);
      expect(
        await db.syncQuarantineDao.getDeferredConsumerDeliveries(
          'fronting_sessions',
          'strict-front',
        ),
        isEmpty,
      );
    },
  );

  test('deferred fields survive an actual database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prism-front-defer-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/app.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    var wrapped = buildSyncAdapterWithCompletion(db);
    var quarantine = SyncQuarantineService(db.syncQuarantineDao);
    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'reopened-front',
          isDelete: false,
          fields: {'notes': 'durable', 'member_id': 'member-a'},
        ),
      ],
    );
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    wrapped = buildSyncAdapterWithCompletion(db);
    quarantine = SyncQuarantineService(db.syncQuarantineDao);
    await applyConsumerDeliveriesHealingUnappliable(
      db,
      wrapped.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 2,
          table: 'fronting_sessions',
          entityId: 'reopened-front',
          isDelete: false,
          fields: {'start_time': '2026-09-07T12:00:00.000Z', 'session_type': 0},
        ),
      ],
    );
    final front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'member-a');
    expect(front.notes, 'durable');
    await db.close();
  });
}
