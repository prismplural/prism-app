import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

class _DelayedQuarantineService extends SyncQuarantineService {
  _DelayedQuarantineService(super.dao, this.gate);

  final Completer<void> gate;

  @override
  Future<void> quarantineField({
    required String entityType,
    required String entityId,
    String? fieldName,
    required String expectedType,
    required String receivedType,
    String? receivedValue,
    String? sourceDevice,
    String? errorMessage,
  }) async {
    await gate.future;
    await super.quarantineField(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      expectedType: expectedType,
      receivedType: receivedType,
      receivedValue: receivedValue,
      sourceDevice: sourceDevice,
      errorMessage: errorMessage,
    );
  }
}

void main() {
  test(
    'quarantined field writes are tracked before sync batch completion',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final gate = Completer<void>();
      final quarantine = _DelayedQuarantineService(db.syncQuarantineDao, gate);
      final syncAdapter = buildSyncAdapterWithCompletion(
        db,
        quarantine: quarantine,
      );

      final members = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'members',
      );

      syncAdapter.beginSyncBatch();

      final applyFuture = members.applyFields('member-1', {
        'name': 'Ada',
        'emoji': '✨',
        'is_active': true,
        'created_at': DateTime.utc(2026, 3, 18).toIso8601String(),
        'display_order': 1,
        'is_admin': false,
        'custom_color_enabled': false,
        'bio': 123,
        'is_deleted': false,
      });

      await applyFuture;
      expect(await db.syncQuarantineDao.count(), 0);

      var batchComplete = false;
      final completeFuture = syncAdapter.completeSyncBatch();
      completeFuture.then((_) => batchComplete = true);

      await Future<void>.delayed(Duration.zero);
      expect(batchComplete, isFalse);

      gate.complete();
      await completeFuture;

      expect(batchComplete, isTrue);
      expect(await db.syncQuarantineDao.count(), 1);
    },
  );

  test(
    'fronting_sessions sync entity carries sleep fields and sleep_sessions is removed',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final entityNames = syncAdapter.adapter.entities
          .map((entity) => entity.tableName)
          .toSet();

      expect(entityNames, contains('fronting_sessions'));
      expect(entityNames, isNot(contains('sleep_sessions')));

      final frontingEntity = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'fronting_sessions',
      );
      final session = database.FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 18, 10),
        endTime: DateTime(2026, 3, 18, 12),
        memberId: null,
        coFronterIds: '[]',
        sessionType: domain.SessionType.sleep.index,
        quality: domain.SleepQuality.unknown.index,
        isHealthKitImport: true,
        pluralkitUuid: null,
        isDeleted: false,
      );

      final fields = frontingEntity.toSyncFields(session);
      expect(fields['session_type'], 1);
      expect(fields['quality'], 0);
      expect(fields['is_health_kit_import'], isTrue);
    },
  );
}
