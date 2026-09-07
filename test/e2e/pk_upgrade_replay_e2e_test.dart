import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';
import 'pk_upgrade_replay_fixture.dart';

const _remoteMember = 'remote-member';
const _localMember = 'local-winner';
const _memberUuid = 'stable-member-uuid';

Map<String, dynamic> _memberFields() => {
  'name': 'Remote member',
  'created_at': '2026-01-01T00:00:00.000Z',
  'pluralkit_uuid': _memberUuid,
  'is_deleted': false,
};

Map<String, dynamic> _frontFields(String notes) => {
  'start_time': '2026-09-07T12:00:00.000Z',
  'end_time': null,
  'member_id': _remoteMember,
  'notes': notes,
  'confidence': null,
  'session_type': 0,
  'quality': null,
  'is_health_kit_import': false,
  'pluralkit_uuid': null,
  'pk_import_source': null,
  'pk_file_switch_id': null,
  'pk_member_ids_json': null,
  'delete_push_started_at': null,
  'is_deleted': false,
};

Future<int> _drainAll(
  E2EDevice device,
  AppDatabase db,
  SyncAdapterWithCompletion wrapped,
  SyncQuarantineService quarantine,
) async {
  var applied = 0;
  while (true) {
    final chunk = DrainChunk.fromJson(
      jsonDecode(
            await ffi.takeUndeliveredChanges(handle: device.handle, limit: 1),
          )
          as Map<String, dynamic>,
    );
    if (chunk.isEmpty) return applied;
    wrapped.beginSyncBatch();
    try {
      applied += await applyConsumerDeliveriesHealingUnappliable(
        db,
        wrapped.adapter,
        quarantine,
        chunk.deliveries,
      );
    } finally {
      await wrapped.completeSyncBatch();
    }
    await ffi.ackConsumerDeliveries(handle: device.handle, upToId: chunk.maxId);
  }
}

