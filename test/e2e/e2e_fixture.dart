// Reusable device fixtures for the end-to-end FFI suite: create a first device
// (its own sync group) and pair a second device into it via the REAL pairing
// ceremony — both handles live in one test process, sharing one spawned relay.
//
// All of this drives the real compiled Rust FFI; nothing is mocked.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
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

/// Snapshot/event signature captured while pairing a fresh device.
class PairingSnapshotDiagnostics {
  PairingSnapshotDiagnostics({
    required this.device,
    required this.bootstrapRestored,
    required this.bootstrapEvents,
    required this.bootstrapConsumerDeliveryChunk,
    required this.postBootstrapSyncResults,
    required this.postBootstrapSyncEvents,
  });

  final E2EDevice device;
  final BigInt bootstrapRestored;
  final List<SyncEvent> bootstrapEvents;
  final Map<String, dynamic>? bootstrapConsumerDeliveryChunk;
  final List<Map<String, dynamic>> postBootstrapSyncResults;
  final List<SyncEvent> postBootstrapSyncEvents;

  Iterable<SyncEvent> get bootstrapRemoteChanges =>
      bootstrapEvents.where((event) => event.isRemoteChanges);

  int get bootstrapRemoteChangesCount => bootstrapRemoteChanges.length;

  int get bootstrapRemoteChangeRows => bootstrapRemoteChanges.fold(
    0,
    (sum, event) => sum + event.changes.length,
  );

  int get bootstrapConsumerDeliveryCount {
    final deliveries = bootstrapConsumerDeliveryChunk?['deliveries'];
    return deliveries is List ? deliveries.length : 0;
  }

  int get bootstrapConsumerDeliveryMaxId {
    final maxId = bootstrapConsumerDeliveryChunk?['max_id'];
    return maxId is num ? maxId.toInt() : 0;
  }

  bool get postBootstrapSyncsAreEmpty => postBootstrapSyncResults.every(
    (result) =>
        _syncResultInt(result, 'pulled') == 0 &&
        _syncResultInt(result, 'merged') == 0 &&
        _syncResultInt(result, 'pushed') == 0 &&
        (result['error'] == null || result['error'] == ''),
  );
}

/// A device's own `device_id` + `session_token`, read from its in-memory secure
/// store. The store holds raw UTF-8 (no base64 — that's only the app's keychain
/// encoding). Needed to drive device-management calls like `revokeDevice`.
Future<({String deviceId, String sessionToken})> credsOf(
  E2EDevice device,
) async {
  final store = await ffi.drainSecureStore(handle: device.handle);
  return (
    deviceId: utf8.decode(store['device_id']!),
    sessionToken: utf8.decode(store['session_token']!),
  );
}

