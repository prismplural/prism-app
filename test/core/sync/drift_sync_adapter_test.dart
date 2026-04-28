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
      unawaited(completeFuture.then((_) => batchComplete = true));

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

  // ---------------------------------------------------------------------------
  // PK bidirectional sync (plan 08) — round-trip locks for new fields.
  //
  // Risk #3 from the plan: "adding columns without wiring drift_sync_adapter
  // means new fields don't sync between devices." These tests pack a row into
  // sync fields via the adapter, apply the same field map back through
  // applyFields, read the row, and assert every PK-related column round-trips
  // both when populated and when null.
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> roundTripMember(
    database.AppDatabase db,
    database.Member input,
  ) async {
    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final members = syncAdapter.adapter.entities
        .singleWhere((e) => e.tableName == 'members');

    // Seed via Drift so toSyncFields has a row to read.
    await db
        .into(db.members)
        .insertOnConflictUpdate(input.toCompanion(false));

    final packed = members.toSyncFields(input);

    // Wipe and re-apply via the sync path.
    await (db.delete(db.members)..where((t) => t.id.equals(input.id))).go();
    await members.applyFields(input.id, Map<String, dynamic>.from(packed));

    final back = await members.readRow(input.id);
    return back!;
  }

  test(
    'members: PK fields round-trip through sync adapter when populated',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final member = database.Member(
        id: 'm-1',
        name: 'Ada',
        emoji: '✨',
        isActive: true,
        createdAt: DateTime.utc(2026, 3, 18),
        displayOrder: 1,
        isAdmin: false,
        customColorEnabled: false,
        pluralkitUuid: 'uuid-ada',
        pluralkitId: 'ada',
        displayName: 'Ada Lovelace',
        birthday: '1815-12-10',
        proxyTagsJson:
            '[{"prefix":"A:","suffix":null}]',
        pluralkitSyncIgnored: true,
        markdownEnabled: true,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final back = await roundTripMember(db, member);
      expect(back['display_name'], 'Ada Lovelace');
      expect(back['birthday'], '1815-12-10');
      expect(back['proxy_tags_json'], '[{"prefix":"A:","suffix":null}]');
      expect(back['pluralkit_sync_ignored'], isTrue);
      expect(back['pluralkit_id'], 'ada');
      expect(back['pluralkit_uuid'], 'uuid-ada');
    },
  );

  test(
    'members: PK fields round-trip as null (not missing) when not set',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final member = database.Member(
        id: 'm-2',
        name: 'Bo',
        emoji: '🌱',
        isActive: true,
        createdAt: DateTime.utc(2026, 3, 18),
        displayOrder: 0,
        isAdmin: false,
        customColorEnabled: false,
        pluralkitSyncIgnored: false,
        markdownEnabled: false,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final back = await roundTripMember(db, member);
      expect(back.containsKey('display_name'), isTrue,
          reason: 'Null must be present as an explicit key, not missing');
      expect(back['display_name'], isNull);
      expect(back.containsKey('birthday'), isTrue);
      expect(back['birthday'], isNull);
      expect(back.containsKey('proxy_tags_json'), isTrue);
      expect(back['proxy_tags_json'], isNull);
      expect(back['pluralkit_sync_ignored'], isFalse);
      expect(back['pluralkit_uuid'], isNull);
      expect(back['pluralkit_id'], isNull);
    },
  );

  // ---------------------------------------------------------------------------
  // DateTime UTC normalization (audit batch O)
  //
  // Drift reads DateTime columns as local time. Without `.toUtc()`, the wire
  // string has no offset/Z, so a peer in a different timezone parses it as
  // their own local time, shifting the absolute moment by the timezone delta.
  // The sync adapter must funnel every DateTime emission through the
  // _dateTimeToSyncString helper. These tests pin the contract.
  // ---------------------------------------------------------------------------

  test(
    'fronting_sessions: DateTime fields serialize as UTC (Z-suffixed)',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities
          .singleWhere((e) => e.tableName == 'fronting_sessions');

      // Local DateTime — no UTC marker on the input.
      final localStart = DateTime(2024, 1, 1, 12);
      final localEnd = DateTime(2024, 1, 1, 14);
      final session = database.FrontingSession(
        id: 'fs-utc-1',
        startTime: localStart,
        endTime: localEnd,
        memberId: null,
        coFronterIds: '[]',
        sessionType: domain.SessionType.sleep.index,
        quality: domain.SleepQuality.unknown.index,
        isHealthKitImport: false,
        pluralkitUuid: null,
        isDeleted: false,
      );

      final fields = fronting.toSyncFields(session);

      final startStr = fields['start_time'] as String;
      final endStr = fields['end_time'] as String;
      expect(startStr.endsWith('Z'), isTrue,
          reason: 'start_time must be UTC (Z-suffixed): got $startStr');
      expect(endStr.endsWith('Z'), isTrue,
          reason: 'end_time must be UTC (Z-suffixed): got $endStr');

      // The absolute instant must equal the input's UTC equivalent.
      expect(
        DateTime.parse(startStr).isAtSameMomentAs(localStart.toUtc()),
        isTrue,
      );
      expect(
        DateTime.parse(endStr).isAtSameMomentAs(localEnd.toUtc()),
        isTrue,
      );
    },
  );

  test(
    'members: created_at serializes as UTC (Z-suffixed)',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final members = syncAdapter.adapter.entities
          .singleWhere((e) => e.tableName == 'members');

      // Local DateTime as the input — Drift hands these to toSyncFields.
      final localCreated = DateTime(2024, 1, 1, 12);
      final member = database.Member(
        id: 'm-utc-1',
        name: 'Ada',
        emoji: '✨',
        isActive: true,
        createdAt: localCreated,
        displayOrder: 0,
        isAdmin: false,
        customColorEnabled: false,
        pluralkitSyncIgnored: false,
        markdownEnabled: false,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final fields = members.toSyncFields(member);
      final createdStr = fields['created_at'] as String;
      expect(createdStr.endsWith('Z'), isTrue,
          reason: 'created_at must be UTC (Z-suffixed): got $createdStr');
      expect(
        DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
        isTrue,
      );
    },
  );

  test(
    'fronting_sessions: nullable end_time stays null (not "null" string)',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities
          .singleWhere((e) => e.tableName == 'fronting_sessions');

      final session = database.FrontingSession(
        id: 'fs-utc-2',
        startTime: DateTime(2024, 1, 1, 12),
        endTime: null,
        memberId: null,
        coFronterIds: '[]',
        sessionType: domain.SessionType.normal.index,
        quality: domain.SleepQuality.unknown.index,
        isHealthKitImport: false,
        pluralkitUuid: null,
        isDeleted: false,
      );

      final fields = fronting.toSyncFields(session);
      expect(fields.containsKey('end_time'), isTrue);
      expect(fields['end_time'], isNull);
    },
  );
}
