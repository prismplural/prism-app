// Models mixed-version field delivery ordering, not a specific device incident.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

final _now = DateTime.utc(2026, 9, 16, 12);
final _ancientStart = _now.subtract(const Duration(days: 467));

Map<String, dynamic> _memberFields(String name) => <String, dynamic>{
  'name': name,
  'created_at': _now.toIso8601String(),
  'is_active': true,
  'is_deleted': false,
};

Map<String, dynamic> _frontCreateFields({
  required String memberId,
  required DateTime startTime,
}) => <String, dynamic>{
  'member_id': memberId,
  'start_time': startTime.toIso8601String(),
  'session_type': 0,
  'is_health_kit_import': false,
  'is_deleted': false,
};

Future<int> _deliver(
  AppDatabase db,
  SyncAdapterWithCompletion adapter,
  SyncQuarantineService quarantine,
  List<ConsumerDelivery> deliveries,
) async {
  adapter.beginSyncBatch();
  try {
    return await applyConsumerDeliveriesHealingUnappliable(
      db,
      adapter.adapter,
      quarantine,
      deliveries,
    );
  } finally {
    await adapter.completeSyncBatch();
  }
}

void main() {
  test('467-day historical endings survive reversed partial catch-up and a '
      'late base replay cannot reopen them', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);

    expect(
      await _deliver(db, adapter, quarantine, [
        ConsumerDelivery(
          id: 1,
          table: 'members',
          entityId: 'current-member',
          isDelete: false,
          fields: _memberFields('Current'),
        ),
        ConsumerDelivery(
          id: 2,
          table: 'members',
          entityId: 'historical-member',
          isDelete: false,
          fields: _memberFields('Historical'),
        ),
        ConsumerDelivery(
          id: 3,
          table: 'fronting_sessions',
          entityId: 'current-front',
          isDelete: false,
          fields: _frontCreateFields(
            memberId: 'current-member',
            startTime: _now,
          ),
        ),
      ]),
      3,
    );

    // End-before-create must retain its historical timestamp.
    expect(
      await _deliver(db, adapter, quarantine, [
        ConsumerDelivery(
          id: 4,
          table: 'fronting_sessions',
          entityId: 'old-front',
          isDelete: false,
          fields: {
            'end_time': _ancientStart
                .add(const Duration(hours: 2))
                .toIso8601String(),
          },
        ),
      ]),
      1,
    );
    expect(await db.select(db.frontingSessions).get(), hasLength(1));
    expect(
      await quarantine.getDeferredConsumerDelivery(
        'fronting_sessions',
        'old-front',
      ),
      isNotNull,
    );

    expect(
      await _deliver(db, adapter, quarantine, [
        ConsumerDelivery(
          id: 5,
          table: 'fronting_sessions',
          entityId: 'old-front',
          isDelete: false,
          fields: _frontCreateFields(
            memberId: 'historical-member',
            startTime: _ancientStart,
          ),
        ),
      ]),
      1,
    );

    var oldFront = await (db.select(
      db.frontingSessions,
    )..where((row) => row.id.equals('old-front'))).getSingle();
    expect(oldFront.startTime.toUtc(), _ancientStart);
    expect(
      oldFront.endTime?.toUtc(),
      _ancientStart.add(const Duration(hours: 2)),
    );
    expect(
      (await db.frontingSessionsDao.getActiveSessions()).map((row) => row.id),
      ['current-front'],
    );
    expect(
      await quarantine.getDeferredConsumerDelivery(
        'fronting_sessions',
        'old-front',
      ),
      isNull,
    );

    // An absent end_time must preserve the existing end.
    expect(
      await _deliver(db, adapter, quarantine, [
        ConsumerDelivery(
          id: 6,
          table: 'fronting_sessions',
          entityId: 'old-front',
          isDelete: false,
          fields: _frontCreateFields(
            memberId: 'historical-member',
            startTime: _ancientStart,
          ),
        ),
      ]),
      1,
    );
    oldFront = await (db.select(
      db.frontingSessions,
    )..where((row) => row.id.equals('old-front'))).getSingle();
    expect(oldFront.endTime, isNotNull);
    expect(
      (await db.frontingSessionsDao.getActiveSessions()).map((row) => row.id),
      ['current-front'],
    );
    expect(await db.syncOutboxDao.count(), 0);
  });

  test('legacy raw consumer delivery can acknowledge an end-before-create and '
      'then materialize the historical front as active', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = buildSyncAdapterWithCompletion(db);

    // The 0.14 drain acknowledged unknown sparse patches without hydration.
    adapter.beginSyncBatch();
    try {
      expect(
        await applyConsumerDeliveries(db, adapter.adapter, [
          ConsumerDelivery(
            id: 1,
            table: 'fronting_sessions',
            entityId: 'legacy-front',
            isDelete: false,
            fields: {
              'end_time': _ancientStart
                  .add(const Duration(hours: 2))
                  .toIso8601String(),
            },
          ),
        ]),
        1,
        reason: 'the legacy caller considered the skipped sparse patch done',
      );
      expect(
        await applyConsumerDeliveries(db, adapter.adapter, [
          ConsumerDelivery(
            id: 2,
            table: 'fronting_sessions',
            entityId: 'legacy-front',
            isDelete: false,
            fields: _frontCreateFields(
              memberId: 'historical-member',
              startTime: _ancientStart,
            ),
          ),
        ]),
        1,
      );
    } finally {
      await adapter.completeSyncBatch();
    }

    final oldFront = await (db.select(
      db.frontingSessions,
    )..where((row) => row.id.equals('legacy-front'))).getSingle();
    expect(oldFront.endTime, isNull);
    expect(
      (await db.frontingSessionsDao.getActiveSessions()).map((row) => row.id),
      ['legacy-front'],
      reason: 'this is the old receiver symptom, not current intended behavior',
    );
  });

  test(
    'a winning historical end=null remains active until a real end or delete '
    'arrives, then a tombstone blocks late replay',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db);
      final quarantine = SyncQuarantineService(db.syncQuarantineDao);

      await _deliver(db, adapter, quarantine, [
        ConsumerDelivery(
          id: 1,
          table: 'members',
          entityId: 'historical-member',
          isDelete: false,
          fields: _memberFields('Historical'),
        ),
        ConsumerDelivery(
          id: 2,
          table: 'fronting_sessions',
          entityId: 'still-open',
          isDelete: false,
          fields: _frontCreateFields(
            memberId: 'historical-member',
            startTime: _ancientStart,
          ),
        ),
      ]);

      // Age is not a validity test: Prism supports intentionally long fronts.
      // Transport/lifecycle repairs cannot safely invent a missing end_time.
      expect(
        (await db.frontingSessionsDao.getActiveSessions()).map((row) => row.id),
        ['still-open'],
      );

      expect(
        await _deliver(db, adapter, quarantine, const [
          ConsumerDelivery(
            id: 3,
            table: 'fronting_sessions',
            entityId: 'still-open',
            isDelete: true,
            fields: <String, dynamic>{},
          ),
          ConsumerDelivery(
            id: 4,
            table: 'fronting_sessions',
            entityId: 'still-open',
            isDelete: false,
            fields: <String, dynamic>{
              'member_id': 'historical-member',
              'start_time': '2025-06-06T12:00:00.000Z',
              'session_type': 0,
              'is_health_kit_import': false,
              'is_deleted': false,
            },
          ),
        ]),
        2,
      );
      expect(
        await (db.select(
          db.frontingSessions,
        )..where((row) => row.id.equals('still-open'))).getSingleOrNull(),
        isNull,
      );
      expect(await db.frontingSessionsDao.getActiveSessions(), isEmpty);
    },
  );
}
