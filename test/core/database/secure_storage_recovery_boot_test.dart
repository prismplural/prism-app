// Integration tests for the §4 + §5 boot probes and the §3 keychain-repair
// write-back, exercising the full recovery flow with mocked secure storage
// and a temp-directory-backed filesystem.
//
// These are not real device tests — they're Dart-level tests that drive the
// production probe + recovery functions through every recovery scenario the
// real device can hit. See `docs/0.9.2-secure-storage-remediation.md` §11.
//
// Scenarios covered:
//   1. Corrupted blob on every slot → unrecoverable → recovery UI routing.
//   2. Valid sync slot → silent recovery + repair-pending flag set;
//      retry write-back when keystore is still broken (flag stays set);
//      retry again after keystore recovers (flag clears, primary slot
//      now holds the verified key).
//   3. Fresh install with no prism.db → key generated and persisted.
//   4. Sync DB cross-recovery from the app primary slot.
//   5. Pairing state machine survives offline restart in `pendingPair`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/services/keychain_degraded_state.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_pairing_phase.dart';

Future<bool> _dartSyncDatabaseOpenProbe(String dbPath, String hexKey) async {
  return tryOpenEncryptedDb(dbPath, hexKey);
}

// ---------------------------------------------------------------------------
// In-memory secure-storage stub with per-key queued PlatformException support.
//
// Identical shape to the stubs already used in
// `database_provider_test.dart` / `prism_sync_providers_test.dart` so the
// behaviour matches the rest of the suite.
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final Map<String, String> store = <String, String>{};
  final Map<String, List<PlatformException>> throwOnReadKeyQueue =
      <String, List<PlatformException>>{};

  /// When true, every read for a key NOT explicitly queued throws a cipher
  /// exception. Lets us simulate "the whole keystore is broken right now".
  bool throwCipherOnAllReads = false;

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                if (value == null) {
                  store.remove(key);
                } else {
                  store[key] = value;
                }
                return null;
              case 'read':
                final key = call.arguments['key'] as String;
                final queue = throwOnReadKeyQueue[key];
                if (queue != null && queue.isNotEmpty) {
                  throw queue.removeAt(0);
                }
                if (throwCipherOnAllReads) {
                  throw _cipherException();
                }
                return store[key];
              case 'readAll':
                return Map<String, String>.from(store);
              case 'delete':
                store.remove(call.arguments['key'] as String);
                return null;
              case 'deleteAll':
                store.clear();
                return null;
              case 'containsKey':
                return store.containsKey(call.arguments['key'] as String);
              default:
                return null;
            }
          },
        );
  }

  void teardown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    store.clear();
    throwOnReadKeyQueue.clear();
    throwCipherOnAllReads = false;
  }
}

PlatformException _cipherException() => PlatformException(
  code: 'Exception encountered',
  message: 'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
  details:
      'javax.crypto.AEADBadTagException: Error while decrypting\n\tat '
      'com.it_nomads.fluttersecurestorage.FlutterSecureStorage.read(FlutterSecureStorage.java:200)',
);

String _hexKey(int fill) => fill.toRadixString(16).padLeft(2, '0') * 32;

/// Create an encrypted SQLite file at [path] using SQLite3MultipleCiphers.
void _createEncryptedDb(String path, String hexKey) {
  final db = raw.sqlite3.open(path);
  db.execute("PRAGMA key = \"x'$hexKey'\";");
  db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
  db.execute('INSERT INTO t (id) VALUES (1);');
  db.close();
}

