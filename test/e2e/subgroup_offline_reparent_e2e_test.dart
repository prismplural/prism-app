import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';
import 'pk_service_peer_fixture.dart';
import 'pk_upgrade_replay_fixture.dart' show pairPersistentDevice;

const _operationTimeout = Duration(seconds: 30);
const _names = ['Root', 'Other', 'Branch', 'Leaf', 'Sibling'];

/// Sticky for the rest of this suite. A 30s wait bounds only the Dart await
/// (see [_reopenOfflineDevice]), so an expiry leaves native work in flight that
/// Dart cannot cancel; such stores cannot be called quiescent.
bool _unprovenNativeWork = false;
String? _unprovenNativeReason;
String? _preservedStoresPath;

/// Latched by the body before its first allocation and cleared only when the
/// case's own teardown finishes. The framework's 3-minute timeout marks the
/// test failed but does not cancel the body future, so a still-set latch is the
/// one signal that a body (and its native work) may outlive the case.
bool _caseInProgress = false;
String? _caseTempPath;

void _markUnprovenNativeWork(String reason) {
  _unprovenNativeWork = true;
  final previous = _unprovenNativeReason;
  _unprovenNativeReason = previous == null ? reason : '$previous; $reason';
}

/// Failure text for the next case. Never a skip: an unproven predecessor means
/// the run must fail loudly, pointing at the preserved evidence.
String _poisonReason() {
  if (!_unprovenNativeWork) {
    return 'no unproven native work from a previous case';
  }
  return 'previous case left unproven native work '
      '(${_unprovenNativeReason ?? "unknown"}); stores preserved at '
      '${_preservedStoresPath ?? "unknown"}';
}

