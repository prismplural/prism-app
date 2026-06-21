// Pairing snapshot contract E2E.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  test(
    'fresh pairing snapshot restores state and leaves deliveries drainable',
    skip: e2eSkip(),
    () async {
      final relay = await spawnRelay();
      E2EDevice? initiator;
      PairingSnapshotDiagnostics? pairing;
      try {
        initiator = await createDevice(relay);

        for (var i = 0; i < 3; i++) {
          await ffi.recordCreate(
            handle: initiator.handle,
            table: 'members',
            entityId: 'snapshot-event-member-$i',
            fieldsJson: '{"name":"Snapshot Event $i"}',
          );
        }

        final seedPush = await initiator.sync();
        expect(seedPush['error'], isNull, reason: 'seed push: $seedPush');
        expect(
          seedPush['pushed'],
          greaterThanOrEqualTo(1),
          reason: 'initiator must upload seeded data before pairing',
        );

        pairing = await pairNewDeviceWithSnapshotDiagnostics(
          relay,
          initiator,
          postBootstrapSyncCycles: 2,
        );

        expect(
          pairing.bootstrapRestored,
          greaterThan(BigInt.zero),
          reason: 'snapshot bootstrap should restore the seeded initiator rows',
        );

        final restoredName = await ffi.readFieldValue(
          handle: pairing.device.handle,
          table: 'members',
          entityId: 'snapshot-event-member-0',
          field: 'name',
        );
        expect(
          restoredName,
          equals('"Snapshot Event 0"'),
          reason: 'joiner engine state must contain the snapshot data',
        );

        expect(
          pairing.bootstrapConsumerDeliveryCount,
          greaterThan(0),
          reason:
              'positive bootstrap restored ${pairing.bootstrapRestored} rows '
              'but left no drainable consumer deliveries. Polled '
              '${pairing.bootstrapRemoteChangesCount} RemoteChanges events / '
              '${pairing.bootstrapRemoteChangeRows} RemoteChanges rows; max '
              'delivery id '
              '${pairing.bootstrapConsumerDeliveryMaxId}; post-bootstrap '
              'sync results were ${pairing.postBootstrapSyncResults}',
        );
      } finally {
        pairing?.device.dispose();
        initiator?.dispose();
        relay.stop();
      }
    },
  );
}