void main() {
  setUpAll(() async {
    if (e2eSkip() == null) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(resolveFfiLib()),
      );
    }
  });
  tearDownAll(() {
    if (e2eSkip() == null) RustLib.dispose();
  });

  for (final restartMode in PkRestartUnlockMode.values) {
    test(
      'schema39 recovery survives page replay and real app plus engine restart '
      '(${restartMode.name})',
      skip: e2eSkip(),
      timeout: const Timeout(Duration(minutes: 5)),
      () async {
        SharedPreferences.setMockInitialValues({});
        final directory = await Directory.systemTemp.createTemp(
          'prism-pk-upgrade-replay-',
        );
        final relay = await spawnRelay(
          dbPath: '${directory.path}/relay.sqlite',
        );
        E2EDevice? source;
        E2EDevice? receiver;
        AppDatabase? appDb;
        try {
          final appDbFile = await seedPkSchema39Fixture(directory);
          final engineDbPath = '${directory.path}/receiver-sync.sqlite';
          source = await createDevice(relay);
          receiver = await pairPersistentDevice(relay, source, engineDbPath);
          var activeReceiver = receiver;
          final sourceNodeId = await ffi.getNodeId(handle: source.handle);
          final receiverNodeIdBeforeRestart = await ffi.getNodeId(
            handle: activeReceiver.handle,
          );
          expect(receiverNodeIdBeforeRestart, isNot(sourceNodeId));

          await ffi.recordCreate(
            handle: source.handle,
            table: 'members',
            entityId: _remoteMember,
            fieldsJson: jsonEncode(_memberFields()),
          );
          for (final id in ['historical-front', 'fresh-front']) {
            await ffi.recordCreate(
              handle: source.handle,
              table: 'fronting_sessions',
              entityId: id,
              fieldsJson: jsonEncode(_frontFields('source-$id')),
            );
          }
          expect((await source.sync())['error'], anyOf(isNull, ''));
          expect((await receiver.sync())['error'], anyOf(isNull, ''));

          var activeDb = AppDatabase(NativeDatabase(appDbFile));
          appDb = activeDb;
          await activeDb.customSelect('SELECT 1').get();
          final version = await activeDb
              .customSelect('PRAGMA user_version')
              .getSingle();
          expect(version.read<int>('user_version'), 40);

          // The upgrade-only pass cannot guess a pre-alias identity.
          final upgrade = await repairPkFrontOrphansAfterUpgrade(
            db: activeDb,
            versionBefore: 39,
            versionAfter: 40,
          );
          expect(upgrade?.noEvidence, 1);

          // The real healthy hook reads retained native winners and persists the
          // validated alias without any fresh incoming operation being required.
          await runPostHealthySyncCatchUp(
            handle: activeReceiver.handle,
            db: activeDb,
            failureLabel: 'upgrade replay catch-up failed',
            drainOutbox: (_, _) async {},
            reemitGroupChatVisibility: (_, _) async =>
                const GroupChatVisibilitySyncReemitResult(),
            reemitOversizedInlineImages: (_, _) async =>
                const OversizedInlineImageReemitResult(),
            repairQuarantinedPushBatches: (_) async {},
            drainMigrationSyncRepairs: (_, _) async =>
                const MigrationSyncRepairResult(),
            catchUpPk: (_, _) async => const PkGroupSyncV2CatchupResult(),
            drain: (_) async {},
          );
          expect(
            (await activeDb.select(activeDb.frontingSessions).get())
                .singleWhere((row) => row.id == 'historical-front')
                .memberId,
            _localMember,
          );

          var wrapped = buildSyncAdapterWithCompletion(activeDb);
          var quarantine = SyncQuarantineService(activeDb.syncQuarantineDao);
          var restarted = false;
          while (true) {
            final chunk = DrainChunk.fromJson(
              jsonDecode(
                    await ffi.takeUndeliveredChanges(
                      handle: activeReceiver.handle,
                      limit: 1,
                    ),
                  )
                  as Map<String, dynamic>,
            );
            if (chunk.isEmpty) break;
            wrapped.beginSyncBatch();
            await applyConsumerDeliveriesHealingUnappliable(
              activeDb,
              wrapped.adapter,
              quarantine,
              chunk.deliveries,
            );
            await wrapped.completeSyncBatch();

            if (!restarted &&
                chunk.deliveries.any(
                  (row) => row.table == 'fronting_sessions',
                )) {
              // Crash-window counterfactual: Drift committed the delivery, but
              // the native high-water ACK did not. Close both real resources,
              // reopen, then prove the same durable page replays harmlessly.
              await activeDb.close();
              appDb = null;
              activeReceiver = await reopenPersistentDevice(
                relay,
                activeReceiver,
                engineDbPath,
                restartMode,
              );
              receiver = activeReceiver;
              expect(
                await ffi.getNodeId(handle: activeReceiver.handle),
                receiverNodeIdBeforeRestart,
                reason: 'native reopen must retain the paired device identity',
              );
              activeDb = AppDatabase(NativeDatabase(appDbFile));
              appDb = activeDb;
              await activeDb.customSelect('SELECT 1').get();
              wrapped = buildSyncAdapterWithCompletion(activeDb);
              quarantine = SyncQuarantineService(activeDb.syncQuarantineDao);
              final replay = DrainChunk.fromJson(
                jsonDecode(
                      await ffi.takeUndeliveredChanges(
                        handle: activeReceiver.handle,
                        limit: 1,
                      ),
                    )
                    as Map<String, dynamic>,
              );
              expect(replay.maxId, chunk.maxId);
              wrapped.beginSyncBatch();
              await applyConsumerDeliveriesHealingUnappliable(
                activeDb,
                wrapped.adapter,
                quarantine,
                replay.deliveries,
              );
              await wrapped.completeSyncBatch();
              await ffi.ackConsumerDeliveries(
                handle: activeReceiver.handle,
                upToId: replay.maxId,
              );
              restarted = true;
            } else {
              await ffi.ackConsumerDeliveries(
                handle: activeReceiver.handle,
                upToId: chunk.maxId,
              );
            }
          }
          expect(restarted, isTrue);

          // Reordered duplicate consumer replay models retry around an ACK
          // boundary. The
          // stale raw remote id must resolve through the persisted UUID alias.
          await applyConsumerDeliveriesHealingUnappliable(
            activeDb,
            wrapped.adapter,
            quarantine,
            [
              ConsumerDelivery(
                id: 9002,
                table: 'fronting_sessions',
                entityId: 'fresh-front',
                isDelete: false,
                fields: _frontFields('newer duplicate'),
              ),
              const ConsumerDelivery(
                id: 9001,
                table: 'fronting_sessions',
                entityId: 'fresh-front',
                isDelete: false,
                fields: {'member_id': _remoteMember},
              ),
            ],
          );

          final fronts = await activeDb.select(activeDb.frontingSessions).get();
          expect(fronts, hasLength(3));
          expect(
            fronts
                .where((row) => row.sessionType == 0)
                .every((row) => row.memberId == _localMember),
            isTrue,
          );
          final sleep = fronts.singleWhere(
            (row) => row.id == 'intentional-sleep',
          );
          expect(sleep.memberId, isNull);
          expect(sleep.sessionType, 1);
          expect(await quarantine.count(), 0);

          final reconciles = <Map<String, dynamic>>[];
          await MigrationSyncRepairService(
            db: activeDb,
            recordReconcile:
                ({required table, required entityId, required fields}) async {
                  reconciles.add({
                    'table': table,
                    'entity': entityId,
                    'fields': fields,
                  });
                  await ffi.recordReconcile(
                    handle: activeReceiver.handle,
                    table: table,
                    entityId: entityId,
                    fieldsJson: jsonEncode(fields),
                    divergentFreshHlc: true,
                  );
                },
          ).drain();
          expect(
            reconciles.where((row) => row['table'] == 'fronting_sessions'),
            isEmpty,
          );
          expect((await activeReceiver.sync())['error'], anyOf(isNull, ''));
          expect((await source.sync())['error'], anyOf(isNull, ''));
          expect(
            await ffi.readFieldValue(
              handle: source.handle,
              table: 'fronting_sessions',
              entityId: 'historical-front',
              field: 'member_id',
            ),
            jsonEncode(_remoteMember),
            reason: 'local projection recovery must not emit a peer correction',
          );

          // Terminal member delivery purges the recovery alias. A later import
          // with the same stable UUID is a new incarnation, and replaying the old
          // legacy delete must not kill it.
          await ffi.recordDelete(
            handle: source.handle,
            table: 'members',
            entityId: _remoteMember,
          );
          expect(
            await ffi.readFieldValue(
              handle: activeReceiver.handle,
              table: 'members',
              entityId: _remoteMember,
              field: 'is_deleted',
            ),
            'false',
          );
          final deleteSourceSync = await source.sync();
          expect(deleteSourceSync['error'], anyOf(isNull, ''));
          expect(
            (deleteSourceSync['pushed'] as num?)?.toInt() ?? 0,
            greaterThan(0),
            reason: 'source must publish the tombstone: $deleteSourceSync',
          );
          final deleteSyncs = <Map<String, dynamic>>[];
          for (var attempt = 0; attempt < 3; attempt++) {
            final result = await activeReceiver.sync();
            deleteSyncs.add(result);
            expect(result['error'], anyOf(isNull, ''));
            if (((result['merged'] as num?)?.toInt() ?? 0) > 0) break;
          }
          expect(
            deleteSyncs.fold<int>(
              0,
              (sum, result) => sum + ((result['pulled'] as num?)?.toInt() ?? 0),
            ),
            greaterThan(0),
            reason: 'the reopened receiver must pull the member tombstone',
          );
          expect(
            await ffi.readFieldValue(
              handle: activeReceiver.handle,
              table: 'members',
              entityId: _remoteMember,
              field: 'is_deleted',
            ),
            'true',
            reason: 'receiver state after sync: $deleteSyncs',
          );
          final deleteDeliveries = await _drainAll(
            activeReceiver,
            activeDb,
            wrapped,
            quarantine,
          );
          expect(
            deleteDeliveries,
            greaterThan(0),
            reason: 'a pulled tombstone must survive into the durable journal',
          );
          expect(
            await activeDb.pkIdentitySyncAliasesDao.getByLegacyEntityId(
              'members',
              _remoteMember,
            ),
            isNull,
          );

          await ffi.recordCreate(
            handle: source.handle,
            table: 'members',
            entityId: 'remote-member-reimport',
            fieldsJson: jsonEncode(_memberFields()),
          );
          expect((await source.sync())['error'], anyOf(isNull, ''));
          expect((await activeReceiver.sync())['error'], anyOf(isNull, ''));
          await _drainAll(activeReceiver, activeDb, wrapped, quarantine);
          await wrapped.adapter.hardDelete('members', _remoteMember);
          final reimport =
              await (activeDb.select(activeDb.members)
                    ..where((row) => row.id.equals('remote-member-reimport')))
                  .getSingle();
          expect(reimport.isDeleted, isFalse);
          expect(reimport.pluralkitUuid, _memberUuid);
        } finally {
          await appDb?.close();
          receiver?.dispose();
          source?.dispose();
          relay.stop();
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        }
      },
    );
  }

  test(
    'real retained tombstone and ambiguous holder evidence stay unresolved',
    skip: e2eSkip(),
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prism-pk-unresolved-',
      );
      final relay = await spawnRelay();
      E2EDevice? source;
      E2EDevice? receiver;
      AppDatabase? db;
      try {
        source = await createDevice(relay);
        receiver = await pairPersistentDevice(
          relay,
          source,
          '${directory.path}/receiver.sqlite',
        );
        await ffi.recordCreate(
          handle: source.handle,
          table: 'members',
          entityId: 'remote-tombstone',
          fieldsJson: jsonEncode({
            ..._memberFields(),
            'pluralkit_uuid': 'tombstone-uuid',
          }),
        );
        await ffi.recordDelete(
          handle: source.handle,
          table: 'members',
          entityId: 'remote-tombstone',
        );
        await ffi.recordCreate(
          handle: source.handle,
          table: 'members',
          entityId: 'remote-ambiguous',
          fieldsJson: jsonEncode({
            ..._memberFields(),
            'pluralkit_uuid': 'ambiguous-uuid',
          }),
        );
        await source.sync();
        await receiver.sync();

        db = AppDatabase(NativeDatabase.memory());
        await db.customSelect('SELECT 1').get();
        await db.customStatement('DROP INDEX idx_members_pluralkit_uuid');
        for (final id in ['holder-a', 'holder-b']) {
          await db
              .into(db.members)
              .insert(
                MembersCompanion.insert(
                  id: id,
                  name: id,
                  createdAt: DateTime.utc(2026, 1, 1),
                  pluralkitUuid: const Value('ambiguous-uuid'),
                ),
              );
        }
        for (final entry in const [
          ('front-tombstone', 'remote-tombstone'),
          ('front-ambiguous', 'remote-ambiguous'),
        ]) {
          await db
              .into(db.frontingSessions)
              .insert(
                FrontingSessionsCompanion.insert(
                  id: entry.$1,
                  startTime: DateTime.utc(2026, 2, 1),
                  memberId: Value(entry.$2),
                ),
              );
        }

        final result = await PkFrontOrphanProjectionRepair(db).run(
          readWinningField:
              ({required table, required entityId, required field}) =>
                  ffi.readFieldValue(
                    handle: receiver!.handle,
                    table: table,
                    entityId: entityId,
                    field: field,
                  ),
        );
        expect(result.repaired, 0);
        expect(result.engineTombstoned, 1);
        expect(result.ambiguousIdentity, 1);
        expect(
          (await db.select(db.frontingSessions).get()).map(
            (row) => row.memberId,
          ),
          containsAll(['remote-tombstone', 'remote-ambiguous']),
        );
        expect(
          await db.customSelect('SELECT 1 FROM pk_identity_sync_aliases').get(),
          isEmpty,
        );
      } finally {
        await db?.close();
        receiver?.dispose();
        source?.dispose();
        relay.stop();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
    },
  );
}
