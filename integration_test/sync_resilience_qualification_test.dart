// Gate A sync-resilience qualification harness: a real candidate macOS sender
// paired to a real candidate Android receiver through a local relay, with a
// host-side raw-TCP fault proxy that blackholes ONLY the relay->Android bytes of
// the receiver's already-upgraded WebSocket while leaving that socket open.
//
// What it proves
// --------------
// After three active fronting members are established and the fault is armed,
// the sender changes one member profile. The receiver must, with NO manual
// sync / rebind / restart, autonomously retire the silent socket, open a
// replacement, catch up within 110s, keep exactly the same three active fronts,
// and observe the profile change. A final diagnostic manual sync must merge 0.
//
// Every stage is gated by an explicit controller barrier, so the run cannot
// "pass" by accident: the fault is asserted armed on the host before the sender
// writes, and the receiver's recovery is observed purely by polling its own
// projected state.
//
// Prerequisites (host)
// --------------------
//   1. A local relay (e.g. the prism-sync `test_relay` binary) on :50225.
//   2. python3 scripts/sync_resilience_qualification_controller.py \
//          --relay http://localhost:50225
//      which prints CONTROLLER_URL and PROXY_URL and owns the fault proxy.
//   3. adb reverse for all three localhost ports on the Android device:
//          adb -s <serial> reverse tcp:50230 tcp:50230   # controller (KV/barriers)
//          adb -s <serial> reverse tcp:50225 tcp:50225   # direct relay for pairing
//          adb -s <serial> reverse tcp:50226 tcp:50226   # fault proxy
//
// Exact command contract
// ----------------------
// macOS sender:
//   flutter test integration_test/sync_resilience_qualification_test.dart -d macos \
//     --dart-define=PRISM_RESILIENCE_RUN_ID=<fresh-id> \
//     --dart-define=PRISM_RESILIENCE_CONTROLLER=http://localhost:50230 \
//     --dart-define=PRISM_RESILIENCE_RELAY=http://localhost:50225 \
//     --dart-define=PRISM_RESILIENCE_PROXY=http://localhost:50226
//
// Android receiver:
//   flutter test integration_test/sync_resilience_qualification_test.dart -d <serial> \
//     --dart-define=PRISM_RESILIENCE_RUN_ID=<same-fresh-id> \
//     --dart-define=PRISM_RESILIENCE_CONTROLLER=http://localhost:50230 \
//     --dart-define=PRISM_RESILIENCE_RELAY=http://localhost:50225 \
//     --dart-define=PRISM_RESILIENCE_PROXY=http://localhost:50226
//
// The role is derived from the native platform, not a Dart define. This is
// intentional: both concurrent Flutter commands therefore compile with the same
// defines and cannot race by overwriting a shared artifact with the peer's role.
// Launch the two roles in either order; pairing barriers self-synchronize. Use a
// FRESH run id and a fresh relay database per attempt.
//
// Secrecy: the mnemonic and password below are throwaway fixed literals for an
// ephemeral local run. They are passed only into FFI calls, never logged, and
// never published as evidence (see `_rejectSecrets`).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'support/sync_resilience_qualification_support.dart';

// ── Test constants ──────────────────────────────────────────────────────────

const _mac = 'mac';
const _android = 'android';

/// Throwaway fixed pairing literals for an ephemeral local run only.
const _password = 'resilience-pin-0001';
const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

const _memberNames = <String, String>{
  'qual-member-1': 'Qualified Member One',
  'qual-member-2': 'Qualified Member Two',
  'qual-member-3': 'Qualified Member Three',
};
const _updatedName = 'Qualified Member One (renamed during stall)';

final _expectedFrontIds = _memberNames.keys.map((id) => 'front-$id').toSet();

/// How long the receiver is allowed to recover on its own. Matches the gate.
const _recoveryBudget = Duration(seconds: 110);

final _frontStart = DateTime.utc(2026, 9, 16, 9);