/// The same 30s bound as before, but an expiry is recorded as unproven native
/// work instead of looking like a clean finish.
Future<T> _bounded<T>(Future<T> work, String label) async {
  try {
    return await work.timeout(_operationTimeout);
  } on TimeoutException {
    _markUnprovenNativeWork('timeout: $label');
    rethrow;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureValues = <String, String?>{};
  var rustInitialized = false;
  // Drift's multiple-database warning is deliberately retained: two AppDatabase
  // instances alive at once is exactly the ownership overlap this suite can
  // create around the app/engine reopen.
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = call.arguments['key'] as String?;
            switch (call.method) {
              case 'write':
                secureValues[key!] = call.arguments['value'] as String?;
                break;
              case 'read':
                return secureValues[key];
              case 'delete':
                secureValues.remove(key);
                break;
            }
            return null;
          },
        );
    if (e2eSkip() == null) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(resolveFfiLib()),
      );
      rustInitialized = true;
    }
  });
  tearDownAll(() {
    // A case still in progress here means its body future outlived the suite
    // (framework timeout). Treat it as unproven before deciding on disposal.
    if (_caseInProgress) {
      _markUnprovenNativeWork(
        'suite ended with a case still in progress at '
        '${_caseTempPath ?? "unknown"}',
      );
    }
    // Terminal FFI cleanup is skipped while native work is unproven: a late
    // handle callback could otherwise land after the library is disposed. The
    // outer test process/gate owns that terminal cleanup.
    if (rustInitialized && !_unprovenNativeWork) {
      RustLib.dispose();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  for (final pkBacked in [false, true]) {
    test(
      '${pkBacked ? 'PK' : 'ordinary'} subgroup reparent survives offline '
      'app and engine reopen then reconnect',
      skip: e2eSkip(),
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        // A previous case that left native work in flight poisons this one: its
        // stores were preserved and are not trustworthy. Fail, never skip. A
        // case whose teardown never ran (framework timeout does not cancel the
        // body) counts as exactly such a case.
        if (_caseInProgress) {
          _markUnprovenNativeWork(
            'previous case never reached its teardown at '
            '${_caseTempPath ?? "unknown"}',
          );
        }
        expect(_unprovenNativeWork, isFalse, reason: _poisonReason());
        _caseInProgress = true;
        final directory = await Directory.systemTemp.createTemp(
          'subgroup-restart-',
        );
        _caseTempPath = directory.path;
        final port = await findFreePort();
        final relayPath = '${directory.path}/relay.sqlite';
        final enginePath = '${directory.path}/b-engine.sqlite';
        _RestartableRelay? relay;
        E2EDevice? aDevice;
        E2EDevice? bDevice;
        PkServicePeer? a;
        PkServicePeer? b;
        var bodySucceeded = false;
        try {
          final initialRelay = await _RestartableRelay.start(
            port,
            relayPath,
            onOwned: (owned) => relay = owned,
          );
          relay = initialRelay;
          final originalUrl = initialRelay.baseUrl;
          // Shared creation helpers retain ownership until they return; do not
          // wrap their whole result in a timeout that could discard a late device.
          aDevice = await createDevice(initialRelay);
          final initialB = await pairPersistentDevice(
            initialRelay,
            aDevice,
            enginePath,
          );
          bDevice = initialB;
          a = await _openPeer(aDevice, directory, 'a');
          b = await _openPeer(initialB, directory, 'b');
          expect(await b.db.memberGroupsDao.getAllActiveGroups(), isEmpty);
          await _bounded(_seedTree(a, pkBacked), 'seed tree');
          await _bounded(a.outbox.drain(aDevice.handle), 'initial drain a');
          await _settle(a, b);
          final initialA = await _tree(a, moved: false);
          expect(await _tree(b, moved: false), initialA);
          if (pkBacked) {
            final aRoot = (await a.db.memberGroupsDao.getAllActiveGroups())
                .singleWhere((g) => g.name == 'Root');
            final bRoot = (await b.db.memberGroupsDao.getAllActiveGroups())
                .singleWhere((g) => g.name == 'Root');
            expect(aRoot.id, startsWith('pk-group-'));
            expect(bRoot.id, startsWith('pk-group:'));
          }

          expect(await b.db.syncOutboxDao.count(), 0);
          // Stop and await the real relay process before mutating; no sleeps or
          // async push can accidentally deliver the offline operation.
          await initialRelay.stopAndWait();
          await b.activate();
          final groups = _groups(b);
          final before = await groups.getAllGroups();
          final branch = before.singleWhere((g) => g.name == 'Branch');
          final other = before.singleWhere((g) => g.name == 'Other');
          await groups.updateGroup(
            branch.copyWith(parentGroupId: other.id, displayOrder: 1),
          );
          final pending = await b.db.syncOutboxDao.allInIdOrder();
          expect(pending, isNotEmpty);
          final reparent = pending.singleWhere(
            (row) =>
                row.entityTable == 'member_groups' && row.opType == 'update',
          );
          expect(
            jsonDecode(reparent.fieldsJson),
            containsPair('parent_group_id', other.id),
          );
          expect(
            jsonDecode(reparent.fieldsJson),
            containsPair('display_order', 1),
          );
          final pendingIds = pending.map((row) => row.id).toList();
          final offlineTree = await _tree(b, moved: true);
          final nodeBefore = await ffi.getNodeId(handle: initialB.handle);

          // Both persistent stores close/reopen while the relay remains down.
          // This is a real engine/app reopen, not a whole OS process restart.
          await _bounded(b.close(), 'reopen close b');
          b = null;
          syncCurrentHandle.value = null;
          SyncRecordMixin.debugInstallOutboxRuntimeForTesting();
          final reopenedB = await _reopenOfflineDevice(
            initialRelay,
            initialB,
            enginePath,
            onOldDisposed: () => bDevice = null,
          );
          bDevice = reopenedB;
          expect(await ffi.getNodeId(handle: reopenedB.handle), nodeBefore);
          b = await _openPeer(reopenedB, directory, 'b');
          expect(await _tree(b, moved: true), offlineTree);
          expect(
            (await b.db.syncOutboxDao.allInIdOrder()).map((r) => r.id).toList(),
            pendingIds,
          );

          final reconnectedRelay = await _RestartableRelay.start(
            port,
            relayPath,
            onOwned: (owned) => relay = owned,
          );
          relay = reconnectedRelay;
          expect(reconnectedRelay.baseUrl, originalUrl);
          await b.activate();
          await _bounded(
            b.outbox.drain(reopenedB.handle),
            'post-reopen drain b',
          );
          await _settle(a, b);
          final converged = await _tree(a, moved: true);
          expect(await _tree(b, moved: true), converged);
          expect(await a.db.syncOutboxDao.count(), 0);
          expect(await b.db.syncOutboxDao.count(), 0);
          expect(await a.db.syncQuarantineDao.getAll(), isEmpty);
          expect(await b.db.syncQuarantineDao.getAll(), isEmpty);
          for (final peer in [a, b]) {
            final pendingDelivery =
                jsonDecode(
                      await ffi.takeUndeliveredChanges(
                        handle: peer.device.handle,
                        limit: 100,
                      ),
                    )
                    as Map<String, dynamic>;
            expect(pendingDelivery['deliveries'], isEmpty);
          }
          // Repeated sync/delivery is idempotent, not a one-shot snapshot success.
          await _settle(a, b);
          expect(await _tree(a, moved: true), converged);
          expect(await _tree(b, moved: true), converged);
          bodySucceeded = true;
        } finally {
          syncCurrentHandle.value = null;
          syncCredentialsPersisted.value = false;
          SyncRecordMixin.debugInstallOutboxRuntimeForTesting();
          // Teardown order is relay -> handles -> files: a live relay can still
          // drive pushes into the handles. Every step below bounds only the Dart
          // await (see _reopenOfflineDevice), so none of them proves native
          // quiescence; failures are recorded here instead of thrown over a body
          // failure, and the stores survive unless every step is confirmed.
          try {
            Object? relayError;
            try {
              await _bounded(
                relay?.stopAndWait() ?? Future<void>.value(),
                'teardown relay stop',
              );
            } catch (error) {
              relayError = error;
              _markUnprovenNativeWork(
                'relay stop failed: ${error.runtimeType}',
              );
            }
            final relayConfirmed =
                relayError == null && (relay?.stopped ?? true);
            var closesConfirmed = true;
            final peerB = b;
            if (peerB != null) {
              try {
                await _bounded(peerB.close(), 'teardown close b');
              } catch (error) {
                closesConfirmed = false;
                _markUnprovenNativeWork(
                  'close(b) failed: ${error.runtimeType}',
                );
                printOnFailure('close(b) failed: ${error.runtimeType}');
              }
            }
            final peerA = a;
            if (peerA != null) {
              try {
                await _bounded(peerA.close(), 'teardown close a');
              } catch (error) {
                closesConfirmed = false;
                _markUnprovenNativeWork(
                  'close(a) failed: ${error.runtimeType}',
                );
                printOnFailure('close(a) failed: ${error.runtimeType}');
              }
            }
            final deviceB = bDevice;
            if (deviceB != null) {
              try {
                deviceB.dispose();
              } catch (error) {
                _markUnprovenNativeWork(
                  'dispose(b) failed: ${error.runtimeType}',
                );
              }
            }
            final deviceA = aDevice;
            if (deviceA != null) {
              try {
                deviceA.dispose();
              } catch (error) {
                _markUnprovenNativeWork(
                  'dispose(a) failed: ${error.runtimeType}',
                );
              }
            }
            final storesRemovable =
                bodySucceeded &&
                closesConfirmed &&
                !_unprovenNativeWork &&
                relayConfirmed;
            if (storesRemovable) {
              await directory.delete(recursive: true);
            } else {
              _preservedStoresPath = directory.path;
              printOnFailure(
                'PRESERVED STORES: ${directory.path} (body=$bodySucceeded, '
                'closes=$closesConfirmed, relay=$relayConfirmed, '
                'unproven=${_unprovenNativeReason ?? "none"})',
              );
            }
            if (bodySucceeded && !storesRemovable) {
              throw StateError(
                'Teardown unconfirmed; stores preserved at ${directory.path} '
                '(closes=$closesConfirmed, relay=$relayConfirmed, '
                'unproven=${_unprovenNativeReason ?? "none"})',
              );
            }
          } finally {
            secureValues.clear();
            _caseInProgress = false;
            _caseTempPath = null;
          }
        }
      },
    );
  }
}

// Timeouts below bound Dart waits, not native execution. In-flight native work
// may settle later; disposal releases our handle ownership, not cancellation.
// Every wait here routes through [_bounded], which records an expiry as
// unproven native work: teardown then preserves the stores instead of deleting
// them, and the next case fails rather than running on. The external
// serial-check process-group deadline remains the final budget.
Future<E2EDevice> _reopenOfflineDevice(
  TestRelay relay,
  E2EDevice oldDevice,
  String enginePath, {
  required void Function() onOldDisposed,
}) async {
  // Until both exports succeed, the caller still owns the old device.
  final dek = await _bounded(
    ffi.exportDek(handle: oldDevice.handle),
    'export dek',
  );
  if (dek.isEmpty) throw StateError('missing synthetic runtime key');
  final secureStore = await _bounded(
    ffi.drainSecureStore(handle: oldDevice.handle),
    'drain secure store',
  );
  if (secureStore['device_secret'] == null) {
    throw StateError('missing synthetic device secret');
  }
  oldDevice.dispose();
  onOldDisposed();
  ffi.PrismSyncHandle? ownedHandle;
  var transferred = false;
  try {
    final creation = ffi.createPrismSync(
      relayUrl: relay.baseUrl,
      dbPath: enginePath,
      allowInsecure: true,
      schemaJson: prismSyncSchema,
    );
    var abandoned = false;
    // Observe both outcomes even if our wait expires. A late-created handle
    // must never arrive unowned, and a late error must not go unobserved: both
    // are recorded as unproven native work (error type only — messages can
    // carry store paths) so teardown preserves the stores and skips terminal
    // FFI cleanup.
    unawaited(
      creation.then<void>(
        (lateHandle) {
          if (abandoned) {
            lateHandle.dispose();
            _markUnprovenNativeWork('abandoned reopen handle arrived late');
          }
        },
        onError: (Object error, StackTrace stack) {
          _markUnprovenNativeWork(
            'late reopen create error: ${error.runtimeType}',
          );
        },
      ),
    );
    final ffi.PrismSyncHandle created;
    try {
      created = await _bounded(creation, 'reopen createPrismSync');
    } on TimeoutException {
      abandoned = true;
      rethrow;
    }
    ownedHandle = created;
    await _bounded(
      ffi.seedSecureStore(handle: created, entries: secureStore),
      'seed secure store',
    );
    final secretKey = await _bounded(
      ffi.mnemonicToBytes(mnemonic: Uint8List.fromList(oldDevice.mnemonic)),
      'mnemonicToBytes',
    );
    await _bounded(
      ffi.unlock(
        handle: created,
        password: oldDevice.password,
        secretKey: secretKey,
      ),
      'unlock',
    );
    await _bounded(ffi.configureEngine(handle: created), 'configureEngine');
    final reopened = E2EDevice(
      handle: created,
      syncId: oldDevice.syncId,
      password: oldDevice.password,
      mnemonic: oldDevice.mnemonic,
    );
    transferred = true;
    return reopened;
  } finally {
    if (!transferred) ownedHandle?.dispose();
  }
}

DriftMemberGroupsRepository _groups(PkServicePeer peer) =>
    DriftMemberGroupsRepository(
      peer.db.memberGroupsDao,
      peer.device.handle,
      memberRepository: peer.members,
    );

Future<PkServicePeer> _openPeer(
  E2EDevice device,
  Directory dir,
  String name,
) async {
  final peer = await PkServicePeer.open(
    device,
    dir,
    name,
    SyntheticPluralKitClient(members: const [], switches: const []),
  );
  await peer.db.systemSettingsDao.getSettings();
  await peer.db.systemSettingsDao.applyPartialSettings(
    const SystemSettingsTableCompanion(pkGroupSyncV2Enabled: Value(true)),
  );
  return peer;
}

Future<void> _seedTree(PkServicePeer peer, bool pkBacked) async {
  await peer.activate();
  await peer.members.createMember(
    domain.Member(
      id: 'member-local',
      name: 'Member',
      createdAt: DateTime.utc(2026),
      pluralkitUuid: pkBacked ? 'member-uuid' : null,
    ),
  );
  final groups = _groups(peer);
  if (pkBacked) {
    await PkGroupsImporter(
      db: peer.db,
      memberRepository: peer.members,
      syncHandle: peer.device.handle,
    ).importGroups([
      for (var i = 0; i < _names.length; i++)
        PKGroup(
          id: 'grp0$i',
          uuid: 'subgroup-uuid-$i',
          name: _names[i],
          memberIds: const [],
        ),
    ]);
  } else {
    for (final name in _names) {
      await groups.createGroup(
        domain.MemberGroup(
          id: 'group-$name',
          name: name,
          createdAt: DateTime.utc(2026),
        ),
      );
    }
  }
  final byName = {for (final g in await groups.getAllGroups()) g.name: g};
  for (final (child, parent) in [
    ('Branch', 'Root'),
    ('Leaf', 'Branch'),
    ('Sibling', 'Other'),
  ]) {
    await groups.updateGroup(
      byName[child]!.copyWith(
        parentGroupId: byName[parent]!.id,
        displayOrder: 0,
      ),
    );
  }
  await groups.addMemberToGroup(
    byName['Leaf']!.id,
    'member-local',
    'entry-leaf',
  );
}

Future<void> _settle(PkServicePeer a, PkServicePeer b) async {
  for (var cycle = 0; cycle < 3; cycle++) {
    await _bounded(a.syncAndApply(), 'settle sync a');
    await _bounded(b.syncAndApply(), 'settle sync b');
  }
}

Future<Map<String, Object?>> _tree(
  PkServicePeer peer, {
  required bool moved,
}) async {
  final rows = await peer.db.memberGroupsDao.getAllActiveGroups();
  expect(rows, hasLength(_names.length));
  final byId = {for (final row in rows) row.id: row};
  final byName = {for (final row in rows) row.name: row};
  final expectedParents = <String, String?>{
    'Root': null,
    'Other': null,
    'Branch': moved ? 'Other' : 'Root',
    'Leaf': 'Branch',
    'Sibling': 'Other',
  };
  for (final row in rows) {
    final parent = row.parentGroupId;
    if (parent != null) {
      expect(byId, contains(parent), reason: 'no dangling parent');
    }
    expect(
      parent == null ? null : byId[parent]!.name,
      expectedParents[row.name],
    );
    final seen = <String>{};
    MemberGroupRow? ancestor = row;
    while (ancestor != null) {
      expect(seen.add(ancestor.id), isTrue, reason: 'no hierarchy cycle');
      ancestor = byId[ancestor.parentGroupId];
    }
  }
  expect(byName['Branch']!.displayOrder, moved ? 1 : 0);
  expect(byName['Sibling']!.displayOrder, 0);
  final entries = await peer.db.memberGroupsDao.getAllGroupEntries();
  expect(entries, hasLength(1));
  expect(entries.single.groupId, byName['Leaf']!.id);
  final members = await peer.members.getAllMembers();
  expect(members, hasLength(1));
  expect(entries.single.memberId, members.single.id);
  return {
    for (final row in rows)
      row.name: {
        'parent': byId[row.parentGroupId]?.name,
        'order': row.displayOrder,
        'pk_uuid': row.pluralkitUuid,
      },
    'membership': ['Leaf', members.single.name],
  };
}

/// Scoped [HttpOverrides] that resolves the REAL client for the relay health
/// probe, which the test binding's global override would otherwise answer with
/// a synthetic 400 without touching the network. It forwards to the base
/// implementation on purpose: calling `HttpClient()` inside
/// `createHttpClient` would re-enter this override and recurse. The null
/// context is exactly what `HttpClient()` itself passes.
class _RealNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(null);
}

