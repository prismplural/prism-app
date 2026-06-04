// Cross-device LWW (last-write-wins) convergence end-to-end. Two paired devices
// concurrently edit the SAME field; after exchanging, both must converge to the
// same winning value. Reads the merged value on each device via the real FFI
// (read_field_value) — not just sync counts.
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

  test('concurrent edits to the same field converge across devices (LWW)',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a, b;
    try {
      a = await createDevice(relay);
      b = await pairNewDevice(relay, a);

      // Shared baseline both devices have.
      await ffi.recordCreate(
        handle: a.handle,
        table: 'members',
        entityId: 'lww-1',
        fieldsJson: '{"name":"init"}',
      );
      await a.sync();
      await b.sync();

      // CONCURRENT edit: each writes 'name' before seeing the other's write.
      await ffi.recordUpdate(
        handle: a.handle,
        table: 'members',
        entityId: 'lww-1',
        changedFieldsJson: '{"name":"from-A"}',
      );
      await ffi.recordUpdate(
        handle: b.handle,
        table: 'members',
        entityId: 'lww-1',
        changedFieldsJson: '{"name":"from-B"}',
      );

      // Exchange both ways and settle.
      await a.sync();
      await b.sync();
      await a.sync();
      await b.sync();

      // Both devices converge to the SAME winning value (LWW tiebreak), read
      // from each device's merged state. Values are JSON-encoded (quoted).
      final aVal = await ffi.readFieldValue(
        handle: a.handle,
        table: 'members',
        entityId: 'lww-1',
        field: 'name',
      );
      final bVal = await ffi.readFieldValue(
        handle: b.handle,
        table: 'members',
        entityId: 'lww-1',
        field: 'name',
      );
      expect(aVal, isNotNull, reason: 'A has a merged value for the field');
      expect(aVal, equals(bVal), reason: 'A and B must converge (A=$aVal B=$bVal)');
      expect(
        ['"from-A"', '"from-B"'],
        contains(aVal),
        reason: 'the converged value is one of the two real writes (was: $aVal)',
      );
    } finally {
      a?.dispose();
      b?.dispose();
      relay.stop();
    }
  });
}
