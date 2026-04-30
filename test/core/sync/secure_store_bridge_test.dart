import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';

/// End-to-end tests for the Dart-side secure-store bridge.
///
/// Appendix B.8 of the 2026-04-11 sync robustness plan requires a
/// Dart-side proof that `_seedRustStore` reads dynamic `epoch_key_*` and
/// `runtime_keys_*` entries from `FlutterSecureStorage.readAll()` and
/// forwards them to `ffi.seedSecureStore`. Since `_seedRustStore` takes
/// an FFI handle that can't be constructed in a unit test, we test the
/// pure `buildSeedRequestJson` that `_seedRustStore` now delegates to.
/// Together with the round-trip test in `basic_ffi.rs`, this closes the
/// cross-language seed/drain symmetry gap.
void main() {
  group('buildSeedRequestJson', () {
    test('returns null for empty keychain (nothing to seed)', () {
      expect(buildSeedRequestJson(const {}), isNull);
    });

    test('returns null when the keychain only has unrelated entries', () {
      final result = buildSeedRequestJson({
        'other_app.whatever': 'x',
        'prism_sync.unknown_key_not_dynamic': 'y',
      });
      expect(result, isNull);
    });

    test('seed_then_drain_preserves_dynamic_epoch_keys_end_to_end', () {
      // Simulates: app previously wrote these entries to the keychain
      // across several sync cycles (including an epoch rotation that
      // recovered `epoch_key_1` and `epoch_key_2`, plus a runtime blob),
      // then restarts and calls `_seedRustStore`. The JSON passed to
      // Rust must contain every dynamic key.
      final json = buildSeedRequestJson({
        'prism_sync.wrapped_dek': 'd3JhcHBlZA==',
        'prism_sync.device_id': 'ZGV2aWNlLWFiYw==',
        'prism_sync.sync_id': 'c3luYy1hYmM=',
        'prism_sync.epoch_key_1': 'ZXBvY2gxa2V5',
        'prism_sync.epoch_key_2': 'ZXBvY2gya2V5',
        'prism_sync.runtime_keys_foo': 'Zm9vcnVudGltZQ==',
      });

      expect(json, isNotNull, reason: 'must emit a non-null JSON blob');
      final decoded = jsonDecode(json!) as Map<String, dynamic>;

      // Static allow-list keys survive.
      expect(decoded['wrapped_dek'], 'd3JhcHBlZA==');
      expect(decoded['device_id'], 'ZGV2aWNlLWFiYw==');
      expect(decoded['sync_id'], 'c3luYy1hYmM=');

      // Dynamic prefix scan picks up epoch + runtime keys.
      expect(
        decoded['epoch_key_1'],
        'ZXBvY2gxa2V5',
        reason: 'seed must carry epoch_key_1 from readAll()',
      );
      expect(
        decoded['epoch_key_2'],
        'ZXBvY2gya2V5',
        reason: 'seed must carry epoch_key_2 from readAll()',
      );
      expect(
        decoded['runtime_keys_foo'],
        'Zm9vcnVudGltZQ==',
        reason: 'seed must carry runtime_keys_foo from readAll()',
      );
    });

    test('out-of-range epoch keys (epoch > cached epoch) still propagate', () {
      // Regression case: the old allow-list path would only export
      // `epoch_key_1..=current_epoch`. With the snapshot-based drain AND
      // the dynamic-prefix seed scan, any `epoch_key_N` in the keychain
      // is picked up regardless of what the current epoch counter says.
      final json = buildSeedRequestJson({
        'prism_sync.epoch': 'MQ==', // epoch counter = 1
        'prism_sync.epoch_key_17': 'a2V5MTc=', // far beyond the counter
      });
      expect(json, isNotNull);
      final decoded = jsonDecode(json!) as Map<String, dynamic>;
      expect(decoded['epoch_key_17'], 'a2V5MTc=');
    });

    test('ignores foreign-prefixed entries (other_app.*)', () {
      final json = buildSeedRequestJson({
        'other_app.epoch_key_1': 'Zm9yZWlnbg==',
        'prism_sync.epoch_key_1': 'b3Vycw==',
      });
      expect(json, isNotNull);
      final decoded = jsonDecode(json!) as Map<String, dynamic>;
      expect(decoded['epoch_key_1'], 'b3Vycw==');
      // No foreign key in output.
      expect(decoded.containsKey('other_app.epoch_key_1'), isFalse);
    });
  });
}