// Own the relay process locally because TestRelay.stop() does not await exit.
// Waiting for process exit prevents an old listener from racing a fixed-port
// restart; a single bounded health check verifies readiness before use.
class _RestartableRelay extends TestRelay {
  _RestartableRelay(this.process, String url) : super(process, url);
  final Process process;
  bool stopped = false;

  Future<void> stopAndWait() async {
    if (stopped) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 5));
    }
    stopped = true;
  }

  static Future<_RestartableRelay> start(
    int port,
    String dbPath, {
    required void Function(_RestartableRelay) onOwned,
  }) async {
    // Do not time out Process.start: a late-created process must not arrive
    // after ownership has been discarded. The test/gate is the outer budget.
    final process = await Process.start(
      resolveRelayBinary(),
      const [],
      environment: {'TEST_RELAY_PORT': '$port', 'TEST_RELAY_DB': dbPath},
    );
    var relay = _RestartableRelay(process, '');
    onOwned(relay);
    final urlReady = Completer<String>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('RELAY_URL=') && !urlReady.isCompleted) {
            urlReady.complete(
              line
                  .substring('RELAY_URL='.length)
                  .trim()
                  .replaceFirst('127.0.0.1', 'localhost'),
            );
          }
        });
    unawaited(process.stderr.drain<void>());
    try {
      final url = await Future.any<String>([
        urlReady.future,
        process.exitCode.then<String>(
          (code) => throw StateError('relay exited before readiness ($code)'),
        ),
      ]).timeout(const Duration(seconds: 20));
      relay = _RestartableRelay(process, url);
      onOwned(relay);
      // TestWidgetsFlutterBinding installs a global HttpOverrides whose client
      // answers every request with 400 without touching the network, so the
      // readiness probe must run under a scoped override that resolves a real
      // client. The 20s readiness bound, the 5s probe bounds and the 200
      // assertion are unchanged.
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        try {
          final request = await client
              .getUrl(Uri.parse('$url/health'))
              .timeout(const Duration(seconds: 5));
          final response = await request.close().timeout(
            const Duration(seconds: 5),
          );
          await response.drain<void>().timeout(const Duration(seconds: 5));
          if (response.statusCode != 200) {
            throw StateError('relay health is not ready');
          }
        } finally {
          client.close(force: true);
        }
      }, _RealNetworkHttpOverrides());
      return relay;
    } catch (_) {
      await relay.stopAndWait();
      rethrow;
    }
  }
}
