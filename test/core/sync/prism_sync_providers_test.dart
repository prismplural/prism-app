import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/services/runtime_dek_store.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';

void main() {
  test('syncStatusAfterCompleted keeps last successful sync on sync error', () {
    final previousSyncAt = DateTime.utc(2026, 3, 18, 12, 0, 0);
    final completedAt = DateTime.utc(2026, 3, 18, 12, 5, 0);

    final next = syncStatusAfterCompleted(
      previous: SyncStatus(
        isSyncing: true,
        lastSyncAt: previousSyncAt,
        pendingOps: 4,
      ),
      rawResultError: 'push rejected by relay',
      pendingOps: 2,
      hasQuarantinedItems: false,
      quarantinedBatchCount: 0,
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, previousSyncAt);
    expect(next.lastError, 'Prism sync failed: push rejected by relay');
    expect(next.pendingOps, 2);
  });

  test(
    'syncStatusAfterCompleted can hide retryable errors without marking success',
    () {
      final previousSyncAt = DateTime.utc(2026, 3, 18, 12, 0, 0);
      final completedAt = DateTime.utc(2026, 3, 18, 12, 5, 0);

      final next = syncStatusAfterCompleted(
        previous: SyncStatus(
          isSyncing: true,
          lastSyncAt: previousSyncAt,
          pendingOps: 4,
        ),
        rawResultError: 'relay timeout',
        pendingOps: 2,
        hasQuarantinedItems: false,
        quarantinedBatchCount: 0,
        surfaceResultError: false,
        completedAt: completedAt,
      );

      expect(next.isSyncing, isFalse);
      expect(next.lastSyncAt, previousSyncAt);
      expect(next.lastError, isNull);
      expect(next.pendingOps, 2);
    },
  );

  test('syncStatusAfterCompleted records a new sync time on success', () {
    final completedAt = DateTime.utc(2026, 3, 18, 12, 5, 0);

    final next = syncStatusAfterCompleted(
      previous: const SyncStatus(isSyncing: true, lastError: 'old error'),
      rawResultError: null,
      pendingOps: 0,
      hasQuarantinedItems: true,
      quarantinedBatchCount: 0,
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, completedAt);
    expect(next.lastError, isNull);
    expect(next.hasQuarantinedItems, isTrue);
  });

  test('syncStatusAfterCompleted treats empty-string error as success', () {
    final completedAt = DateTime.utc(2026, 3, 18, 12, 10, 0);

    final next = syncStatusAfterCompleted(
      previous: const SyncStatus(isSyncing: true),
      rawResultError: '',
      pendingOps: 0,
      hasQuarantinedItems: false,
      quarantinedBatchCount: 0,
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, completedAt);
    expect(next.lastError, isNull);
  });

  group('shouldSurfaceSyncError', () {
    test('suppresses retryable attempt errors', () {
      expect(
        shouldSurfaceSyncError(errorKind: 'Network', retryable: true),
        isFalse,
      );
      expect(
        shouldSurfaceSyncError(errorKind: 'Server', retryable: true),
        isFalse,
      );
      expect(
        shouldSurfaceSyncError(errorKind: 'Timeout', retryable: true),
        isFalse,
      );
    });

    test('surfaces terminal and non-retryable errors', () {
      expect(
        shouldSurfaceSyncError(errorKind: 'Network', retryable: false),
        isTrue,
      );
      expect(
        shouldSurfaceSyncError(errorKind: 'Auth', retryable: false),
        isTrue,
      );
      expect(
        shouldSurfaceSyncError(errorKind: 'Protocol', retryable: null),
        isTrue,
      );
    });
  });

  // --------------------------------------------------------------------
  // computeSeedEntries — the Dart-side dynamic-key seed pipeline.
  // --------------------------------------------------------------------

  group('computeSeedEntries', () {
    test('returns empty map when keychain has nothing to seed', () {
      expect(computeSeedEntries({}), isEmpty);
    });

    test('includes every static allow-list entry present in the keychain', () {
      final result = computeSeedEntries({
        'prism_sync.wrapped_dek': 'aW==',
        'prism_sync.device_id': 'ZGV2aWNlMQ==',
        'prism_sync.sync_id': 'c3luYzE=',
        'prism_sync.registration_token': 'cmVnLXRva2Vu',
      });
      expect(result['wrapped_dek'], 'aW==');
      expect(result['device_id'], 'ZGV2aWNlMQ==');
      expect(result['sync_id'], 'c3luYzE=');
      expect(result['registration_token'], 'cmVnLXRva2Vu');
    });

    test('seed includes epoch_key_* entries from the keychain', () {
      final result = computeSeedEntries({
        'prism_sync.sync_id': 'c3luYzE=',
        'prism_sync.epoch_key_1': 'a2V5MQ==',
        'prism_sync.epoch_key_3': 'a2V5Mw==',
        'prism_sync.epoch_key_17': 'a2V5MTc=',
      });
      // Allow-list static key still included.
      expect(result['sync_id'], 'c3luYzE=');
      // Dynamic epoch keys picked up via prefix scan.
      expect(result['epoch_key_1'], 'a2V5MQ==');
      expect(result['epoch_key_3'], 'a2V5Mw==');
      expect(result['epoch_key_17'], 'a2V5MTc=');
    });

    test('seed includes runtime_keys_* entries from the keychain', () {
      final result = computeSeedEntries({
        'prism_sync.runtime_keys_abc': 'cnVudGltZQ==',
        'prism_sync.runtime_keys_xyz': 'eHl6',
      });
      expect(result['runtime_keys_abc'], 'cnVudGltZQ==');
      expect(result['runtime_keys_xyz'], 'eHl6');
    });

    test('ignores entries not using the prism_sync prefix', () {
      final result = computeSeedEntries({
        'other_app.wrapped_dek': 'bogus',
        'prism_sync_bogus.epoch_key_1': 'bogus2',
      });
      expect(result, isEmpty);
    });

    test('ignores non-dynamic prefixed entries that are not allow-listed', () {
      final result = computeSeedEntries({'prism_sync.unknown_key': 'bogus'});
      expect(result, isEmpty);
    });
  });

  group('buildRuntimeDekAad', () {
    test('binds sync id, device id, and wrapper version', () {
      expect(
        buildRuntimeDekAad(syncId: 'sync-1', deviceId: 'device-1'),
        'sync-1|device-1|1',
      );
    });

    test('returns null when either identity component is missing', () {
      expect(buildRuntimeDekAad(syncId: null, deviceId: 'device-1'), isNull);
      expect(buildRuntimeDekAad(syncId: 'sync-1', deviceId: null), isNull);
      expect(buildRuntimeDekAad(syncId: '', deviceId: 'device-1'), isNull);
      expect(buildRuntimeDekAad(syncId: 'sync-1', deviceId: ''), isNull);
    });
  });

  group('runtime DEK platform support', () {
    test('supports mobile and desktop runtime cache wrappers', () {
      expect(
        isRuntimeDekWrappingPlatformSupported(
          isAndroid: true,
          isIOS: false,
          isMacOS: false,
          isWindows: false,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        isRuntimeDekWrappingPlatformSupported(
          isAndroid: false,
          isIOS: true,
          isMacOS: false,
          isWindows: false,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        isRuntimeDekWrappingPlatformSupported(
          isAndroid: false,
          isIOS: false,
          isMacOS: true,
          isWindows: false,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        isRuntimeDekWrappingPlatformSupported(
          isAndroid: false,
          isIOS: false,
          isMacOS: false,
          isWindows: true,
          isLinux: false,
        ),
        isTrue,
      );
      expect(
        isRuntimeDekWrappingPlatformSupported(
          isAndroid: false,
          isIOS: false,
          isMacOS: false,
          isWindows: false,
          isLinux: true,
        ),
        isTrue,
      );
    });

    test('does not claim unsupported platforms', () {
      expect(
        isRuntimeDekWrappingPlatformSupported(
          isAndroid: false,
          isIOS: false,
          isMacOS: false,
          isWindows: false,
          isLinux: false,
        ),
        isFalse,
      );
    });
  });

  group('Linux runtime DEK AES-GCM wrapper', () {
    test('round-trips with matching AAD', () {
      final plaintext = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final key = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
      final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i + 1));
      final aad = utf8.encode('sync-1|device-1|1');

      final combined = aesGcmEncryptForRuntimeDek(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );
      expect(combined, isNot(orderedEquals(plaintext)));
      expect(combined.length, plaintext.length + 16);

      final restored = aesGcmDecryptForRuntimeDek(
        combined: combined,
        key: key,
        nonce: nonce,
        aad: aad,
      );
      expect(restored, orderedEquals(plaintext));
    });

    test('rejects mismatched AAD', () {
      final plaintext = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final key = Uint8List.fromList(List<int>.generate(32, (i) => 7 + i));
      final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 33 + i));
      final combined = aesGcmEncryptForRuntimeDek(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: utf8.encode('sync-1|device-1|1'),
      );

      expect(
        () => aesGcmDecryptForRuntimeDek(
          combined: combined,
          key: key,
          nonce: nonce,
          aad: utf8.encode('sync-1|other-device|1'),
        ),
        throwsA(anything),
      );
    });
  });

  group('hasCompletePersistentSyncIdentity', () {
    test('requires relay, sync id, device id, and device secret', () {
      expect(
        hasCompletePersistentSyncIdentity(
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-1',
          deviceId: 'device-1',
          hasDeviceSecret: true,
        ),
        isTrue,
      );

      expect(
        hasCompletePersistentSyncIdentity(
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-1',
          deviceId: null,
          hasDeviceSecret: true,
        ),
        isFalse,
      );
      expect(
        hasCompletePersistentSyncIdentity(
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-1',
          deviceId: 'device-1',
          hasDeviceSecret: false,
        ),
        isFalse,
      );
    });
  });

  group('readCachedRuntimeDekForRestoreCore', () {
    test(
      'migrates legacy raw runtime_dek into wrapped slot and deletes raw',
      () async {
        final rawDek = List<int>.generate(32, (i) => i);
        final store = <String, String>{kRuntimeDekKey: base64Encode(rawDek)};

        final restored = await readCachedRuntimeDekForRestoreCore(
          aad: 'sync-1|device-1|1',
          readKey: (key) async => store[key],
          deleteKey: (key) async {
            store.remove(key);
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          unwrapDek: (_, _) => throw StateError('should not unwrap'),
          wrapDek: (dekBytes, aad) async {
            expect(aad, 'sync-1|device-1|1');
            expect(dekBytes, rawDek);
            return 'wrapped-json';
          },
        );

        expect(restored, rawDek);
        expect(store[kRuntimeDekKey], isNull);
        expect(store[kRuntimeDekWrappedKey], 'wrapped-json');
      },
    );

    test(
      'deletes legacy raw runtime_dek after wrapped restore succeeds',
      () async {
        final rawDek = List<int>.generate(32, (i) => i);
        final restoredDek = List<int>.generate(32, (i) => 255 - i);
        final store = <String, String>{
          kRuntimeDekKey: base64Encode(rawDek),
          kRuntimeDekWrappedKey: 'wrapped-json',
        };

        final restored = await readCachedRuntimeDekForRestoreCore(
          aad: 'sync-1|device-1|1',
          readKey: (key) async => store[key],
          deleteKey: (key) async {
            store.remove(key);
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          unwrapDek: (blob, aad) async {
            expect(blob, 'wrapped-json');
            expect(aad, 'sync-1|device-1|1');
            return Uint8List.fromList(restoredDek);
          },
          wrapDek: (_, _) => throw StateError('should not wrap'),
        );

        expect(restored, restoredDek);
        expect(store[kRuntimeDekKey], isNull);
        expect(store[kRuntimeDekWrappedKey], 'wrapped-json');
      },
    );

    test('wrapped restore returns a mutable Dart-owned copy', () async {
      final restoredDek = Uint8List.fromList(
        List<int>.generate(32, (i) => 255 - i),
      ).asUnmodifiableView();
      final store = <String, String>{kRuntimeDekWrappedKey: 'wrapped-json'};

      final restored = await readCachedRuntimeDekForRestoreCore(
        aad: 'sync-1|device-1|1',
        readKey: (key) async => store[key],
        deleteKey: (key) async {
          store.remove(key);
        },
        writeKey: (key, value) async {
          store[key] = value;
        },
        unwrapDek: (_, _) async => restoredDek,
        wrapDek: (_, _) => throw StateError('should not wrap'),
      );

      expect(restored, restoredDek);
      expect(() => restored!.fillRange(0, restored.length, 0), returnsNormally);
      expect(restored, everyElement(0));
    });

    test(
      'falls back to legacy raw runtime_dek when wrapped restore fails',
      () async {
        final rawDek = List<int>.generate(32, (i) => i);
        final store = <String, String>{
          kRuntimeDekKey: base64Encode(rawDek),
          kRuntimeDekWrappedKey: 'stale-wrapped-json',
        };

        final restored = await readCachedRuntimeDekForRestoreCore(
          aad: 'sync-1|device-1|1',
          readKey: (key) async => store[key],
          deleteKey: (key) async {
            store.remove(key);
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          unwrapDek: (_, _) => throw StateError('stale native wrapping key'),
          wrapDek: (dekBytes, aad) async {
            expect(aad, 'sync-1|device-1|1');
            expect(dekBytes, rawDek);
            return 'rewrapped-json';
          },
        );

        expect(restored, rawDek);
        expect(store[kRuntimeDekKey], isNull);
        expect(store[kRuntimeDekWrappedKey], 'rewrapped-json');
      },
    );

    test(
      'deletes invalid legacy raw runtime_dek without writing wrapped slot',
      () async {
        final store = <String, String>{kRuntimeDekKey: 'not-base64'};

        final restored = await readCachedRuntimeDekForRestoreCore(
          aad: 'sync-1|device-1|1',
          readKey: (key) async => store[key],
          deleteKey: (key) async {
            store.remove(key);
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          unwrapDek: (_, _) => throw StateError('should not unwrap'),
          wrapDek: (_, _) => throw StateError('should not wrap'),
        );

        expect(restored, isNull);
        expect(store[kRuntimeDekKey], isNull);
        expect(store[kRuntimeDekWrappedKey], isNull);
      },
    );

    // ── Classification + retry policy (Android Keystore eviction fix) ────
    //
    // Pre-fix: any unwrap failure deleted the wrapped cache and forced a
    // full PIN+12-words re-auth on the NEXT launch. Post-fix: classify
    // the failure and only delete on terminal codes; transient codes get
    // one retry; unknown codes preserve the cache so future launches can
    // try again.

    test('transient unwrap failure: retries once, succeeds, returns DEK and '
        'PRESERVES wrapped cache', () async {
      final restoredDek = List<int>.generate(32, (i) => 99);
      final store = <String, String>{kRuntimeDekWrappedKey: 'transient-blob'};
      var attempts = 0;

      final restored = await readCachedRuntimeDekForRestoreCore(
        aad: 'sync-1|device-1|1',
        readKey: (key) async => store[key],
        deleteKey: (key) async {
          store.remove(key);
        },
        writeKey: (key, value) async {
          store[key] = value;
        },
        unwrapDek: (_, _) async {
          attempts++;
          if (attempts == 1) {
            throw PlatformException(code: 'runtime_dek_wrap_transient');
          }
          return Uint8List.fromList(restoredDek);
        },
        wrapDek: (_, _) => throw StateError('should not wrap'),
      );

      expect(attempts, 2);
      expect(restored, restoredDek);
      expect(store[kRuntimeDekWrappedKey], 'transient-blob');
    });

    test('transient unwrap failure that persists across retry: returns null '
        'but PRESERVES wrapped cache for next launch', () async {
      final store = <String, String>{kRuntimeDekWrappedKey: 'transient-blob'};
      var attempts = 0;

      final restored = await readCachedRuntimeDekForRestoreCore(
        aad: 'sync-1|device-1|1',
        readKey: (key) async => store[key],
        deleteKey: (key) async {
          store.remove(key);
        },
        writeKey: (key, value) async {
          store[key] = value;
        },
        unwrapDek: (_, _) async {
          attempts++;
          throw PlatformException(code: 'runtime_dek_wrap_transient');
        },
        wrapDek: (_, _) => throw StateError('should not wrap'),
      );

      expect(attempts, 2, reason: 'must retry once on transient');
      expect(restored, isNull);
      expect(
        store[kRuntimeDekWrappedKey],
        'transient-blob',
        reason: 'transient failure must NOT delete the cache',
      );
    });

    test(
      'terminal unwrap failure: returns null and DELETES wrapped cache',
      () async {
        final store = <String, String>{
          kRuntimeDekWrappedKey: 'unrecoverable-blob',
        };
        var attempts = 0;

        final restored = await readCachedRuntimeDekForRestoreCore(
          aad: 'sync-1|device-1|1',
          readKey: (key) async => store[key],
          deleteKey: (key) async {
            store.remove(key);
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          unwrapDek: (_, _) async {
            attempts++;
            throw PlatformException(code: 'runtime_dek_wrap_terminal');
          },
          wrapDek: (_, _) => throw StateError('should not wrap'),
        );

        expect(attempts, 1, reason: 'terminal must NOT retry');
        expect(restored, isNull);
        expect(
          store[kRuntimeDekWrappedKey],
          isNull,
          reason: 'terminal failure must delete the cache',
        );
      },
    );

    test('unknown / legacy unwrap failure: returns null and PRESERVES wrapped '
        'cache (conservative — preserve viable blobs)', () async {
      final store = <String, String>{
        kRuntimeDekWrappedKey: 'unclassified-blob',
      };
      var attempts = 0;

      final restored = await readCachedRuntimeDekForRestoreCore(
        aad: 'sync-1|device-1|1',
        readKey: (key) async => store[key],
        deleteKey: (key) async {
          store.remove(key);
        },
        writeKey: (key, value) async {
          store[key] = value;
        },
        unwrapDek: (_, _) async {
          attempts++;
          // Legacy code from older platform builds — no _terminal /
          // _transient suffix.
          throw PlatformException(code: 'runtime_dek_wrap_failed');
        },
        wrapDek: (_, _) => throw StateError('should not wrap'),
      );

      expect(
        attempts,
        1,
        reason: 'unknown classification must NOT retry (could be terminal)',
      );
      expect(restored, isNull);
      expect(
        store[kRuntimeDekWrappedKey],
        'unclassified-blob',
        reason:
            'unknown failure must preserve cache to avoid spurious '
            'eviction of a viable blob',
      );
    });

    test(
      'non-platform unwrap failure diagnostics do not include wrapped blob text',
      () async {
        final store = <String, String>{
          kRuntimeDekWrappedKey: 'WRAPPED-CIPHERTEXT-SHOULD-NOT-LEAK',
        };
        RuntimeDekUnwrapFailure? failure;

        final restored = await readCachedRuntimeDekForRestoreCore(
          aad: 'sync-1|device-1|1',
          readKey: (key) async => store[key],
          deleteKey: (key) async {
            store.remove(key);
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          unwrapDek: (_, _) async {
            throw const FormatException(
              'wrapped runtime DEK JSON was invalid',
              'WRAPPED-CIPHERTEXT-SHOULD-NOT-LEAK',
            );
          },
          wrapDek: (_, _) => throw StateError('should not wrap'),
          recordFailure: (value) => failure = value,
        );

        expect(restored, isNull);
        expect(store[kRuntimeDekWrappedKey], isNotNull);
        expect(failure?.errorMessage, 'wrapped runtime DEK JSON was invalid');
        expect(
          failure?.errorMessage,
          isNot(contains('WRAPPED-CIPHERTEXT-SHOULD-NOT-LEAK')),
        );
      },
    );

    test(
      'writeRuntimeDekCacheCore preserves existing wrapped cache on refresh failure',
      () async {
        final store = <String, String>{
          kRuntimeDekKey: 'legacy-raw-cache',
          kRuntimeDekWrappedKey: 'still-viable-wrapped-cache',
        };
        String? warning;

        await writeRuntimeDekCacheCore(
          dekBytes: Uint8List.fromList(List<int>.filled(32, 7)),
          aad: 'sync-1|device-1|1',
          wrapDek: (_, _) async {
            throw PlatformException(
              code: 'runtime_dek_wrap_transient',
              message: 'Secret Service unavailable',
            );
          },
          writeKey: (key, value) async {
            store[key] = value;
          },
          deleteKey: (key) async {
            store.remove(key);
          },
          reportWarning: (message, _, _) => warning = message,
        );

        expect(store[kRuntimeDekWrappedKey], 'still-viable-wrapped-cache');
        expect(store[kRuntimeDekKey], isNull);
        expect(
          warning,
          'Runtime DEK cache refresh failed; previous wrapped cache preserved.',
        );
      },
    );

    test(
      'classifyRuntimeDekUnwrapError: uppercase iOS codes also classify',
      () {
        expect(
          classifyRuntimeDekUnwrapError(
            PlatformException(code: 'RUNTIME_DEK_WRAP_TERMINAL'),
          ),
          RuntimeDekUnwrapClassification.terminal,
        );
        expect(
          classifyRuntimeDekUnwrapError(
            PlatformException(code: 'RUNTIME_DEK_WRAP_TRANSIENT'),
          ),
          RuntimeDekUnwrapClassification.transient,
        );
        expect(
          classifyRuntimeDekUnwrapError(
            PlatformException(code: 'RUNTIME_DEK_WRAP_FAILED'),
          ),
          RuntimeDekUnwrapClassification.unknown,
        );
        expect(
          classifyRuntimeDekUnwrapError(StateError('non-platform')),
          RuntimeDekUnwrapClassification.unknown,
        );
      },
    );
  });

  // --------------------------------------------------------------------
  // computeKeysToClearOnReset — the reset/revoke cleanup pipeline.
  // --------------------------------------------------------------------

  group('computeKeysToClearOnReset', () {
    test('returns empty when the keychain is empty (inclusion-by-prefix)', () {
      // After Phase 1B the helper is keychain-driven: it only returns keys
      // that actually exist. An empty keychain yields no work to do.
      final result = computeKeysToClearOnReset({});
      expect(result, isEmpty);
    });

    test('includes every prism_sync.* entry present in the keychain', () {
      final result = computeKeysToClearOnReset({
        'prism_sync.wrapped_dek': 'x',
        'prism_sync.bootstrap_joiner_bundle': 'b',
        'prism_sync.pending_sync_id': 'p',
        'prism_sync.registration_token': 'r',
        'prism_sync.runtime_dek': 'd',
        'prism_sync.runtime_dek_wrapped_v1': 'wrapped',
        kSnapshotApplyCompleteKey: 'applied',
        'prism_sync.epoch_key_1': 'key1',
        'prism_sync.epoch_key_42': 'key42',
        'prism_sync.runtime_keys_foo': 'runtime',
      });
      expect(result, contains('prism_sync.wrapped_dek'));
      // The transient pairing keys the v1 allow-list missed are now picked up.
      expect(result, contains('prism_sync.bootstrap_joiner_bundle'));
      expect(result, contains('prism_sync.pending_sync_id'));
      expect(result, contains('prism_sync.registration_token'));
      expect(result, contains('prism_sync.runtime_dek'));
      expect(result, contains(kRuntimeDekWrappedKey));
      expect(result, contains(kSnapshotApplyCompleteKey));
      expect(result, contains('prism_sync.epoch_key_1'));
      expect(result, contains('prism_sync.epoch_key_42'));
      expect(result, contains('prism_sync.runtime_keys_foo'));
    });

    test('preserves database-encryption slots in kProtectedFromReset', () {
      final result = computeKeysToClearOnReset({
        'prism_sync.wrapped_dek': 'x',
        'prism_sync.database_key': 'preserve',
        'prism_sync.database_key_staging': 'preserve',
        'prism_sync.sync_database_key': 'preserve',
        'prism_sync.sync_database_key_staging': 'preserve',
      });
      for (final protected in kProtectedFromReset) {
        expect(result, isNot(contains(protected)));
      }
      expect(result, contains('prism_sync.wrapped_dek'));
    });

    test('does not include entries from other app prefixes', () {
      final result = computeKeysToClearOnReset({
        'other.sync_id': 'foreign',
        'unrelated_key': 'foreign',
      });
      expect(result, isEmpty);
    });
  });

  // --------------------------------------------------------------------
  // Phase 4B — SyncHealthState.unpaired distinction
  //
  // The full `_autoConfigureIfReady` flow requires an FFI handle, which
  // pulls in the Rust runtime. We extract the keychain-classification
  // step into a pure helper (`classifyHealthFromKeychain`) and assert
  // its decisions here.
  // --------------------------------------------------------------------

  group('classifyHealthFromKeychain (Phase 4B)', () {
    test('returns unpaired when sync_id is missing', () {
      final result = classifyHealthFromKeychain(
        syncId: null,
        deviceId: 'abc123',
        deviceSecret: 'secret',
      );
      expect(result, SyncHealthState.unpaired);
    });

    test('returns unpaired when device_id is missing', () {
      final result = classifyHealthFromKeychain(
        syncId: 'sync-1',
        deviceId: null,
        deviceSecret: 'secret',
      );
      expect(result, SyncHealthState.unpaired);
    });

    test('returns unpaired when both are missing', () {
      final result = classifyHealthFromKeychain(
        syncId: null,
        deviceId: null,
        deviceSecret: null,
      );
      expect(result, SyncHealthState.unpaired);
    });

    test('returns unpaired when device_secret is missing', () {
      final result = classifyHealthFromKeychain(
        syncId: 'sync-1',
        deviceId: 'abc123',
        deviceSecret: null,
      );
      expect(result, SyncHealthState.unpaired);
    });

    test(
      'returns null (defer to runtime-keys path) when identity is complete',
      () {
        final result = classifyHealthFromKeychain(
          syncId: 'sync-1',
          deviceId: 'abc123',
          deviceSecret: 'secret',
        );
        expect(result, isNull);
      },
    );

    test('SyncHealthState enum still includes the prior three cases', () {
      // Regression guard: adding `unpaired` must not silently drop the
      // others (existing switch/match sites depend on them).
      expect(SyncHealthState.values, contains(SyncHealthState.healthy));
      expect(SyncHealthState.values, contains(SyncHealthState.needsPassword));
      expect(SyncHealthState.values, contains(SyncHealthState.disconnected));
      expect(SyncHealthState.values, contains(SyncHealthState.unpaired));
      expect(SyncHealthState.values, contains(SyncHealthState.needsRewrap));
    });
  });

  // --------------------------------------------------------------------
  // wrapped_dek pair-readiness probe (needsRewrap recovery)
  //
  // The classifier branch that flips `_autoConfigureIfReady`'s final
  // result from `healthy` to `needsRewrap` when `wrapped_dek` is missing
  // after a successful runtime DEK restore.
  // --------------------------------------------------------------------

  group('classifyPairReadinessFromWrappedDek', () {
    test('returns needsRewrap when wrapped_dek is null (missing slot)', () {
      expect(
        classifyPairReadinessFromWrappedDek(null),
        SyncHealthState.needsRewrap,
      );
    });

    test('returns needsRewrap when wrapped_dek is empty string', () {
      expect(
        classifyPairReadinessFromWrappedDek(''),
        SyncHealthState.needsRewrap,
      );
    });

    test('returns healthy when wrapped_dek is present', () {
      expect(
        classifyPairReadinessFromWrappedDek('base64-payload=='),
        SyncHealthState.healthy,
      );
    });
  });

  // --------------------------------------------------------------------
  // Phase 4C — `_handleDeviceRevokedFromAuthFailure` device_id self-check
  //
  // The full handler reaches into FFI / secure storage / providers; we
  // extract the wipe-decision into the pure helper `shouldWipeForRevokeEvent`
  // and assert its three branches here.
  // --------------------------------------------------------------------

  group('shouldWipeForRevokeEvent (Phase 4C)', () {
    test('wipes when own device_id matches the revoked id', () {
      expect(
        shouldWipeForRevokeEvent(
          revokedDeviceId: 'device-self',
          currentDeviceId: 'device-self',
        ),
        isTrue,
      );
    });

    test('does not wipe when revoked id targets a sibling', () {
      expect(
        shouldWipeForRevokeEvent(
          revokedDeviceId: 'device-sibling',
          currentDeviceId: 'device-self',
        ),
        isFalse,
      );
    });

    test('wipes when event has no device_id (legacy auth failure)', () {
      expect(
        shouldWipeForRevokeEvent(
          revokedDeviceId: null,
          currentDeviceId: 'device-self',
        ),
        isTrue,
      );
    });

    test('wipes when event device_id is empty string', () {
      expect(
        shouldWipeForRevokeEvent(
          revokedDeviceId: '',
          currentDeviceId: 'device-self',
        ),
        isTrue,
      );
    });

    test(
      'wipes when we cannot read our own device_id (assume self-target)',
      () {
        expect(
          shouldWipeForRevokeEvent(
            revokedDeviceId: 'device-anything',
            currentDeviceId: null,
          ),
          isTrue,
        );
      },
    );
  });

  // --------------------------------------------------------------------
  // The fronting migration startup gate must NOT fall through into the
  // old-group seed/configure path until the reset/re-pair cutover completes.
  // For `inProgress`, this also prevents `drainRustStore` from nuking
  // `prism_sync.sync_id` before `resumeCleanup()` can target clear_sync_state.
  // --------------------------------------------------------------------

  group('startupHealthForMigrationMode (pass-4 #B-PASS4-P1)', () {
    test('returns unpaired for known non-complete migration modes', () {
      // The fronting migration is a hard sync boundary: known states before
      // `complete` must not seed/configure the old sync group.
      for (final mode in const [
        'notStarted',
        'deferred',
        'upgradeAndKeep',
        'startFresh',
        'blocked',
        'inProgress',
      ]) {
        expect(
          startupHealthForMigrationMode(mode),
          SyncHealthState.unpaired,
          reason: mode,
        );
      }
    });

    test('returns null when the migration is already complete', () {
      expect(startupHealthForMigrationMode('complete'), isNull);
    });

    test('returns null for an unknown / null mode (fail open)', () {
      // Defensive: any unrecognized value (including null from a DAO
      // read failure) must fall through to the normal startup path
      // rather than silently locking the user into the cleanup screen.
      expect(startupHealthForMigrationMode(null), isNull);
      expect(startupHealthForMigrationMode(''), isNull);
      expect(startupHealthForMigrationMode('totally-unknown-mode'), isNull);
    });
  });

  group('applyDrainedEntries with empty entries (pass-4 #B-PASS4-P1)', () {
    // Regression guard for the underlying destructive behavior: if the
    // post-config block ever runs against an empty drain (the exact
    // condition produced by skipping `_seedRustStore` when the
    // migration is mid-cleanup), it would delete every static key —
    // including `prism_sync.sync_id`. The fix is to NOT call into
    // `applyDrainedEntries` from the in-progress gate; this test
    // demonstrates *why* by pinning the destructive behavior.
    test('deletes prism_sync.sync_id when entries map is empty', () async {
      final deleted = <String>[];
      final written = <String, String>{};

      final committed = await applyDrainedEntries(
        entries: const <String, String>{}, // empty: never-seeded engine
        deleteKey: (full) async {
          deleted.add(full);
        },
        writeKey: (full, value) async {
          written[full] = value;
        },
      );

      expect(committed, 0);
      // `prism_sync.sync_id` is in the static `_secureStoreKeys`
      // allow-list, so an empty drain wipes it. This is the exact
      // mechanism by which the pre-fix in-progress gate corrupted the
      // keychain.
      expect(deleted, contains('prism_sync.sync_id'));
      expect(written, isEmpty);
    });

    test(
      'preserves prism_sync.sync_id when the drained entries echo it back',
      () async {
        // Sanity check: when Rust IS seeded and reports sync_id back,
        // the helper writes it (and does not also delete it) — proving
        // the destructive path above is uniquely the empty-drain case.
        final deleted = <String>[];
        final written = <String, String>{};

        await applyDrainedEntries(
          entries: const <String, String>{'sync_id': 'c3luYzE='},
          deleteKey: (full) async {
            deleted.add(full);
          },
          writeKey: (full, value) async {
            written[full] = value;
          },
        );

        expect(deleted, isNot(contains('prism_sync.sync_id')));
        expect(written['prism_sync.sync_id'], 'c3luYzE=');
      },
    );

    test('writes startup gate keys after device identity keys', () async {
      final written = <String>[];

      await applyDrainedEntries(
        entries: const <String, String>{
          'sync_id': 'c3luYzE=',
          'relay_url': 'aHR0cHM6Ly9yZWxheQ==',
          'device_id': 'ZGV2aWNl',
          'device_secret': 'c2VjcmV0',
          'wrapped_dek': 'd3JhcA==',
        },
        deleteKey: (_) async {},
        writeKey: (full, _) async {
          written.add(full);
        },
      );

      expect(
        written.indexOf('prism_sync.device_id'),
        lessThan(written.indexOf('prism_sync.sync_id')),
      );
      expect(
        written.indexOf('prism_sync.device_secret'),
        lessThan(written.indexOf('prism_sync.relay_url')),
      );
    });
  });

  // --------------------------------------------------------------------
  // applyDrainedEntriesWithSnapshotRollback — Block 6a of the Android
  // sync remediation. The setup-only drain mirror restores a
  // caller-owned snapshot if a delete or write throws mid-loop.
  //
  // Critical invariants:
  //   1. Diagnostic re-throw names the failed key + phase.
  //   2. Keychain is restored EXACTLY to the pre-write snapshot.
  //   3. `kProtectedFromReset` is never deleted or overwritten.
  //
  // Tests use injectable callbacks (a small in-memory map) instead of
  // FlutterSecureStorage so the failure-injection seams are local.
  // --------------------------------------------------------------------
  group('applyDrainedEntriesWithSnapshotRollback (Block 6a)', () {
    // Helper: build the four canonical callbacks from a backing map +
    // an optional throw-injector keyed off the call number.
    ({
      Future<void> Function(String) deleteKey,
      Future<void> Function(String, String) writeKey,
      Future<Map<String, String>> Function() readCurrentNamespace,
    })
    storageOps(
      Map<String, String> storage, {
      int? throwOnDeleteCall,
      int? throwOnWriteCall,
    }) {
      var deleteCalls = 0;
      var writeCalls = 0;
      return (
        deleteKey: (key) async {
          deleteCalls++;
          if (deleteCalls == throwOnDeleteCall) {
            throw StateError('injected delete failure on call $deleteCalls');
          }
          storage.remove(key);
        },
        writeKey: (key, value) async {
          writeCalls++;
          if (writeCalls == throwOnWriteCall) {
            throw StateError('injected write failure on call $writeCalls');
          }
          storage[key] = value;
        },
        readCurrentNamespace: () async => Map<String, String>.from(storage),
      );
    }

    test(
      'setup drain — write failure mid-loop restores keychain to snapshot',
      () async {
        // Pre-setup snapshot — different keys than what the drain will write.
        // Includes one protected DB-key slot to prove rollback never touches it.
        final snapshot = <String, String>{
          'prism_sync.relay_url': 'snapshot-relay-url',
          'prism_sync.session_token': 'snapshot-session-token',
        };

        // Live keychain: starts as snapshot + protected slots.
        final storage = <String, String>{
          ...snapshot,
          'prism_sync.database_key': 'PROTECTED-db-key',
          'prism_sync.database_key_staging': 'PROTECTED-db-key-staging',
          'prism_sync.sync_database_key': 'PROTECTED-sync-db-key',
          'prism_sync.sync_database_key_staging':
              'PROTECTED-sync-db-key-staging',
        };

        // Drained entries — what the new identity would look like.
        // Five entries; sort key (`device_id`, `device_secret`, `wrapped_dek`,
        // `dek_salt` are priority 0; `sync_id`, `relay_url` priority 2),
        // so the 4th write lands on a priority-0 key (one of the four).
        final entries = <String, String>{
          'device_id': 'new-device-id',
          'device_secret': 'new-device-secret',
          'wrapped_dek': 'new-wrapped-dek',
          'dek_salt': 'new-dek-salt',
          'sync_id': 'new-sync-id',
          'relay_url': 'new-relay-url',
        };

        final ops = storageOps(storage, throwOnWriteCall: 4);

        Object? caught;
        StackTrace? caughtStack;
        try {
          await applyDrainedEntriesWithSnapshotRollback(
            entries: entries,
            rollbackSnapshot: snapshot,
            deleteKey: ops.deleteKey,
            writeKey: ops.writeKey,
            readCurrentNamespace: ops.readCurrentNamespace,
          );
        } catch (e, st) {
          caught = e;
          caughtStack = st;
        }

        expect(caught, isA<DrainPartialWriteException>());
        final err = caught as DrainPartialWriteException;
        expect(err.phase, DrainPartialWritePhase.write);
        expect(err.failedKey, startsWith('prism_sync.'));
        expect(err.cause, isA<StateError>());
        expect(caughtStack, isNotNull);

        // Keychain restored EXACTLY to snapshot + untouched protected slots.
        expect(storage, {
          'prism_sync.relay_url': 'snapshot-relay-url',
          'prism_sync.session_token': 'snapshot-session-token',
          'prism_sync.database_key': 'PROTECTED-db-key',
          'prism_sync.database_key_staging': 'PROTECTED-db-key-staging',
          'prism_sync.sync_database_key': 'PROTECTED-sync-db-key',
          'prism_sync.sync_database_key_staging':
              'PROTECTED-sync-db-key-staging',
        });
      },
    );

    test(
      'setup drain — delete-phase failure restores keychain to snapshot',
      () async {
        // Snapshot has some pre-existing identity; drained entries are empty
        // for the keys that Phase 1 would delete, so Phase 1 actually runs.
        final snapshot = <String, String>{
          'prism_sync.relay_url': 'snapshot-relay',
          'prism_sync.sync_id': 'snapshot-sync-id',
        };
        final storage = <String, String>{
          ...snapshot,
          // A stale static key Phase 1 will try to delete.
          'prism_sync.wrapped_dek': 'stale-wrapped',
          'prism_sync.dek_salt': 'stale-salt',
          // Protected slots — must survive rollback.
          'prism_sync.database_key': 'PROTECTED-db-key',
          'prism_sync.sync_database_key': 'PROTECTED-sync-db-key',
        };

        // Empty drained entries — Phase 1 will iterate over every static
        // key and try to delete it.
        final entries = <String, String>{};

        final ops = storageOps(storage, throwOnDeleteCall: 2);

        Object? caught;
        try {
          await applyDrainedEntriesWithSnapshotRollback(
            entries: entries,
            rollbackSnapshot: snapshot,
            deleteKey: ops.deleteKey,
            writeKey: ops.writeKey,
            readCurrentNamespace: ops.readCurrentNamespace,
          );
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<DrainPartialWriteException>());
        final err = caught as DrainPartialWriteException;
        expect(err.phase, DrainPartialWritePhase.delete);
        expect(err.failedKey, startsWith('prism_sync.'));

        // Snapshot is restored, protected keys untouched, and stale
        // entries that Phase 1 had already deleted before the throw are
        // re-removed by the rollback's namespace scan.
        expect(storage['prism_sync.relay_url'], 'snapshot-relay');
        expect(storage['prism_sync.sync_id'], 'snapshot-sync-id');
        expect(storage['prism_sync.database_key'], 'PROTECTED-db-key');
        expect(storage['prism_sync.sync_database_key'], 'PROTECTED-sync-db-key');
        // No stale non-snapshot non-protected keys left over.
        for (final key in storage.keys) {
          final isProtected = kProtectedFromReset.contains(key);
          final isSnapshot = snapshot.containsKey(key);
          expect(
            isProtected || isSnapshot,
            isTrue,
            reason: 'unexpected leftover key after rollback: $key',
          );
        }
      },
    );

    test(
      'post-config drain (no snapshot) preserves committed writes on failure',
      () async {
        // The non-rollback API: a thrown write must propagate, but already
        // committed writes stay (no destructive cleanup) and the Phase 1
        // deletes that already ran are not re-resurrected.
        final storage = <String, String>{
          // Pre-existing keys — represents valid credentials from a
          // prior successful drain. Some are in the static allow-list,
          // some are dynamic (e.g. epoch_key_*) and Phase 1 won't touch
          // them.
          'prism_sync.epoch_key_3': 'prior-epoch-key',
        };

        final entries = <String, String>{
          'device_id': 'commit-device-id',
          'device_secret': 'commit-device-secret',
          'wrapped_dek': 'commit-wrapped-dek',
          'dek_salt': 'commit-dek-salt',
          'sync_id': 'commit-sync-id',
        };

        var writeCalls = 0;
        final deleted = <String>[];

        Object? caught;
        try {
          await applyDrainedEntries(
            entries: entries,
            deleteKey: (key) async {
              deleted.add(key);
              storage.remove(key);
            },
            writeKey: (key, value) async {
              writeCalls++;
              if (writeCalls == 3) {
                throw StateError('injected write failure');
              }
              storage[key] = value;
            },
          );
        } catch (e) {
          caught = e;
        }

        // Existing behavior preserved: applyDrainedEntries propagates the
        // raw storage error (NOT a DrainPartialWriteException).
        expect(caught, isA<StateError>());
        expect(caught, isNot(isA<DrainPartialWriteException>()));

        // The first two writes committed and remain.
        expect(writeCalls, 3);
        // The two committed entries are still in storage.
        final committedEntries = storage.entries
            .where((e) => e.value.startsWith('commit-'))
            .toList();
        expect(committedEntries, hasLength(2));
        // The pre-existing dynamic key was untouched (not in
        // _secureStoreKeys, so Phase 1 didn't see it).
        expect(storage['prism_sync.epoch_key_3'], 'prior-epoch-key');
      },
    );

    test(
      'rollback never deletes or overwrites kProtectedFromReset slots',
      () async {
        // All four protected slots in the snapshot AND in storage with
        // distinct values to prove "never touched" includes "never
        // restored from snapshot."
        const protectedValues = <String, String>{
          'prism_sync.database_key': 'live-db-key',
          'prism_sync.database_key_staging': 'live-db-key-staging',
          'prism_sync.sync_database_key': 'live-sync-db-key',
          'prism_sync.sync_database_key_staging': 'live-sync-db-key-staging',
        };
        // Snapshot deliberately holds DIFFERENT values for the same
        // protected keys. If rollback honored them, the storage values
        // would change. They must not.
        final snapshot = <String, String>{
          'prism_sync.database_key': 'SNAPSHOT-db-key',
          'prism_sync.database_key_staging': 'SNAPSHOT-db-key-staging',
          'prism_sync.sync_database_key': 'SNAPSHOT-sync-db-key',
          'prism_sync.sync_database_key_staging': 'SNAPSHOT-sync-db-key-staging',
          // A non-protected snapshot entry to prove rollback DOES restore
          // those.
          'prism_sync.relay_url': 'snapshot-relay',
        };
        final storage = <String, String>{
          ...protectedValues,
          // Pre-existing non-protected non-snapshot key — rollback should
          // delete this.
          'prism_sync.session_token': 'stale-session-token',
        };

        final entries = <String, String>{
          'device_id': 'new-device-id',
          'device_secret': 'new-device-secret',
        };

        final ops = storageOps(storage, throwOnWriteCall: 1);

        Object? caught;
        try {
          await applyDrainedEntriesWithSnapshotRollback(
            entries: entries,
            rollbackSnapshot: snapshot,
            deleteKey: ops.deleteKey,
            writeKey: ops.writeKey,
            readCurrentNamespace: ops.readCurrentNamespace,
          );
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<DrainPartialWriteException>());

        // Every protected slot still holds its LIVE value, not the
        // snapshot's bogus value.
        for (final entry in protectedValues.entries) {
          expect(
            storage[entry.key],
            entry.value,
            reason: 'protected slot ${entry.key} was modified by rollback',
          );
        }
        // Non-protected snapshot entries WERE restored.
        expect(storage['prism_sync.relay_url'], 'snapshot-relay');
        // Stale non-snapshot non-protected keys were cleared.
        expect(storage.containsKey('prism_sync.session_token'), isFalse);
      },
    );

    test(
      'rollback namespace scan failure falls back to attempted-keys + '
      'static allowlist delete and reports a warning',
      () async {
        // Reproduces a realistic Android keystore failure: Phase 2 throws
        // mid-write AND `readCurrentNamespace()` (the post-failure scan
        // used by the rollback to discover leftover keys to delete) also
        // throws. Without the fallback, the rollback would only restore
        // snapshot entries — leaving the post-Phase-1 + post-partial-Phase-2
        // leftover keys in the keychain.
        ErrorReportingService.instance.clear();

        // Snapshot is non-empty — proves the rollback still restores
        // those entries even when the namespace scan fails.
        final snapshot = <String, String>{
          'prism_sync.relay_url': 'snapshot-relay-url',
        };

        // Storage contains the snapshot, the protected DB slot, plus a
        // stale identity key that Phase 1 should re-delete on rollback.
        final storage = <String, String>{
          ...snapshot,
          'prism_sync.session_token': 'leftover-token',
          'prism_sync.database_key': 'PROTECTED-db-key',
        };

        // Drained entries — the post-Phase-2 leftover will be the first
        // priority-0 write that succeeded before the throw.
        final entries = <String, String>{
          'device_id': 'new-device-id',
          'device_secret': 'new-device-secret',
          'wrapped_dek': 'new-wrapped-dek',
        };

        var deleteCalls = 0;
        var writeCalls = 0;

        Object? caught;
        try {
          await applyDrainedEntriesWithSnapshotRollback(
            entries: entries,
            rollbackSnapshot: snapshot,
            deleteKey: (key) async {
              deleteCalls++;
              storage.remove(key);
            },
            writeKey: (key, value) async {
              writeCalls++;
              if (writeCalls == 2) {
                throw StateError('injected write failure');
              }
              storage[key] = value;
            },
            // Inject the Android keystore failure on the rollback's
            // namespace scan.
            readCurrentNamespace: () async {
              throw StateError('injected readAll failure during rollback');
            },
          );
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<DrainPartialWriteException>());

        // The fallback path attempted to delete:
        //   - keys we tried to mutate during this drain (the Phase-2
        //     writes, including the one that committed before the throw)
        //     that aren't in the snapshot
        //   - keys in the static `_secureStoreKeys` allow-list that
        //     aren't in the snapshot
        // None of those are in the snapshot, so the storage should end
        // up snapshot-only (plus untouched protected slots).
        for (final key in entries.keys) {
          expect(
            storage.containsKey('prism_sync.$key'),
            isFalse,
            reason:
                'attempted-write key $key should be deleted by the '
                'fallback rollback even when readCurrentNamespace throws',
          );
        }
        // The pre-existing stale `session_token` is in `_secureStoreKeys`,
        // so the static-allowlist fallback delete catches it too.
        expect(storage.containsKey('prism_sync.session_token'), isFalse);

        // Snapshot was restored verbatim.
        expect(storage['prism_sync.relay_url'], 'snapshot-relay-url');
        // Protected slot untouched.
        expect(storage['prism_sync.database_key'], 'PROTECTED-db-key');

        // Deletes ran: Phase 1 delete sweep + the fallback deletes.
        expect(deleteCalls, greaterThan(0));

        // ErrorReportingService captured the namespace-scan failure as
        // a warning so diagnostics can flag the degraded restore.
        final scanWarnings = ErrorReportingService.instance.errors
            .where(
              (e) =>
                  e.severity == ErrorSeverity.warning &&
                  e.message.contains('rollback namespace scan failed'),
            )
            .toList();
        expect(
          scanWarnings,
          isNotEmpty,
          reason:
              'rollback must surface a warning when the namespace scan '
              'fails so the degraded exactness guarantee is observable',
        );
      },
    );

    test(
      'snapshot values containing non-ASCII bytes round-trip byte-identical',
      () async {
        // The snapshot stores already-base64 strings (whatever
        // `readPrefixed`/`readAll` returned). The drain emits bytes,
        // base64-encodes via `encodeDrainedEntries`, and writes the
        // base64 string. The rollback restore path MUST write the
        // snapshot's already-base64 strings VERBATIM — no re-encoding,
        // no transcoding. This pins the contract for callers like the
        // initiator setup that store raw 32-byte secrets.
        ErrorReportingService.instance.clear();

        // Construct a base64 string of a value with non-ASCII bytes
        // (e.g. a raw 32-byte device_secret).
        final secretBytes = Uint8List.fromList(
          List<int>.generate(32, (i) => (i * 7 + 0xC0) & 0xFF),
        );
        final snapshotBase64 = base64Encode(secretBytes);
        // Sanity: contains bytes outside printable ASCII once decoded.
        expect(secretBytes.any((b) => b >= 0x80), isTrue);

        final snapshot = <String, String>{
          'prism_sync.device_secret': snapshotBase64,
        };

        // Storage starts empty (or with something else); we want the
        // rollback path to restore the snapshot's exact bytes.
        final storage = <String, String>{};

        // Force the rollback path: a write throws on the first attempt.
        final entries = <String, String>{
          'device_id': base64Encode(utf8.encode('new-device-id')),
          'device_secret': base64Encode(utf8.encode('new-device-secret')),
        };

        var writeCalls = 0;

        Object? caught;
        try {
          await applyDrainedEntriesWithSnapshotRollback(
            entries: entries,
            rollbackSnapshot: snapshot,
            deleteKey: (key) async => storage.remove(key),
            writeKey: (key, value) async {
              writeCalls++;
              // Throw on the FIRST drained write so the rollback
              // restore path fires. The restore writes use the same
              // writeKey callback, so the counter trips only once.
              if (writeCalls == 1) {
                throw StateError('injected write failure (force rollback)');
              }
              storage[key] = value;
            },
            readCurrentNamespace: () async =>
                Map<String, String>.from(storage),
          );
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<DrainPartialWriteException>());

        // The restored value is byte-identical to the snapshot value.
        expect(
          storage['prism_sync.device_secret'],
          snapshotBase64,
          reason:
              'rollback restore must write snapshot values verbatim — '
              'any double-encoding or transcoding would change the '
              'base64 string, which decodes back to a different byte '
              'sequence.',
        );
        // Decode and compare bytes for an extra layer of confidence
        // that no transcoding happened end-to-end.
        expect(
          base64Decode(storage['prism_sync.device_secret']!),
          orderedEquals(secretBytes),
        );
      },
    );
  });

  // --------------------------------------------------------------------
  // wipeFrontingMigrationSyncKeychain — Workstream 2 step 4
  // (remediation-plan-2026-04-30): the migration's wipe pass must
  // consume `_secureStoreKeys` and `_dynamicSecureStorePrefixes` instead
  // of inlining the list. We expose the static-key set + dynamic prefix
  // list via two `@visibleForTesting` helpers so the contract is pinned.
  // --------------------------------------------------------------------
  group('frontingMigrationWipeStaticKeys', () {
    test('includes every key in the seed allow-list', () {
      // Anything seeded into Rust must also be wiped on migration cutover —
      // otherwise the next launch re-seeds an old DEK / sync_id and the
      // device silently re-attaches to the previous sync group.
      final keys = frontingMigrationWipeStaticKeys();
      expect(
        keys,
        containsAll(const <String>[
          'wrapped_dek',
          'dek_salt',
          'device_secret',
          'device_id',
          'sync_id',
          'session_token',
          'epoch',
          'relay_url',
          'registration_token',
          'setup_rollback_marker',
          'sharing_prekey_store',
          'sharing_id_cache',
          'min_signature_version_floor',
        ]),
      );
    });

    test(
      'includes wipe-only legacy slots not present in the seed allow-list',
      () {
        // `mnemonic` was sometimes persisted by older builds. Runtime DEK
        // cache slots are not seed material, but must be wiped on reset.
        final keys = frontingMigrationWipeStaticKeys();
        expect(keys, contains('mnemonic'));
        expect(keys, contains('runtime_dek'));
        expect(keys, contains('runtime_dek_wrapped_v1'));
        expect(keys, contains('runtime_dek_linux_wrap_key_v1'));
        expect(keys, contains('snapshot_apply_complete_v1'));
      },
    );
  });

  group('frontingMigrationWipeDynamicPrefixes', () {
    test('matches the seed-side dynamic prefix list', () {
      // The wipe path must scan the same dynamic prefixes the seed path
      // scans — otherwise an `epoch_key_1` left behind by a prior pairing
      // gets re-seeded into Rust on the next launch. `computeSeedEntries`
      // already pins `epoch_key_*` and `runtime_keys_*` as the dynamic
      // prefix set; the wipe helper must mirror it.
      final prefixes = frontingMigrationWipeDynamicPrefixes();
      expect(
        prefixes,
        containsAll(const <String>['epoch_key_', 'runtime_keys_']),
      );
    });
  });

  // --------------------------------------------------------------------
  // wipeSyncKeychainNamespace — Block 9 of the Android sync remediation.
  //
  // Both `_resetSyncSystem` (settings reset) and `_cleanupKeychainOnFailure`
  // (failed pairing) now go through this helper. Static cleanup lists were
  // drifting away from the keychain's real `prism_sync.*` contents — these
  // tests pin the union semantics and the runtime-DEK split between the two
  // call sites.
  // --------------------------------------------------------------------
  group('wipeSyncKeychainNamespace', () {
    Map<String, String> seed() => {
      'prism_sync.epoch_key_7': 'EPOCH7',
      'prism_sync.pending_sync_id': 'PENDING',
      'prism_sync.wrapped_dek': 'WRAPPED',
      // DB-encryption slots that must survive every wipe.
      'prism_sync.database_key': 'KEEP1',
      'prism_sync.database_key_staging': 'KEEP2',
      'prism_sync.sync_database_key': 'KEEP3',
      'prism_sync.sync_database_key_staging': 'KEEP4',
      // Foreign-prefixed key — never touched.
      'other_app.something': 'FOREIGN',
    };

    test('deletes unknown dynamic keys via the prefix scan', () async {
      final store = seed();
      final deleted = await wipeSyncKeychainNamespace(
        readAll: () async => Map<String, String>.from(store),
        deleteKey: (key) async {
          store.remove(key);
        },
      );

      expect(store.containsKey('prism_sync.epoch_key_7'), isFalse);
      expect(store.containsKey('prism_sync.pending_sync_id'), isFalse);
      expect(store.containsKey('prism_sync.wrapped_dek'), isFalse);
      expect(deleted, greaterThanOrEqualTo(3));
    });

    test('preserves every kProtectedFromReset key', () async {
      final store = {
        'prism_sync.database_key': 'KEEP1',
        'prism_sync.database_key_staging': 'KEEP2',
        'prism_sync.sync_database_key': 'KEEP3',
        'prism_sync.sync_database_key_staging': 'KEEP4',
        'prism_sync.wrapped_dek': 'WIPE',
      };

      await wipeSyncKeychainNamespace(
        readAll: () async => Map<String, String>.from(store),
        deleteKey: (key) async {
          store.remove(key);
        },
      );

      for (final protectedKey in kProtectedFromReset) {
        expect(
          store[protectedKey],
          isNotNull,
          reason:
              '$protectedKey is in kProtectedFromReset and must survive '
              'every wipeSyncKeychainNamespace call',
        );
      }
      expect(store.containsKey('prism_sync.wrapped_dek'), isFalse);
    });

    test('does not touch entries outside the prism_sync.* namespace', () async {
      final store = seed();
      await wipeSyncKeychainNamespace(
        readAll: () async => Map<String, String>.from(store),
        deleteKey: (key) async {
          store.remove(key);
        },
      );

      expect(store['other_app.something'], 'FOREIGN');
    });

    test('falls back to the static wipe list when readAll() throws', () async {
      // Seed every static-fallback key so we can verify each is targeted by
      // the fallback path, plus a protected key that must still survive.
      final store = <String, String>{
        for (final key in frontingMigrationWipeStaticKeys())
          'prism_sync.$key': 'WIPE-$key',
        'prism_sync.database_key': 'KEEP',
      };

      final deleted = await wipeSyncKeychainNamespace(
        readAll: () async => throw StateError('readAll unavailable'),
        deleteKey: (key) async {
          store.remove(key);
        },
      );

      // Every non-protected static key must be deleted by the fallback path.
      for (final bareKey in frontingMigrationWipeStaticKeys()) {
        final fullKey = 'prism_sync.$bareKey';
        if (kProtectedFromReset.contains(fullKey)) continue;
        expect(
          store.containsKey(fullKey),
          isFalse,
          reason:
              '$fullKey is in the static fallback list and must be deleted '
              'when readAll() fails',
        );
      }
      // Protected slot survives even via the fallback list.
      expect(store['prism_sync.database_key'], 'KEEP');
      expect(deleted, greaterThan(0));
    });

    test(
      'includeRuntimeDekWrappingKey: true triggers the wrapping-key delete',
      () async {
        final store = <String, String>{};
        var wrappingKeyDeleteCount = 0;

        await wipeSyncKeychainNamespace(
          readAll: () async => store,
          deleteKey: (key) async {
            store.remove(key);
          },
          includeRuntimeDekWrappingKey: true,
          deleteWrappingKey: () async {
            wrappingKeyDeleteCount++;
          },
        );

        expect(wrappingKeyDeleteCount, 1);
      },
    );

    test(
      'includeRuntimeDekWrappingKey: false leaves the wrapping key alone',
      () async {
        final store = <String, String>{};
        var wrappingKeyDeleteCount = 0;

        await wipeSyncKeychainNamespace(
          readAll: () async => store,
          deleteKey: (key) async {
            store.remove(key);
          },
          includeRuntimeDekWrappingKey: false,
          deleteWrappingKey: () async {
            wrappingKeyDeleteCount++;
          },
        );

        expect(wrappingKeyDeleteCount, 0);
      },
    );

    test('swallows individual deleteKey failures and continues', () async {
      final store = <String, String>{
        'prism_sync.wrapped_dek': 'a',
        'prism_sync.epoch_key_1': 'b',
        'prism_sync.pending_sync_id': 'c',
      };
      final logs = <String>[];

      await wipeSyncKeychainNamespace(
        readAll: () async => Map<String, String>.from(store),
        deleteKey: (key) async {
          if (key == 'prism_sync.epoch_key_1') {
            throw StateError('simulated delete failure');
          }
          store.remove(key);
        },
        log: logs.add,
      );

      // Other keys still got deleted; the failing key remains and was logged.
      expect(store.containsKey('prism_sync.wrapped_dek'), isFalse);
      expect(store.containsKey('prism_sync.pending_sync_id'), isFalse);
      expect(store.containsKey('prism_sync.epoch_key_1'), isTrue);
      expect(logs.any((m) => m.contains('prism_sync.epoch_key_1')), isTrue);
    });

    test(
      'swallows wrapping-key delete failure when '
      'includeRuntimeDekWrappingKey: true',
      () async {
        final store = <String, String>{};
        final logs = <String>[];

        // Must complete without throwing even though deleteWrappingKey threw.
        await wipeSyncKeychainNamespace(
          readAll: () async => store,
          deleteKey: (key) async {
            store.remove(key);
          },
          includeRuntimeDekWrappingKey: true,
          deleteWrappingKey: () async {
            throw StateError('keystore unavailable');
          },
          log: logs.add,
        );

        expect(logs.any((m) => m.contains('Runtime DEK wrapping-key')), isTrue);
      },
    );
  });
}
