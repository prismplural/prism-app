import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

void main() {
  test('review: start-time fragment must not invent Unknown before member arrives', () async {
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
    final fronts = await db.select(db.frontingSessions).get();
    final repairs = await db.customSelect(
      "SELECT entity_id, reason FROM sync_migration_repairs WHERE table_name = 'fronting_sessions'",
    ).get();
    // ignore: avoid_print
    print('REVIEW start-first fronts=${fronts.map((f) => f.memberId).toList()} '
        'queuedRepairs=${repairs.map((r) => r.data).toList()}');
    expect(fronts, isEmpty, reason: 'The member field can arrive in a later pull batch');
    expect(repairs, isEmpty, reason: 'An incomplete projection must not invent a sync repair');
  });
}