// ── Harness ────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RustLib.init);
  tearDownAll(RustLib.dispose);

  test('stalled receiver autonomously replaces socket and catches up '
      '(real macOS sender + Android receiver through a raw TCP blackhole)', () async {
    expect(
      <String>{resilienceRoleMac, resilienceRoleAndroid},
      contains(resilienceRole),
      reason: 'run this qualification only on native macOS or Android',
    );
    expect(
      resilienceRunId.trim(),
      isNotEmpty,
      reason:
          'pass a fresh --dart-define=PRISM_RESILIENCE_RUN_ID for both devices',
    );

    final controller = ResilienceController();
    ffi.PrismSyncHandle? handle;
    File? engineDbFile;
    AppDatabase? consumerDb;
    _ReceiverProjection? projection;
    try {
      // Publish before Rust/database initialization. If a role never appears,
      // the failure is in native launch rather than pairing or sync.
      await controller.put('$resilienceRole/runtime-started', <String, dynamic>{
        'platform': Platform.operatingSystem,
        'role': resilienceRole,
      });
      final created = await _createHandle(resilienceRole);
      handle = created.handle;
      engineDbFile = created.dbFile;

      if (resilienceRole == resilienceRoleMac) {
        await _runMacSender(controller, handle);
      } else {
        // Pair/bootstrap before subscribing. Bootstrap emits a sync event while
        // its FFI call still owns the handle; a callback that immediately calls
        // back into the same handle would deadlock. No qualification changes
        // are sent until the subscription is installed below.
        consumerDb = AppDatabase(NativeDatabase.memory());
        await _pairAndroid(controller, handle);
        // From this point onward inbound changes use the real production
        // event-driven consumer-delivery drain path.
        projection = _ReceiverProjection(consumerDb, handle);
        await _runAndroidReceiver(controller, handle, consumerDb, projection);
      }

      await controller.evidence('complete', <String, dynamic>{'passed': true});
    } finally {
      // The FFI event stream's cancel future can remain pending after its native
      // producer is disposed. Begin cancellation, close the producer, and do not
      // use that future as a teardown barrier; all qualification work is already
      // complete and no further event can be emitted once the handle is gone.
      projection?.beginDispose();
      handle?.dispose();
      await consumerDb?.close();
      if (engineDbFile != null) await _deleteEngineDb(engineDbFile);
      // Best-effort: never leave the proxy armed between runs.
      try {
        await controller.clearFault();
      } catch (_) {}
      controller.close();
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

/// The receiver's real inbound projection path: subscribe to the engine's sync
/// event stream and let the production consumer-delivery drain apply every
/// RemoteChanges/SyncCompleted event into Drift.
///
/// This is what makes the recovery claim meaningful — the receiver applies data
/// because the engine delivered an event, not because the test called a sync.
class _ReceiverProjection {
  _ReceiverProjection(this.db, this.handle) {
    _adapter = buildSyncAdapterWithCompletion(db);
    _quarantine = SyncQuarantineService(db.syncQuarantineDao);
    _subscription = createSyncEventStream(handle).listen(
      _onEvent,
      onError: (Object error) {
        // A transport error is expected while the socket is half-open; the
        // engine retires and replaces it on its own. Record and continue.
        lastError = '$error';
      },
    );
  }

  final AppDatabase db;
  final ffi.PrismSyncHandle handle;

  late final SyncAdapterWithCompletion _adapter;
  late final SyncQuarantineService _quarantine;
  late final StreamSubscription<SyncEvent> _subscription;

  DateTime? lastEventAt;
  int eventsHandled = 0;
  DrainResult? lastDrain;
  String? lastError;

  Future<void> _onEvent(SyncEvent event) async {
    if (!event.isRemoteChanges && !event.isSyncCompleted) return;
    lastEventAt = DateTime.now();
    eventsHandled++;
    try {
      lastDrain = await drainRemoteDeliveries(
        handle,
        db: db,
        syncAdapter: _adapter,
        quarantine: _quarantine,
      );
    } catch (error) {
      lastError = '$error';
    }
  }

  /// Drain the consumer-delivery journal once, without touching the relay.
  ///
  /// Used only for deterministic pre-fault setup; the recovery window never
  /// calls this. The production drain serializes overlapping triggers itself.
  Future<DrainResult> drainNow() => drainRemoteDeliveries(
    handle,
    db: db,
    syncAdapter: _adapter,
    quarantine: _quarantine,
  );

  Future<void> waitForQuiescence({
    Duration quiet = const Duration(milliseconds: 1500),
    Duration budget = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(budget);
    while (DateTime.now().isBefore(deadline)) {
      final last = lastEventAt;
      if (last != null && DateTime.now().difference(last) >= quiet) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void beginDispose() => unawaited(_subscription.cancel());
}

// ── Shared plumbing ────────────────────────────────────────────────────────

Future<({ffi.PrismSyncHandle handle, File dbFile})> _createHandle(
  String role,
) async {
  final safeRun = resilienceRunId.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
  final dbFile = File(
    '${Directory.systemTemp.path}/prism-resilience-$safeRun-$role.sqlite3',
  );
  if (await dbFile.exists()) await dbFile.delete();
  final handle = await ffi.createPrismSync(
    relayUrl: resilienceRelayUrl,
    dbPath: dbFile.path,
    allowInsecure: true,
    schemaJson: prismSyncSchema,
  );
  return (handle: handle, dbFile: dbFile);
}

Future<void> _deleteEngineDb(File dbFile) async {
  for (final suffix in <String>['', '-wal', '-shm', '-journal']) {
    final file = File('${dbFile.path}$suffix');
    if (await file.exists()) await file.delete();
  }
}

Future<Map<String, dynamic>> _sync(ffi.PrismSyncHandle handle) async {
  final result = (jsonDecode(await ffi.syncNow(handle: handle)) as Map)
      .cast<String, dynamic>();
  expect(result['error'], anyOf(isNull, ''));
  return result;
}

// ── Pairing (both roles; identical ceremony to the mixed-version harness) ───

Future<void> _pairMac(
  ResilienceController controller,
  ffi.PrismSyncHandle handle,
) async {
  final created =
      (jsonDecode(
                await ffi.createSyncGroup(
                  handle: handle,
                  password: utf8.encode(_password),
                  relayUrl: resilienceRelayUrl,
                  mnemonic: Uint8List.fromList(utf8.encode(_mnemonic)),
                ),
              )
              as Map)
          .cast<String, dynamic>();
  await ffi.configureEngine(handle: handle);
  await controller.put('$_mac/group-ready', <String, dynamic>{'ready': true});

  final token = await controller.waitFor('$_android/joiner-token');
  final init =
      (jsonDecode(
                await ffi.startInitiatorCeremony(
                  handle: handle,
                  tokenBytes: (token['token_bytes'] as List).cast<int>(),
                ),
              )
              as Map)
          .cast<String, dynamic>();
  await controller.put('$_mac/init-ready', <String, dynamic>{
    'sas_words': init['sas_word_list'],
    'joiner_device_id': init['joiner_device_id'],
  });
  await controller.waitFor('$_android/sas-ok');

  // The snapshot must be uploaded before completing, because completing rotates
  // the epoch and would invalidate the snapshot key.
  await ffi.uploadPairingSnapshot(
    handle: handle,
    ttlSecs: BigInt.from(86400),
    forDeviceId: init['joiner_device_id'] as String,
  );
  await controller.put('$_mac/snapshot-uploaded', <String, dynamic>{
    'ready': true,
  });

  // Both sides publish before waiting, then complete concurrently: the two
  // `complete*` calls unblock each other through the relay pairing slots.
  await controller.put('$_mac/complete-started', <String, dynamic>{
    'ready': true,
  });
  await controller.waitFor('$_android/complete-started');
  await ffi.completeInitiatorCeremony(
    handle: handle,
    password: utf8.encode(_password),
    mnemonic: Uint8List.fromList(utf8.encode(_mnemonic)),
  );
  await controller.put('$_mac/pair-complete', <String, dynamic>{
    'sync_id_matches': created['sync_id'] is String,
  });
  await controller.waitFor('$_android/bootstrap-complete');
  await _sync(handle);
  await controller.put('$_mac/settled', <String, dynamic>{'ready': true});
  await controller.waitFor('$_android/settled');
  await _sync(handle);
}

Future<void> _pairAndroid(
  ResilienceController controller,
  ffi.PrismSyncHandle handle,
) async {
  await controller.waitFor('$_mac/group-ready');
  final joiner =
      (jsonDecode(await ffi.startJoinerCeremony(handle: handle)) as Map)
          .cast<String, dynamic>();
  await controller.put('$_android/joiner-token', <String, dynamic>{
    'token_bytes': joiner['token_bytes'],
  });

  final expected = await controller.waitFor('$_mac/init-ready');
  final actual = (jsonDecode(await ffi.getJoinerSas(handle: handle)) as Map)
      .cast<String, dynamic>();
  expect(actual['sas_word_list'], expected['sas_words']);
  await controller.put('$_android/sas-ok', <String, dynamic>{'matched': true});

  await controller.waitFor('$_mac/snapshot-uploaded');
  await controller.put('$_android/complete-started', <String, dynamic>{
    'ready': true,
  });
  await controller.waitFor('$_mac/complete-started');
  await ffi.completeJoinerCeremony(
    handle: handle,
    password: utf8.encode(_password),
  );

  await ffi.configureEngine(handle: handle);
  final restored = await ffi.bootstrapFromSnapshot(handle: handle);
  await ffi.acknowledgeSnapshotApplied(handle: handle);
  await controller.put('$_android/bootstrap-complete', <String, dynamic>{
    'restored_count': restored.toString(),
  });

  await controller.waitFor('$_mac/settled');
  await _sync(handle);
  await controller.put('$_android/settled', <String, dynamic>{'ready': true});
}

// ── macOS sender ───────────────────────────────────────────────────────────

Future<void> _runMacSender(
  ResilienceController controller,
  ffi.PrismSyncHandle handle,
) async {
  await _pairMac(controller, handle);

  // Establish the three active fronting members BEFORE any fault exists.
  for (final entry in _memberNames.entries) {
    await ffi.recordCreate(
      handle: handle,
      table: 'members',
      entityId: entry.key,
      fieldsJson: jsonEncode(<String, dynamic>{
        'name': entry.value,
        'created_at': _frontStart.toIso8601String(),
        'is_active': true,
        'is_deleted': false,
      }),
    );
  }
  for (final id in _memberNames.keys) {
    await ffi.recordCreate(
      handle: handle,
      table: 'fronting_sessions',
      entityId: 'front-$id',
      fieldsJson: jsonEncode(<String, dynamic>{
        'member_id': id,
        'start_time': _frontStart.toIso8601String(),
        'session_type': 0,
        'is_health_kit_import': false,
        'is_deleted': false,
      }),
    );
  }
  final establishment = await _sync(handle);
  await controller.put('$_mac/fronts-established', <String, dynamic>{
    'member_ids': _memberNames.keys.toList(),
    'front_ids': _expectedFrontIds.toList(),
    'count': _memberNames.length,
    'pushed': syncCount(establishment, 'pushed'),
  });
  await controller.waitFor('$_android/fronts-observed');

  // The receiver is now connected through the fault proxy. Arm the blackhole on
  // the socket it is actually using, and assert the host really selected one.
  await controller.waitFor('$_android/proxy-connected');
  final armed = await controller.armFault();
  expect(
    intValue(armed, 'targets'),
    greaterThan(0),
    reason: 'the blackhole must land on a live upgraded socket',
  );
  await controller.put('$_mac/fault-armed', <String, dynamic>{
    'targets': intValue(armed, 'targets'),
    'upgraded_total': intValue(armed, 'upgraded_total'),
  });

  // Barrier: only change the profile once the receiver has confirmed it is
  // inside the fault window and is observing.
  await controller.waitFor('$_android/observing');
  await ffi.recordUpdate(
    handle: handle,
    table: 'members',
    entityId: _memberNames.keys.first,
    changedFieldsJson: jsonEncode(<String, dynamic>{'name': _updatedName}),
  );
  final pushed = await _sync(handle);
  await controller.put('$_mac/profile-changed', <String, dynamic>{
    'pushed': syncCount(pushed, 'pushed'),
  });

  // Wait for the receiver's own autonomous recovery report.
  final recovered = await controller.waitFor(
    '$_android/recovered',
    timeout: _recoveryBudget + const Duration(seconds: 90),
  );

  final senderName = await ffi.readFieldValue(
    handle: handle,
    table: 'members',
    entityId: _memberNames.keys.first,
    field: 'name',
  );
  expect(senderName, jsonEncode(_updatedName));
  final senderStatus = (jsonDecode(await ffi.status(handle: handle)) as Map)
      .cast<String, dynamic>();
  expect(intValue(senderStatus, 'pending_ops'), 0);

  await controller.evidence('sender-converged', <String, dynamic>{
    'sender_engine_name_matches': true,
    'sender_pending_ops': intValue(senderStatus, 'pending_ops'),
    'receiver_elapsed_ms': intValue(recovered, 'elapsed_ms'),
    'receiver_upgraded_sockets': intValue(recovered, 'upgraded_sockets'),
  });

  await controller.waitFor('$_android/manual-sync-clean');
  await controller.put('$_mac/recovery-confirmed', <String, dynamic>{
    'ready': true,
  });
}

// ── Android receiver ───────────────────────────────────────────────────────

Future<void> _runAndroidReceiver(
  ResilienceController controller,
  ffi.PrismSyncHandle handle,
  AppDatabase db,
  _ReceiverProjection projection,
) async {
  Future<Set<String>> activeFrontIds() async {
    final rows = await db.frontingSessionsDao.getActiveSessions();
    return rows.map((row) => row.id).toSet();
  }

  Future<String?> projectedMemberName(String id) async {
    final row = await (db.select(
      db.members,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    return row?.name;
  }

  // ── Pre-fault: three active fronts must be projected ─────────────────────
  await controller.waitFor('$_mac/fronts-established');
  // Deterministic setup is allowed to pull explicitly. The autonomous recovery
  // window begins only after the fault is armed and never calls syncNow.
  final setupSync = await _sync(handle).timeout(const Duration(seconds: 90));
  await controller.put('$_android/setup-pull-complete', <String, dynamic>{
    'merged': syncCount(setupSync, 'merged'),
    'pulled': syncCount(setupSync, 'pulled'),
  });
  final setupDrain = await projection.drainNow().timeout(
    const Duration(seconds: 90),
  );
  await controller.put('$_android/setup-drain-complete', <String, dynamic>{
    'rows_applied': setupDrain.rowsApplied,
    'chunks_acked': setupDrain.chunksAcked,
  });
  final established = await pollUntil(() async {
    final ids = await activeFrontIds();
    return ids.length == _memberNames.length &&
        ids.containsAll(_expectedFrontIds);
  }, const Duration(seconds: 60));
  expect(
    established,
    isNotNull,
    reason:
        'the receiver must project exactly three active fronts before the fault',
  );
  final preFaultIds = await activeFrontIds();
  expect(preFaultIds, equals(_expectedFrontIds));
  await controller.put('$_android/fronts-observed', <String, dynamic>{
    'active_front_count': preFaultIds.length,
    'front_ids': preFaultIds.toList()..sort(),
  });
  await controller.evidence('pre-fault-fronts', <String, dynamic>{
    'active_front_count': preFaultIds.length,
    'exactly_three_fronts': preFaultIds.length == 3,
    'projection_events': projection.eventsHandled,
  });

  // ── Repoint this engine's relay traffic through the fault proxy ──────────
  // Pairing used the real relay origin (the SAS transcript binds it); from here
  // on the receiver talks to the proxy, which forwards to that same relay.
  await ffi.seedSecureStore(
    handle: handle,
    entries: <String, Uint8List>{
      'relay_url': Uint8List.fromList(utf8.encode(resilienceProxyUrl)),
    },
  );
  await ffi.configureEngine(handle: handle);
  await ffi.setAutoSync(
    handle: handle,
    enabled: true,
    debounceMs: BigInt.from(50),
    retryDelayMs: BigInt.from(100),
    maxRetries: 3,
  );
  final connected = await pollUntil(
    () => ffi.isWebsocketConnected(handle: handle),
    const Duration(seconds: 45),
  );
  expect(
    connected,
    isNotNull,
    reason: 'the receiver must connect through the fault proxy',
  );
  final preArmStatus = await controller.faultStatus();
  expect(intValue(preArmStatus, 'upgraded_sockets'), greaterThan(0));
  await controller.put('$_android/proxy-connected', <String, dynamic>{
    'upgraded_sockets': intValue(preArmStatus, 'upgraded_sockets'),
    'proxy_armed': preArmStatus['armed'],
  });

  // ── Fault activation barrier ─────────────────────────────────────────────
  await controller.waitFor('$_mac/fault-armed');
  final armedStatus = await controller.faultStatus();
  expect(
    armedStatus['armed'],
    isTrue,
    reason: 'the host proxy must report the blackhole armed',
  );
  final blackholedAtArm = intValue(armedStatus, 'blackholed_bytes');
  final forwardedAtArm = intValue(armedStatus, 'forwarded_bytes');
  final upgradedAtArm = intValue(armedStatus, 'upgraded_total');
  expect(
    upgradedAtArm,
    greaterThan(0),
    reason: 'a live upgraded socket must exist to blackhole',
  );
  await controller.evidence('fault-active', <String, dynamic>{
    'proxy_armed': true,
    'upgraded_sockets_at_arm': intValue(armedStatus, 'upgraded_sockets'),
    'upgraded_total_at_arm': upgradedAtArm,
  });

  // Tell the sender it may write: we are now genuinely observing under fault.
  await controller.put('$_android/observing', <String, dynamic>{
    'ready': true,
    'events_handled': projection.eventsHandled,
  });

  // ── Autonomous recovery observation (no manual sync, no rebind) ──────────
  final recovery = await pollUntil(() async {
    final ids = await activeFrontIds();
    if (ids.length != _memberNames.length) return false;
    if (!ids.containsAll(_expectedFrontIds)) return false;
    return await projectedMemberName(_memberNames.keys.first) == _updatedName;
  }, _recoveryBudget);

  final afterStatus = await controller.faultStatus();
  final blackholed =
      intValue(afterStatus, 'blackholed_bytes') - blackholedAtArm;
  final forwarded = intValue(afterStatus, 'forwarded_bytes') - forwardedAtArm;
  final upgradedTotal = intValue(afterStatus, 'upgraded_total');
  final upgradedSockets = intValue(afterStatus, 'upgraded_sockets');
  final postRecoveryIds = await activeFrontIds();

  // Fault really suppressed bytes on the socket the receiver was using.
  expect(
    blackholed,
    greaterThan(0),
    reason: 'the blackhole must actually have dropped relay->receiver bytes',
  );
  // The receiver replaced the silent socket, and later sockets stay live.
  expect(
    upgradedTotal,
    greaterThan(upgradedAtArm),
    reason: 'the receiver must open a replacement upgraded socket',
  );
  expect(
    forwarded,
    greaterThan(0),
    reason: 'later sockets and HTTP must keep flowing through the proxy',
  );
  // Recovery completed on its own, inside the gate, and changed nothing else.
  expect(
    recovery,
    isNotNull,
    reason:
        'the receiver must autonomously replace the stalled socket and catch up '
        'within ${_recoveryBudget.inSeconds}s without a manual sync',
  );
  expect(
    recovery!.inMilliseconds,
    lessThanOrEqualTo(_recoveryBudget.inMilliseconds),
  );
  expect(postRecoveryIds, equals(_expectedFrontIds));
  final observedProfileChange =
      await projectedMemberName(_memberNames.keys.first) == _updatedName;
  expect(observedProfileChange, isTrue);

  await controller.evidence('autonomous-recovery', <String, dynamic>{
    'elapsed_ms': recovery.inMilliseconds,
    'within_110s': recovery.inMilliseconds <= _recoveryBudget.inMilliseconds,
    'blackholed_bytes': blackholed,
    'forwarded_bytes_after_arm': forwarded,
    'upgraded_total_at_arm': upgradedAtArm,
    'upgraded_total_after': upgradedTotal,
    'upgraded_sockets_after': upgradedSockets,
    'replacement_socket_opened': upgradedTotal > upgradedAtArm,
    'active_front_count': postRecoveryIds.length,
    'same_three_fronts': postRecoveryIds.length == 3,
    'profile_change_observed': observedProfileChange,
    'manual_sync_used_for_recovery': false,
  });
  await controller.put('$_android/recovered', <String, dynamic>{
    'elapsed_ms': recovery.inMilliseconds,
    'upgraded_sockets': upgradedSockets,
    'upgraded_total': upgradedTotal,
    'blackholed_bytes': blackholed,
    'active_front_count': postRecoveryIds.length,
    'profile_observed': observedProfileChange,
  });

  // ── Final diagnostic manual sync must merge 0 ────────────────────────────
  // Wait for the event stream to go quiet first, so the reading reflects
  // automatic catch-up rather than an in-flight drain.
  final quiet = Stopwatch()..start();
  await projection.waitForQuiescence();
  final manual = (jsonDecode(await ffi.syncNow(handle: handle)) as Map)
      .cast<String, dynamic>();
  expect(
    syncCount(manual, 'merged'),
    0,
    reason: 'automatic catch-up must already have applied every change',
  );
  expect(syncCount(manual, 'pushed'), 0);
  final cleared = await controller.clearFault();
  await controller.evidence('manual-sync-clean', <String, dynamic>{
    'merged': syncCount(manual, 'merged'),
    'pulled': syncCount(manual, 'pulled'),
    'pushed': syncCount(manual, 'pushed'),
    'quiescence_wait_ms': quiet.elapsedMilliseconds,
    'proxy_cleared': cleared['armed'] == false,
    'active_front_count': postRecoveryIds.length,
  });
  await controller.put('$_android/manual-sync-clean', <String, dynamic>{
    'merged': syncCount(manual, 'merged'),
  });

  await controller.waitFor('$_mac/recovery-confirmed');
  await controller.put('$_android/done', <String, dynamic>{'ready': true});
}
