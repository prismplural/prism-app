import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/sync_setup_provider.dart';

void main() {
  group('SyncSetupProgress', () {
    test(
      'enum covers the offline-only stages — no syncing / uploading step',
      () {
        // Guardrail: the new offline-only bootstrap flow must NOT carry a
        // "syncing" stage. If this assertion breaks, the flow reverted to
        // pushing data to the relay during first-device setup.
        expect(SyncSetupProgress.values, hasLength(5));
        expect(
          SyncSetupProgress.values.map((v) => v.name).toSet(),
          {
            'creatingGroup',
            'configuringEngine',
            'cachingKeys',
            'bootstrappingData',
            'measuringSnapshot',
          },
        );
      },
    );
  });

  group('friendlySyncSetupError — bootstrap-specific structured errors', () {
    test('snapshot_too_large renders human-readable byte counts', () {
      final raw = _structuredErrorString({
        'error_type': 'core',
        'code': 'snapshot_too_large',
        'message': 'snapshot too large',
        'bytes': 150 * 1024 * 1024,
        'limit_bytes': 100 * 1024 * 1024,
      });
      final structured = PrismSyncStructuredError.tryParse(raw);
      expect(structured?.code, 'snapshot_too_large');

      final message = friendlySyncSetupError(structured, raw);

      expect(message, contains('150 MB'));
      expect(message, contains('100 MB'));
      expect(message, contains('working on larger systems'));
      expect(message, isNot(contains('PRISM_SYNC_ERROR_JSON')));
    });

    test(
      'snapshot_too_large falls back gracefully when byte counts are missing',
      () {
        final raw = _structuredErrorString({
          'error_type': 'core',
          'code': 'snapshot_too_large',
          'message': 'snapshot too large',
        });
        final structured = PrismSyncStructuredError.tryParse(raw);

        final message = friendlySyncSetupError(structured, raw);

        expect(message, contains('exceeds the current sync data limit'));
        expect(message, contains('working on larger systems'));
      },
    );

    test('bootstrap_not_allowed includes the structured reason', () {
      final raw = _structuredErrorString({
        'error_type': 'core',
        'code': 'bootstrap_not_allowed',
        'message': 'bootstrap not allowed',
        'reason': 'another device is already registered',
      });
      final structured = PrismSyncStructuredError.tryParse(raw);
      expect(structured?.code, 'bootstrap_not_allowed');

      final message = friendlySyncSetupError(structured, raw);

      expect(message, contains("Couldn't prepare sync on this device"));
      expect(message, contains('another device is already registered'));
      expect(message, contains('report this with logs'));
    });

    test(
      'bootstrap_not_allowed falls back to structured message when reason '
      'is absent',
      () {
        final raw = _structuredErrorString({
          'error_type': 'core',
          'code': 'bootstrap_not_allowed',
          'message': 'guard failed: device already registered',
        });
        final structured = PrismSyncStructuredError.tryParse(raw);

        final message = friendlySyncSetupError(structured, raw);

        expect(message, contains('guard failed: device already registered'));
      },
    );
  });

  group('friendlySyncSetupError — pre-existing error paths remain intact', () {
    test('rate-limit registration error maps to friendly copy', () {
      final raw = _structuredErrorString({
        'error_type': 'relay',
        'message': 'registration failed: rate limit exceeded',
        'status': 429,
      });
      final structured = PrismSyncStructuredError.tryParse(raw);

      final message = friendlySyncSetupError(structured, raw);

      expect(message, contains('Too many registration attempts'));
    });

    test('SocketException (no structured error) maps to network copy', () {
      const raw = 'SocketException: Connection refused';

      final message = friendlySyncSetupError(null, raw);

      expect(message, contains('Could not connect to relay server'));
    });

    test('generic relay structured error maps to network copy', () {
      final raw = _structuredErrorString({
        'error_type': 'relay',
        'message': 'upstream unavailable',
        'relay_kind': 'upstream',
      });
      final structured = PrismSyncStructuredError.tryParse(raw);

      final message = friendlySyncSetupError(structured, raw);

      expect(message, contains('Could not connect to relay server'));
    });
  });
}

/// Build the FFI error-string shape that Rust emits when structured errors
/// cross the boundary: `PRISM_SYNC_ERROR_JSON:{...}`.
String _structuredErrorString(Map<String, Object?> payload) {
  final entries = payload.entries
      .map((e) => '"${e.key}":${_encode(e.value)}')
      .join(',');
  return 'PRISM_SYNC_ERROR_JSON:{$entries}';
}

String _encode(Object? value) {
  if (value == null) return 'null';
  if (value is num) return value.toString();
  if (value is bool) return value.toString();
  final escaped = value.toString().replaceAll('"', '\\"');
  return '"$escaped"';
}
