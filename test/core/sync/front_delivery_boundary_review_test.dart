import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

void main() {
  test('replay retains an incomplete front until its member arrives', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final adapter = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    await applyConsumerDeliveriesHealingUnappliable(
      db,
      adapter.adapter,
      quarantine,
      const [
        ConsumerDelivery(
          id: 1,
          table: 'fronting_sessions',
          entityId: 'start-first-front',
          isDelete: false,
          fields: {'start_time': '2026-09-07T12:00:00.000Z'},
        ),
      ],
    );
    expect(
      await repairConsumerDeliverySpillQuarantineRows(
        db,
        adapter,
        db.syncQuarantineDao,
      ),
      0,
    );
    expect(await db.select(db.frontingSessions).get(), isEmpty);
    expect(
      await db
          .customSelect(
            "SELECT entity_id FROM sync_migration_repairs WHERE table_name = 'fronting_sessions'",
          )
          .get(),
      isEmpty,
    );
    expect(
      await quarantine.getDeferredConsumerDelivery(
        'fronting_sessions',
        'start-first-front',
      ),
      containsPair('start_time', '2026-09-07T12:00:00.000Z'),
    );

    await adapter.adapter.applyFields('members', 'real-member', {
      'name': 'Real member',
      'created_at': '2026-09-07T10:00:00.000Z',
    });
    await quarantine.deferConsumerDelivery(
      entityType: 'fronting_sessions',
      entityId: 'start-first-front',
      fields: {'session_type': 0, 'member_id': 'real-member'},
    );
    expect(
      await repairConsumerDeliverySpillQuarantineRows(
        db,
        adapter,
        db.syncQuarantineDao,
      ),
      1,
    );
    final front = (await db.select(db.frontingSessions).get()).single;
    expect(front.memberId, 'real-member');
    expect(front.startTime.toUtc(), DateTime.utc(2026, 9, 7, 12));
    expect(
      await quarantine.getDeferredConsumerDelivery(
        'fronting_sessions',
        'start-first-front',
      ),
      isNull,
    );
  });

  for (final explicitDelete in [true, false]) {
    test(
      'replay retains tombstone after ${explicitDelete ? 'delete' : 'field delete'} and ignores delayed create',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();
        final adapter = buildSyncAdapterWithCompletion(db);
        final quarantine = SyncQuarantineService(db.syncQuarantineDao);
        await quarantineConsumerDeliverySpill(quarantine, [
          ConsumerDelivery(
            id: 1,
            table: 'fronting_sessions',
            entityId: 'deleted-front',
            isDelete: explicitDelete,
            fields: explicitDelete ? {} : {'is_deleted': true},
          ),
        ]);
        await repairConsumerDeliverySpillQuarantineRows(
          db,
          adapter,
          db.syncQuarantineDao,
        );
        expect(
          await quarantine.hasConsumerDeliveryTombstone(
            'fronting_sessions',
            'deleted-front',
          ),
          isTrue,
        );
        await quarantine.deferConsumerDelivery(
          entityType: 'fronting_sessions',
          entityId: 'deleted-front',
          fields: {'start_time': '2026-09-07T12:00:00.000Z', 'session_type': 1},
        );
        expect(
          await repairConsumerDeliverySpillQuarantineRows(
            db,
            adapter,
            db.syncQuarantineDao,
          ),
          1,
        );
        final fronts = await db.select(db.frontingSessions).get();
        expect(fronts.where((front) => !front.isDeleted), isEmpty);
        expect(
          await quarantine.getDeferredConsumerDelivery(
            'fronting_sessions',
            'deleted-front',
          ),
          isNull,
        );
      },
    );
  }
}
