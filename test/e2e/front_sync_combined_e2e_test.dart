import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/pk_front_orphan_projection_repair.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/features/migration/services/migration_sync_repair_service.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

const remoteMember = 'front-e2e-remote-member';
const localMember = 'front-e2e-local-member';
const memberUuid = 'front-e2e-stable-pk-uuid';

Map<String, dynamic> memberFields() => {
  'name': 'Actual fronter',
  'created_at': '2026-09-07T10:00:00.000Z',
  'pluralkit_uuid': memberUuid,
  'is_deleted': false,
};

Map<String, dynamic> frontFields(String note) => {
  'start_time': '2026-09-07T12:00:00.000Z',
  'end_time': null,
  'member_id': remoteMember,
  'notes': note,
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

  test(
    'real paired clients preserve PK recovery across native split delivery '
    'and never sync an Unknown repair back',
    skip: e2eSkip(),
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final relay = await spawnRelay();
      E2EDevice? source;
      E2EDevice? receiver;
      final db = AppDatabase(NativeDatabase.memory());
      try {
        source = await createDevice(relay);
        receiver = await pairNewDevice(relay, source);
        final sourceDevice = source;
        final receiverDevice = receiver;
        await db.customSelect('SELECT 1').get();
        final adapter = buildSyncAdapterWithCompletion(db);
        final quarantine = SyncQuarantineService(db.syncQuarantineDao);
        await adapter.adapter.applyFields(
          'members',
          localMember,
          memberFields(),
        );

        await ffi.recordCreate(
          handle: sourceDevice.handle,
          table: 'members',
          entityId: remoteMember,
          fieldsJson: jsonEncode(memberFields()),
        );
        for (final front in ['historical-front', 'new-front']) {
          await ffi.recordCreate(
            handle: sourceDevice.handle,
            table: 'fronting_sessions',
            entityId: front,
            fieldsJson: jsonEncode(frontFields('note-$front')),
          );
        }
        expect((await sourceDevice.sync())['error'], anyOf(isNull, ''));
        expect((await receiverDevice.sync())['error'], anyOf(isNull, ''));

        // Reproduce a 0.14 orphan with retained native winners but no local alias.
        await adapter.adapter.applyFields(
          'fronting_sessions',
          'historical-front',
          frontFields('old projection'),
        );
        expect(
          await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
            'members',
            remoteMember,
          ),
          isNull,
        );
        final recovery = await PkFrontOrphanProjectionRepair(db).run(
          readWinningField:
              ({required table, required entityId, required field}) =>
                  ffi.readFieldValue(
                    handle: receiverDevice.handle,
                    table: table,
                    entityId: entityId,
                    field: field,
                  ),
        );
        expect(
          recovery.repaired,
          1,
          reason: 'Use real retained native member/tombstone evidence',
        );

        var rawPages = 0;
        var frontPages = 0;
        adapter.beginSyncBatch();
        try {
          await runRemoteDeliveryDrain(
            // Split every create regardless of field ordering.
            take: (_) async {
              final chunk = DrainChunk.fromJson(
                jsonDecode(
                      await ffi.takeUndeliveredChanges(
                        handle: receiverDevice.handle,
                        limit: 1,
                      ),
                    )
                    as Map<String, dynamic>,
              );
              if (!chunk.isEmpty) rawPages++;
              for (final delivery in chunk.deliveries) {
                if (delivery.table == 'fronting_sessions' &&
                    !delivery.isDelete) {
                  frontPages++;
                  expect(delivery.fields['member_id'], remoteMember);
                  expect(delivery.fields['start_time'], isNotNull);
                  expect(delivery.fields['session_type'], 0);
                  expect(delivery.fields['notes'], startsWith('note-'));
                }
              }
              return chunk;
            },
            ack: (id) => ffi.ackConsumerDeliveries(
              handle: receiverDevice.handle,
              upToId: id,
            ),
            applyChanges: (rows) => applyConsumerDeliveriesHealingUnappliable(
              db,
              adapter.adapter,
              quarantine,
              rows,
            ),
            quarantineSpill: (rows) =>
                quarantineConsumerDeliverySpill(quarantine, rows),
          );
        } finally {
          await adapter.completeSyncBatch();
        }
        expect(rawPages, greaterThan(2));
        expect(frontPages, greaterThan(2));
        final fronts = await db.select(db.frontingSessions).get();
        expect(fronts, hasLength(2));
        expect(
          fronts.every((front) => front.memberId == localMember),
          isTrue,
          reason: 'Native hydrated raw IDs must not undo local PK recovery',
        );
        expect(
          fronts.every((front) => front.notes == 'note-${front.id}'),
          isTrue,
        );
        expect(await quarantine.count(), 0);

        final emitted = <Map<String, dynamic>>[];
        await MigrationSyncRepairService(
          db: db,
          recordReconcile:
              ({required table, required entityId, required fields}) async {
                emitted.add({
                  'table': table,
                  'entity': entityId,
                  'fields': fields,
                });
                await ffi.recordReconcile(
                  handle: receiverDevice.handle,
                  table: table,
                  entityId: entityId,
                  fieldsJson: jsonEncode(fields),
                  divergentFreshHlc: true,
                );
              },
        ).drain();
        expect(
          emitted.where((event) => event['table'] == 'fronting_sessions'),
          isEmpty,
          reason:
              'The actual repair service must not originate an Unknown correction',
        );
        expect((await receiverDevice.sync())['error'], anyOf(isNull, ''));
        expect((await sourceDevice.sync())['error'], anyOf(isNull, ''));
        for (final front in ['historical-front', 'new-front']) {
          expect(
            await ffi.readFieldValue(
              handle: sourceDevice.handle,
              table: 'fronting_sessions',
              entityId: front,
              field: 'member_id',
            ),
            jsonEncode(remoteMember),
            reason:
                'The source peer must retain its own member identity after round trip',
          );
        }

        // Later hydration must preserve the recovered identity.
        await ffi.recordUpdate(
          handle: sourceDevice.handle,
          table: 'fronting_sessions',
          entityId: 'historical-front',
          changedFieldsJson: jsonEncode({'notes': 'later edit'}),
        );
        await sourceDevice.sync();
        await receiverDevice.sync();
        await drainRemoteDeliveries(
          receiverDevice.handle,
          db: db,
          syncAdapter: adapter,
          quarantine: quarantine,
        );
        final updated = (await db.select(db.frontingSessions).get())
            .singleWhere((front) => front.id == 'historical-front');
        expect(updated.memberId, localMember);
        expect(updated.notes, 'later edit');

        await ffi.recordDelete(
          handle: sourceDevice.handle,
          table: 'fronting_sessions',
          entityId: 'new-front',
        );
        await sourceDevice.sync();
        await receiverDevice.sync();
        await drainRemoteDeliveries(
          receiverDevice.handle,
          db: db,
          syncAdapter: adapter,
          quarantine: quarantine,
        );
        expect(
          (await db.select(db.frontingSessions).get()).map((front) => front.id),
          ['historical-front'],
        );
        // ignore: avoid_print
        print(
          'FRONT_E2E nativePages=$rawPages frontPages=$frontPages '
          'historicalRecovered=${recovery.repaired} frontRepairs=0 '
          'sourceMemberPreserved=true deleteConverged=true',
        );
      } finally {
        await db.close();
        receiver?.dispose();
        source?.dispose();
        relay.stop();
      }
    },
  );
}
