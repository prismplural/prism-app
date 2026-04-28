import 'package:flutter_test/flutter_test.dart';
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
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, previousSyncAt);
    expect(next.lastError, 'push rejected by relay');
    expect(next.pendingOps, 2);
  });

  test('syncStatusAfterCompleted records a new sync time on success', () {
    final completedAt = DateTime.utc(2026, 3, 18, 12, 5, 0);

    final next = syncStatusAfterCompleted(
      previous: const SyncStatus(isSyncing: true, lastError: 'old error'),
      rawResultError: null,
      pendingOps: 0,
      hasQuarantinedItems: true,
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
      completedAt: completedAt,
    );

    expect(next.isSyncing, isFalse);
    expect(next.lastSyncAt, completedAt);
    expect(next.lastError, isNull);
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
      });
      expect(result['wrapped_dek'], 'aW==');
      expect(result['device_id'], 'ZGV2aWNlMQ==');
      expect(result['sync_id'], 'c3luYzE=');
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
      final result = computeSeedEntries({
        'prism_sync.unknown_key': 'bogus',
      });
      expect(result, isEmpty);
    });
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
      );
      expect(result, SyncHealthState.unpaired);
    });

    test('returns unpaired when device_id is missing', () {
      final result = classifyHealthFromKeychain(
        syncId: 'sync-1',
        deviceId: null,
      );
      expect(result, SyncHealthState.unpaired);
    });

    test('returns unpaired when both are missing', () {
      final result = classifyHealthFromKeychain(
        syncId: null,
        deviceId: null,
      );
      expect(result, SyncHealthState.unpaired);
    });

    test('returns null (defer to runtime-keys path) when both present', () {
      final result = classifyHealthFromKeychain(
        syncId: 'sync-1',
        deviceId: 'abc123',
      );
      expect(result, isNull);
    });

    test('SyncHealthState enum still includes the prior three cases', () {
      // Regression guard: adding `unpaired` must not silently drop the
      // others (existing switch/match sites depend on them).
      expect(SyncHealthState.values, contains(SyncHealthState.healthy));
      expect(SyncHealthState.values, contains(SyncHealthState.needsPassword));
      expect(SyncHealthState.values, contains(SyncHealthState.disconnected));
      expect(SyncHealthState.values, contains(SyncHealthState.unpaired));
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
}