/// Create a brand-new device that owns a fresh sync group on [relay].
Future<E2EDevice> createDevice(
  TestRelay relay, {
  String password = 'e2e-pin-0000',
}) async {
  final handle = await ffi.createPrismSync(
    relayUrl: relay.baseUrl,
    dbPath: ':memory:',
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  final pw = utf8.encode(password);
  final mnemonic = utf8.encode(_testMnemonic);
  final created =
      jsonDecode(
            await ffi.createSyncGroup(
              handle: handle,
              password: pw,
              relayUrl: relay.baseUrl,
              mnemonic: Uint8List.fromList(mnemonic),
            ),
          )
          as Map<String, dynamic>;
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
  final diagnostics = await pairNewDeviceWithSnapshotDiagnostics(
    relay,
    initiator,
    captureSnapshotEvents: false,
  );
  return diagnostics.device;
}

/// Pair a device and capture the raw FFI snapshot event contract.
Future<PairingSnapshotDiagnostics> pairNewDeviceWithSnapshotDiagnostics(
  TestRelay relay,
  E2EDevice initiator, {
  bool captureSnapshotEvents = true,
  int postBootstrapSyncCycles = 1,
}) async {
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
    final joiner =
        jsonDecode(
              await _withPhaseTimeout(
                'startJoinerCeremony',
                ffi.startJoinerCeremony(handle: b),
              ),
            )
            as Map<String, dynamic>;
    final tokenBytes = (joiner['token_bytes'] as List).cast<int>();

    // A consumes B's token → its SAS + the joiner's device id (writes the
    // `init` slot, non-blocking).
    final init =
        jsonDecode(
              await _withPhaseTimeout(
                'startInitiatorCeremony',
                ffi.startInitiatorCeremony(
                  handle: initiator.handle,
                  tokenBytes: tokenBytes,
                ),
              ),
            )
            as Map<String, dynamic>;
    final joinerDeviceId = init['joiner_device_id'] as String;

    // B reads its SAS from the `init` slot A just wrote.
    final bSas =
        jsonDecode(
              await _withPhaseTimeout(
                'getJoinerSas',
                ffi.getJoinerSas(handle: b),
              ),
            )
            as Map<String, dynamic>;

    // The SAS match IS the confirmation (no FFI confirm call; the MAC check
    // inside complete_* enforces it cryptographically).
    expect(
      bSas['sas_word_list'],
      equals(init['sas_word_list']),
      reason: 'pairing SAS must match on both sides',
    );

    // A uploads the bootstrap snapshot BEFORE completing — completing rotates
    // A's epoch, after which the snapshot key would no longer match the bundle.
    await _withPhaseTimeout(
      'uploadPairingSnapshot',
      ffi.uploadPairingSnapshot(
        handle: initiator.handle,
        ttlSecs: BigInt.from(86400),
        forDeviceId: joinerDeviceId,
      ),
      timeout: const Duration(seconds: 30),
    );

    // Complete both sides CONCURRENTLY — they unblock each other via the relay.
    final results = await _withPhaseTimeout(
      'complete pairing ceremony',
      Future.wait([
        ffi.completeInitiatorCeremony(
          handle: initiator.handle,
          password: initiator.password,
          mnemonic: Uint8List.fromList(initiator.mnemonic),
        ),
        ffi.completeJoinerCeremony(handle: b, password: initiator.password),
      ]),
      timeout: const Duration(seconds: 45),
    );
    final joinResult = jsonDecode(results[1]) as Map<String, dynamic>;
    expect(
      joinResult['sync_id'],
      equals(initiator.syncId),
      reason: 'joiner must land in the initiator\'s sync group',
    );

    // B configures its engine and bootstraps from the snapshot.
    await _withPhaseTimeout(
      'configureEngine(joiner)',
      ffi.configureEngine(handle: b),
    );

    final bootstrapRestored = await _withPhaseTimeout(
      'bootstrapFromSnapshot',
      ffi.bootstrapFromSnapshot(handle: b),
      timeout: const Duration(seconds: 45),
    );
    final bootstrapEvents = captureSnapshotEvents
        ? await _drainPolledEvents(
            b,
            phase: 'poll bootstrap events',
            window: const Duration(milliseconds: 250),
          )
        : <SyncEvent>[];

    final bootstrapConsumerDeliveryChunk = captureSnapshotEvents
        ? jsonDecode(
                await _withPhaseTimeout(
                  'takeUndeliveredChanges after bootstrap',
                  ffi.takeUndeliveredChanges(handle: b, limit: 1000),
                ),
              )
              as Map<String, dynamic>
        : null;

    await _withPhaseTimeout(
      'acknowledgeSnapshotApplied',
      ffi.acknowledgeSnapshotApplied(handle: b),
    );

    final joinerDevice = E2EDevice(
      handle: b,
      syncId: initiator.syncId,
      password: initiator.password,
      mnemonic: initiator.mnemonic,
    );

    // Settle: completing pairing rotated A's epoch, so let both catch up.
    await _withPhaseTimeout(
      'initiator post-pair sync',
      initiator.sync(),
      timeout: const Duration(seconds: 30),
    );
    final postBootstrapSyncResults = <Map<String, dynamic>>[];
    for (var i = 0; i < postBootstrapSyncCycles; i++) {
      postBootstrapSyncResults.add(
        await _withPhaseTimeout(
          'joiner post-bootstrap sync #$i',
          joinerDevice.sync(),
          timeout: const Duration(seconds: 30),
        ),
      );
    }
    final postBootstrapSyncEvents = captureSnapshotEvents
        ? await _drainPolledEvents(
            b,
            phase: 'poll post-bootstrap sync events',
            window: const Duration(milliseconds: 250),
          )
        : <SyncEvent>[];

    return PairingSnapshotDiagnostics(
      device: joinerDevice,
      bootstrapRestored: bootstrapRestored,
      bootstrapEvents: List<SyncEvent>.unmodifiable(bootstrapEvents),
      bootstrapConsumerDeliveryChunk: bootstrapConsumerDeliveryChunk,
      postBootstrapSyncResults: List<Map<String, dynamic>>.unmodifiable(
        postBootstrapSyncResults,
      ),
      postBootstrapSyncEvents: List<SyncEvent>.unmodifiable(
        postBootstrapSyncEvents,
      ),
    );
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

Future<T> _withPhaseTimeout<T>(
  String phase,
  Future<T> future, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    return await future.timeout(
      timeout,
      onTimeout: () {
        throw TimeoutException('Timed out during $phase after $timeout');
      },
    );
  } on TimeoutException {
    rethrow;
  }
}

Future<List<SyncEvent>> _drainPolledEvents(
  ffi.PrismSyncHandle handle, {
  required String phase,
  required Duration window,
}) async {
  final events = <SyncEvent>[];
  final deadline = DateTime.now().add(window);
  while (DateTime.now().isBefore(deadline)) {
    final raw = await _withPhaseTimeout(
      phase,
      ffi.pollEvent(handle: handle),
      timeout: const Duration(seconds: 2),
    );
    if (raw != null) {
      events.add(SyncEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
  return events;
}

int _syncResultInt(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
