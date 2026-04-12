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
    test('includes all static allow-list keys even when keychain is empty',
        () {
      final result = computeKeysToClearOnReset({});
      expect(result, contains('prism_sync.wrapped_dek'));
      expect(result, contains('prism_sync.dek_salt'));
      expect(result, contains('prism_sync.device_secret'));
      expect(result, contains('prism_sync.device_id'));
      expect(result, contains('prism_sync.sync_id'));
      expect(result, contains('prism_sync.session_token'));
      expect(result, contains('prism_sync.epoch'));
      expect(result, contains('prism_sync.relay_url'));
      expect(result, contains('prism_sync.mnemonic'));
      expect(result, contains('prism_sync.runtime_dek'));
    });

    test('reset deletes epoch_key_* prefix entries', () {
      final result = computeKeysToClearOnReset({
        'prism_sync.wrapped_dek': 'x',
        'prism_sync.epoch_key_1': 'key1',
        'prism_sync.epoch_key_42': 'key42',
        'prism_sync.runtime_keys_foo': 'runtime',
      });
      expect(result, contains('prism_sync.epoch_key_1'));
      expect(result, contains('prism_sync.epoch_key_42'));
      expect(result, contains('prism_sync.runtime_keys_foo'));
    });

    test('does not include entries from other app prefixes', () {
      final result = computeKeysToClearOnReset({
        'other.sync_id': 'foreign',
      });
      expect(result, isNot(contains('other.sync_id')));
    });
  });
}