void main() {
  // -------------------------------------------------------------------------
  // 1. Corrupted blob → unrecoverable → recovery UI route
  // -------------------------------------------------------------------------

  group('integration: corrupted blob across all slots → unrecoverable', () {
    late Directory tempDir;
    late _SecureStorageStub storageStub;
    late KeychainDegradedStateService degradedStateService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_int_corrupt_');
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      degradedStateService = KeychainDegradedStateService();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    test('prism.db exists, every secure-storage read throws cipher → '
        'unrecoverable + appDbKey=unreadable', () async {
      final hex = _hexKey(0x12);
      _createEncryptedDb('${tempDir.path}/prism.db', hex);

      // Make EVERY slot read throw cipher.
      storageStub.throwCipherOnAllReads = true;

      final report = await probeAppDatabaseStartup(
        directory: tempDir,
        degradedStateService: degradedStateService,
      );

      expect(report.state, DbStartupState.unrecoverable);
      expect(report.keyInMemory, isNull);
      expect(report.usedRecoverySlot, isNull);

      // Diagnostic captured cipher outcomes on every probed slot.
      final outcomes = report.diagnostic!.slotOutcomes;
      for (final id in const <String>[
        DiagnosticSlotIds.appDbPrimary,
        DiagnosticSlotIds.appDbSync,
        DiagnosticSlotIds.appDbSyncStaging,
      ]) {
        expect(
          outcomes[id],
          equals('cipher'),
          reason: 'slot $id should be classified as cipher failure',
        );
      }

      // Degraded state reflects "appDbKey unreadable" — main.dart uses
      // this to short-circuit to the recovery UI.
      final state = await degradedStateService.read();
      expect(state.appDbKey, SlotState.unreadable);

      // The repair-pending flag was NOT set (no verified key in memory).
      expect(await isKeychainRepairPending(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Valid sync slot → silent recovery + flag round-trips across boots
  // -------------------------------------------------------------------------

  group(
    'integration: sync-slot recovery → repair-pending → retry write-back',
    () {
      late Directory tempDir;
      late _SecureStorageStub storageStub;
      late KeychainDegradedStateService degradedStateService;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('prism_int_recover_');
        storageStub = _SecureStorageStub()..setup();
        SharedPreferences.setMockInitialValues(<String, Object>{});
        degradedStateService = KeychainDegradedStateService();
      });

      tearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        storageStub.teardown();
      });

      test(
        'valid sync slot opens DB → repair-pending set → write-back still '
        'broken on next attempt (flag stays) → keystore recovers → '
        'write-back succeeds → flag clears + primary slot now holds key',
        () async {
          final realKey = _hexKey(0xab);
          _createEncryptedDb('${tempDir.path}/prism.db', realKey);

          // Primary slot's read throws cipher; sync slot holds the real key.
          storageStub.throwOnReadKeyQueue[kDatabaseKeyStorageKey] = [
            _cipherException(),
          ];
          storageStub.store[kSyncDatabaseKeyStorageKey] = realKey;

          // --- Boot 1: probe recovers via sync slot ---
          final report = await probeAppDatabaseStartup(
            directory: tempDir,
            degradedStateService: degradedStateService,
          );

          expect(report.state, DbStartupState.ready);
          expect(report.usedRecoverySlot, 'sync');
          expect(report.keyInMemory, equals(realKey));
          expect(
            await isKeychainRepairPending(),
            isTrue,
            reason:
                'sync-slot recovery must set the repair-pending flag for the '
                'next boot to retry the write-back',
          );

          // --- Still on Boot 1: attempt the write-back while keystore is
          //     STILL broken (mock primary slot to cipher-throw again).
          storageStub.throwOnReadKeyQueue[kDatabaseKeyStorageKey] = [];
          // The actual writeback writes via writeDatabaseKeyHex which calls
          // safeSecureWrite — there is no throw queue on writes in the stub
          // so writes always succeed in this stub. To simulate a write
          // failure, force the underlying platform channel to throw by
          // overriding the handler temporarily.

          // Override handler to make writes fail.
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel(
                  'plugins.it_nomads.com/flutter_secure_storage',
                ),
                (MethodCall call) async {
                  if (call.method == 'write') {
                    throw _cipherException();
                  }
                  // Fall through to the existing in-memory store for reads,
                  // which keep the recovered state intact.
                  if (call.method == 'read') {
                    return storageStub.store[call.arguments['key'] as String];
                  }
                  return null;
                },
              );

          await attemptKeychainRepairWriteback(realKey);

          expect(
            await isKeychainRepairPending(),
            isTrue,
            reason:
                'write-back failed → flag must stay set for next boot retry',
          );

          // --- Boot 2: keystore has recovered. Restore the normal handler
          //     and retry the write-back. This time it succeeds and clears
          //     the flag, AND writes the verified key into the primary slot.
          storageStub.setup();
          storageStub.store[kSyncDatabaseKeyStorageKey] = realKey;

          await attemptKeychainRepairWriteback(realKey);

          expect(await isKeychainRepairPending(), isFalse);
          expect(
            storageStub.store[kDatabaseKeyStorageKey],
            equals(realKey),
            reason:
                'after successful write-back, primary slot must hold the '
                'verified key — repair is complete',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // 3. Fresh install — no prism.db on disk
  // -------------------------------------------------------------------------

  group('integration: fresh install probe', () {
    late Directory tempDir;
    late _SecureStorageStub storageStub;
    late KeychainDegradedStateService degradedStateService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_int_fresh_');
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      degradedStateService = KeychainDegradedStateService();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    test(
      'no prism.db + empty secure storage → ready(fresh) with a new key '
      'persisted via the guarded writer; repair-pending stays false',
      () async {
        expect(File('${tempDir.path}/prism.db').existsSync(), isFalse);

        final report = await probeAppDatabaseStartup(
          directory: tempDir,
          degradedStateService: degradedStateService,
        );

        expect(report.state, DbStartupState.ready);
        expect(report.usedRecoverySlot, 'fresh');
        expect(report.keyInMemory, isNotNull);
        expect(report.keyInMemory!.length, 64);
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(report.keyInMemory!),
          isTrue,
          reason: 'fresh install key must be lowercase hex',
        );
        // Key was written via the guarded writer.
        expect(
          storageStub.store[kDatabaseKeyStorageKey],
          equals(report.keyInMemory),
        );
        // Fresh installs never set the repair-pending flag.
        expect(await isKeychainRepairPending(), isFalse);
        final state = await degradedStateService.read();
        expect(state.appDbKey, SlotState.ok);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. Sync DB cross-recovery from app primary slot
  // -------------------------------------------------------------------------

  group('integration: sync DB cross-recovery from app primary', () {
    late Directory tempDir;
    late _SecureStorageStub storageStub;
    late KeychainDegradedStateService degradedStateService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_int_xrecover_');
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      degradedStateService = KeychainDegradedStateService();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    test('sync slot + sync staging cipher-broken, app primary holds the key '
        'that opens prism_sync.db (older-install convergence) → ready via '
        'app_primary', () async {
      final convergedKey = _hexKey(0xcc);
      _createEncryptedDb('${tempDir.path}/prism_sync.db', convergedKey);

      storageStub.throwOnReadKeyQueue[kSyncDatabaseKeyStorageKey] = [
        _cipherException(),
      ];
      storageStub.throwOnReadKeyQueue['${kSyncDatabaseKeyStorageKey}_staging'] =
          [_cipherException()];

      final report = await probeSyncDatabaseStartup(
        verifiedAppDbKey: convergedKey,
        directory: tempDir,
        degradedStateService: degradedStateService,
        syncDatabaseOpenProbe: _dartSyncDatabaseOpenProbe,
      );

      expect(report.state, DbStartupState.ready);
      expect(report.usedRecoverySlot, 'app_primary');
      expect(report.keyInMemory, equals(convergedKey));
      final state = await degradedStateService.read();
      expect(state.syncKey, SlotState.ok);
    });
  });

  // -------------------------------------------------------------------------
  // 5. Pairing state machine survives offline restart in pendingPair
  // -------------------------------------------------------------------------

  group('integration: pairing state machine offline-safe', () {
    late Directory tempDir;
    late _SecureStorageStub storageStub;
    late KeychainDegradedStateService degradedStateService;
    late SyncPairingPhaseService phaseService;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_int_pair_');
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      degradedStateService = KeychainDegradedStateService();
      phaseService = SyncPairingPhaseService();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    test('wipeSyncDatabaseForRepair: unread → wipeInProgress → pendingPair; '
        'sync DB file deleted; sync slots cleared; restart still in '
        'pendingPair (does NOT recreate broken state)', () async {
      // Pre-state: sync DB exists; key slots populated; syncKey state
      // is unreadable; pairing phase is unread.
      await degradedStateService.updateSlot('syncKey', SlotState.unreadable);
      final dbPath = '${tempDir.path}/prism_sync.db';
      _createEncryptedDb(dbPath, _hexKey(0xee));
      File('$dbPath-shm').writeAsStringSync('shm');
      File('$dbPath-wal').writeAsStringSync('wal');
      storageStub.store[kSyncDatabaseKeyStorageKey] = _hexKey(0xee);
      storageStub.store['${kSyncDatabaseKeyStorageKey}_staging'] = _hexKey(
        0xef,
      );
      storageStub.store['prism_sync.sync_id'] = 'sync-1';
      storageStub.store['prism_sync.device_id'] = 'dev-1';

      expect(await phaseService.read(), SyncPairingPhase.unread);

      // Run the wipe (simulates offline — we don't run FFI re-pair).
      await wipeSyncDatabaseForRepair(
        directory: tempDir,
        degradedStateService: degradedStateService,
        phaseService: phaseService,
      );

      // Post-wipe asserts: phase, files, slots.
      expect(await phaseService.read(), SyncPairingPhase.pendingPair);
      expect(File(dbPath).existsSync(), isFalse);
      expect(File('$dbPath-shm').existsSync(), isFalse);
      expect(File('$dbPath-wal').existsSync(), isFalse);
      expect(
        storageStub.store.containsKey(kSyncDatabaseKeyStorageKey),
        isFalse,
      );
      expect(
        storageStub.store.containsKey('${kSyncDatabaseKeyStorageKey}_staging'),
        isFalse,
      );
      expect(storageStub.store.containsKey('prism_sync.sync_id'), isFalse);
      expect(storageStub.store.containsKey('prism_sync.device_id'), isFalse);

      // ── Simulate "user goes offline / app restarts" ─────────────────
      //
      // SharedPreferences-backed phase persistence is durable across the
      // restart. A fresh SyncPairingPhaseService reads the same phase.
      final freshPhaseService = SyncPairingPhaseService();
      expect(
        await freshPhaseService.read(),
        SyncPairingPhase.pendingPair,
        reason:
            'state machine must survive offline restart in pendingPair — '
            'the pairing UI takes over from here without recreating the '
            'broken pre-wipe state',
      );

      // The sync DB file should still NOT exist post-restart — we did
      // not auto-recreate it. The pairing flow will create it on
      // successful pair.
      expect(File(dbPath).existsSync(), isFalse);
    });
  });
}
