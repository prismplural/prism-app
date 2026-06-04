// Reusable device fixtures for the end-to-end FFI suite: create a first device
// (its own sync group) and pair a second device into it via the REAL pairing
// ceremony — both handles live in one test process, sharing one spawned relay.
//
// All of this drives the real compiled Rust FFI; nothing is mocked.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'e2e_support.dart';

/// A known-valid 12-word BIP39 phrase (all-zero entropy). The initiator needs
/// its mnemonic at pairing-complete time, so devices are created with a known
/// one rather than an auto-generated phrase we'd never see.
const String _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// A configured device: an opaque handle plus the bits needed to pair others in
/// and to drive sync. Call [dispose] in teardown.
class E2EDevice {
  E2EDevice({
    required this.handle,
    required this.syncId,
    required this.password,
    required this.mnemonic,
  });

  final ffi.PrismSyncHandle handle;
  final String syncId;
  final List<int> password;
  final List<int> mnemonic;

  /// Run a sync cycle; returns the decoded result `{pulled, merged, pushed, ...}`.
  Future<Map<String, dynamic>> sync() async =>
      jsonDecode(await ffi.syncNow(handle: handle)) as Map<String, dynamic>;

  void dispose() => handle.dispose();
}

/// A device's own `device_id` + `session_token`, read from its in-memory secure
/// store. The store holds raw UTF-8 (no base64 — that's only the app's keychain
/// encoding). Needed to drive device-management calls like `revokeDevice`.
Future<({String deviceId, String sessionToken})> credsOf(E2EDevice device) async {
  final store = await ffi.drainSecureStore(handle: device.handle);
  return (
    deviceId: utf8.decode(store['device_id']!),
    sessionToken: utf8.decode(store['session_token']!),
  );
}

/// Create a brand-new device that owns a fresh sync group on [relay].
Future<E2EDevice> createDevice(TestRelay relay, {String password = 'e2e-pin-0000'}) async {
  final handle = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: ':memory:',
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  final pw = utf8.encode(password);
  final mnemonic = utf8.encode(_testMnemonic);
  final created = jsonDecode(
    await ffi.createSyncGroup(
      handle: handle,
      password: pw,
      relayUrl: relay.baseUrl,
      mnemonic: Uint8List.fromList(mnemonic),
    ),
  ) as Map<String, dynamic>;
  await ffi.configureEngine(handle: handle);
  return E2EDevice(
    handle: handle,
    syncId: created['sync_id'] as String,
    password: pw,
    mnemonic: mnemonic,
  );
}

/// Pair a NEW (joiner) device into [initiator]'s group via the real ceremony,
/// then settle epochs so both are ready to exchange records. Returns the joiner.
///
/// The `complete_*` pair is mutually unblocking through the relay's pairing
/// slots, so they MUST run concurrently (Future.wait) or both time out.
Future<E2EDevice> pairNewDevice(TestRelay relay, E2EDevice initiator) async {
  // B (joiner): fresh empty handle on the SAME relay (the relay origin is bound
  // into the SAS transcript, so the URL must match the initiator's).
  final b = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: ':memory:',
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );

  try {
    // B starts the ceremony → rendezvous token (the only "out of band" datum).
    final joiner = jsonDecode(await ffi.startJoinerCeremony(handle: b)) as Map<String, dynamic>;
    final tokenBytes = (joiner['token_bytes'] as List).cast<int>();

    // A consumes B's token → its SAS + the joiner's device id (writes the
    // `init` slot, non-blocking).
    final init = jsonDecode(
      await ffi.startInitiatorCeremony(handle: initiator.handle, tokenBytes: tokenBytes),
    ) as Map<String, dynamic>;
    final joinerDeviceId = init['joiner_device_id'] as String;

    // B reads its SAS from the `init` slot A just wrote.
    final bSas = jsonDecode(await ffi.getJoinerSas(handle: b)) as Map<String, dynamic>;

    // The SAS match IS the confirmation (no FFI confirm call; the MAC check
    // inside complete_* enforces it cryptographically).
    expect(
      bSas['sas_word_list'],
      equals(init['sas_word_list']),
      reason: 'pairing SAS must match on both sides',
    );

    // A uploads the bootstrap snapshot BEFORE completing — completing rotates
    // A's epoch, after which the snapshot key would no longer match the bundle.
    await ffi.uploadPairingSnapshot(
      handle: initiator.handle,
      ttlSecs: BigInt.from(86400),
      forDeviceId: joinerDeviceId,
    );

    // Complete both sides CONCURRENTLY — they unblock each other via the relay.
    final results = await Future.wait([
      ffi.completeInitiatorCeremony(
        handle: initiator.handle,
        password: initiator.password,
        mnemonic: Uint8List.fromList(initiator.mnemonic),
      ),
      ffi.completeJoinerCeremony(handle: b, password: initiator.password),
    ]);
    final joinResult = jsonDecode(results[1]) as Map<String, dynamic>;
    expect(
      joinResult['sync_id'],
      equals(initiator.syncId),
      reason: 'joiner must land in the initiator\'s sync group',
    );

    // B configures its engine and bootstraps from the snapshot.
    await ffi.configureEngine(handle: b);
    await ffi.bootstrapFromSnapshot(handle: b);
    await ffi.acknowledgeSnapshotApplied(handle: b);

    final joinerDevice = E2EDevice(
      handle: b,
      syncId: initiator.syncId,
      password: initiator.password,
      mnemonic: initiator.mnemonic,
    );

    // Settle: completing pairing rotated A's epoch, so let both catch up.
    await initiator.sync();
    await joinerDevice.sync();

    return joinerDevice;
  } catch (e) {
    // Best-effort: cancel the ceremony so a failed pairing doesn't strand
    // background state, then drop the joiner handle.
    try {
      await ffi.cancelPairingCeremony(handle: b);
    } catch (_) {}
    b.dispose();
    rethrow;
  }
}
