import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/providers/sync_setup_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// In-memory `flutter_secure_storage` MethodChannel stub. The plugin uses a
/// platform channel so we route every read/write/delete/readAll/deleteAll
/// through the same Map and let the centralized `secureStorage` instance
/// from `core/services/secure_storage.dart` go through its real code path.
class _InMemoryKeychain {
  final Map<String, String> values = <String, String>{};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          _handle,
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  }

  Future<dynamic> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
    switch (call.method) {
      case 'read':
        return values[args['key'] as String];
      case 'write':
        values[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        values.remove(args['key'] as String);
        return null;
      case 'readAll':
        return Map<String, String>.from(values);
      case 'deleteAll':
        values.clear();
        return null;
      case 'containsKey':
        return values.containsKey(args['key'] as String);
      default:
        return null;
    }
  }
}

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test double for `PrismSyncHandleNotifier`. Skips the entire FFI plumbing
/// in `createHandle` and just exposes a constant fake handle. Tests can
/// flip `nullOnRead` to true to simulate a provider invalidation between
/// `proceedToEnterPhrase` and `submitPhrase`.
class _FakePrismSyncHandleNotifier extends PrismSyncHandleNotifier {
  _FakePrismSyncHandleNotifier(this._handle);

  ffi.PrismSyncHandle? _handle;
  String? lastRelayUrl;

  @override
  Future<ffi.PrismSyncHandle?> build() async => _handle;

  @override
  Future<ffi.PrismSyncHandle> createHandle({required String relayUrl}) async {
    lastRelayUrl = relayUrl;
    return _handle!;
  }

  void clearHandle() {
    _handle = null;
    state = const AsyncValue.data(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemoryKeychain keychain;

  setUp(() {
    keychain = _InMemoryKeychain()..install();
  });

  tearDown(() {
    keychain.uninstall();
  });

  ProviderContainer makeContainer({
    required _FakePrismSyncHandleNotifier handleNotifier,
  }) {
    final container = ProviderContainer(
      overrides: [prismSyncHandleProvider.overrideWith(() => handleNotifier)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('SyncSetupProgress', () {
    test(
      'enum covers the offline-only stages — no syncing / uploading step',
      () {
        // Guardrail: the new offline-only bootstrap flow must NOT carry a
        // "syncing" stage. If this assertion breaks, the flow reverted to
        // pushing data to the relay during first-device setup.
        expect(SyncSetupProgress.values, hasLength(5));
        expect(SyncSetupProgress.values.map((v) => v.name).toSet(), {
          'creatingGroup',
          'configuringEngine',
          'cachingKeys',
          'bootstrappingData',
          'measuringSnapshot',
        });
      },
    );
  });

  // ── Phase 1A — convention-based rollback test ──────────────────────────
  // Drives `_snapshotPrismSyncKeychain` + `_restoreKeychainSnapshot` via
  // their `@visibleForTesting` seams. The full `_complete` path is gated
  // behind FFI calls (`createSyncGroup`, `configureEngine`,
  // `drainRustStore`, `cacheRuntimeKeys`) that can't run in pure-Dart
  // tests, so we exercise the snapshot/rollback contract directly. This
  // is the contract the plan's "fail at every await point" parameterized
  // test would assert; see `_restoreKeychainSnapshot`'s doc for the
  // rules under test.

  group('SyncSetupNotifier keychain rollback (Phase 1A)', () {
    test(
      'protected DB keys survive rollback for every entry in kProtectedFromReset',
      () async {
        // Convention-based per the plan (Opus §1.3): loop over the
        // exported set rather than hardcoding the four key names so that
        // adding/removing a slot in prism_sync_providers.dart
        // automatically updates this assertion.
        for (final protectedKey in kProtectedFromReset) {
          // Fresh keychain per protected key so failures don't leak across
          // iterations.
          keychain.values.clear();
          keychain.values[protectedKey] = 'SENTINEL_${protectedKey.hashCode}';
          // Pre-existing app key in the prism_sync namespace that should
          // be preserved across rollback (it existed before setup).
          keychain.values['prism_sync.preexisting_app_key'] = 'OLD';

          final notifier = _FakePrismSyncHandleNotifier(
            const _FakePrismSyncHandle(),
          );
          final container = makeContainer(handleNotifier: notifier);
          final setup = container.read(syncSetupProvider.notifier);

          // 1. Snapshot what existed before "setup" started. Protected
          //    slots must be EXCLUDED from this snapshot per
          //    `_snapshotPrismSyncKeychain`'s contract.
          final snapshot = await setup.snapshotPrismSyncKeychainForTest();
          expect(
            snapshot.containsKey(protectedKey),
            isFalse,
            reason:
                '$protectedKey is in kProtectedFromReset and must NOT be '
                'captured in the rollback snapshot — see '
                '_snapshotPrismSyncKeychain doc.',
          );
          expect(
            snapshot['prism_sync.preexisting_app_key'],
            'OLD',
            reason: 'non-protected pre-existing keys must be snapshotted',
          );

          // 2. Simulate writes that happen during `_complete` AFTER the
          //    snapshot is taken: sync_id/relay_url (explicit writes),
          //    plus the secrets that drainRustStore mirrors into the
          //    keychain. Also rotate the protected slot forward to
          //    mimic cacheRuntimeKeys rekeying the DB.
          keychain.values['prism_sync.sync_id'] = 'NEW_SYNC';
          keychain.values['prism_sync.relay_url'] = 'NEW_RELAY';
          keychain.values['prism_sync.session_token'] = 'NEW_TOKEN';
          keychain.values['prism_sync.epoch'] = 'NEW_EPOCH';
          keychain.values['prism_sync.wrapped_dek'] = 'NEW_DEK';
          keychain.values['prism_sync.preexisting_app_key'] = 'CHANGED';
          keychain.values[protectedKey] = 'ROTATED_${protectedKey.hashCode}';

          // 3. Trigger rollback (as the catch block in `_complete` does).
          await setup.restoreKeychainSnapshotForTest(snapshot);

          // 4. Protected slot must NEVER be reverted — see
          //    `_snapshotPrismSyncKeychain` doc for the orphan-DB risk.
          expect(
            keychain.values[protectedKey],
            'ROTATED_${protectedKey.hashCode}',
            reason:
                '$protectedKey was rotated forward by cacheRuntimeKeys and '
                'must survive rollback intact',
          );

          // 5. Setup-time writes must be wiped from the namespace.
          expect(keychain.values['prism_sync.sync_id'], isNull);
          expect(keychain.values['prism_sync.relay_url'], isNull);
          expect(keychain.values['prism_sync.session_token'], isNull);
          expect(keychain.values['prism_sync.epoch'], isNull);
          expect(keychain.values['prism_sync.wrapped_dek'], isNull);

          // 6. Pre-existing non-protected keys must be restored to their
          //    captured value.
          expect(
            keychain.values['prism_sync.preexisting_app_key'],
            'OLD',
            reason: 'snapshotted non-protected keys must be restored',
          );
        }
      },
    );

    test(
      'rollback restores sync_id/relay_url to pre-setup values when they pre-existed',
      () async {
        keychain.values['prism_sync.sync_id'] = 'PRE_SYNC';
        keychain.values['prism_sync.relay_url'] = 'PRE_RELAY';
        keychain.values['prism_sync.database_key'] = 'KEEP_DB_KEY';

        final notifier = _FakePrismSyncHandleNotifier(
          const _FakePrismSyncHandle(),
        );
        final container = makeContainer(handleNotifier: notifier);
        final setup = container.read(syncSetupProvider.notifier);

        final snapshot = await setup.snapshotPrismSyncKeychainForTest();

        // Setup overwrites them.
        keychain.values['prism_sync.sync_id'] = 'NEW_SYNC';
        keychain.values['prism_sync.relay_url'] = 'NEW_RELAY';
        keychain.values['prism_sync.database_key'] = 'ROTATED_DB_KEY';

        await setup.restoreKeychainSnapshotForTest(snapshot);

        expect(keychain.values['prism_sync.sync_id'], 'PRE_SYNC');
        expect(keychain.values['prism_sync.relay_url'], 'PRE_RELAY');
        // Protected DB-key slot must NOT be reverted to PRE value.
        expect(keychain.values['prism_sync.database_key'], 'ROTATED_DB_KEY');
      },
    );

    test(
      'rollback wipes sync_id/relay_url when they did not pre-exist',
      () async {
        // Empty pre-setup state for the prism_sync namespace.
        keychain.values['unrelated'] = 'OUTSIDE';

        final notifier = _FakePrismSyncHandleNotifier(
          const _FakePrismSyncHandle(),
        );
        final container = makeContainer(handleNotifier: notifier);
        final setup = container.read(syncSetupProvider.notifier);

        final snapshot = await setup.snapshotPrismSyncKeychainForTest();
        expect(snapshot, isEmpty);

        // Setup writes appear post-snapshot.
        keychain.values['prism_sync.sync_id'] = 'NEW_SYNC';
        keychain.values['prism_sync.relay_url'] = 'NEW_RELAY';
        keychain.values['prism_sync.session_token'] = 'NEW_TOKEN';

        await setup.restoreKeychainSnapshotForTest(snapshot);

        expect(keychain.values['prism_sync.sync_id'], isNull);
        expect(keychain.values['prism_sync.relay_url'], isNull);
        expect(keychain.values['prism_sync.session_token'], isNull);
        // Out-of-namespace keys are never touched.
        expect(keychain.values['unrelated'], 'OUTSIDE');
      },
    );

    test(
      'snapshot helper covers prism_sync.* and excludes protected slots only',
      () async {
        keychain.values['prism_sync.sync_id'] = 'A';
        keychain.values['prism_sync.bootstrap_joiner_bundle'] = 'B';
        keychain.values['prism_sync.database_key'] = 'C';
        keychain.values['prism_sync.database_key_staging'] = 'D';
        keychain.values['prism_sync.sync_database_key'] = 'E';
        keychain.values['prism_sync.sync_database_key_staging'] = 'F';
        keychain.values['unrelated'] = 'G';

        final notifier = _FakePrismSyncHandleNotifier(
          const _FakePrismSyncHandle(),
        );
        final container = makeContainer(handleNotifier: notifier);
        final setup = container.read(syncSetupProvider.notifier);

        final snapshot = await setup.snapshotPrismSyncKeychainForTest();

        expect(snapshot['prism_sync.sync_id'], 'A');
        expect(snapshot['prism_sync.bootstrap_joiner_bundle'], 'B');
        for (final protectedKey in kProtectedFromReset) {
          expect(
            snapshot.containsKey(protectedKey),
            isFalse,
            reason: '$protectedKey must be excluded from the rollback snapshot',
          );
        }
        expect(snapshot.containsKey('unrelated'), isFalse);
      },
    );
  });

  // ── Phase 4D — handle re-read on submitPhrase ───────────────────────────

  group('SyncSetupNotifier handle re-read (Phase 4D)', () {
    test(
      'submitPhrase surfaces clean error when handle was invalidated',
      () async {
        final handleNotifier = _FakePrismSyncHandleNotifier(
          const _FakePrismSyncHandle(),
        );
        final container = makeContainer(handleNotifier: handleNotifier);
        final setup = container.read(syncSetupProvider.notifier);

        // 1. Establish the setup handle the way the UI does.
        setup.setRelayUrl('https://example.com');
        await setup.proceedToEnterPhrase();
        expect(
          container.read(syncSetupProvider).step,
          SyncSetupStep.enterPhrase,
        );

        // 2. Drop the handle BEFORE submitPhrase. With the old cached
        //    `_handle` field this would have used a stale reference; the
        //    new getter re-reads the provider every call.
        handleNotifier.clearHandle();

        // 3. submitPhrase must surface a clean error, not crash. Use a
        //    valid 12-word BIP39 mnemonic so we get past the wordlist
        //    check and reach the handle-null branch.
        const validMnemonic =
            'abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon about';
        final ok = await setup.submitPhrase(validMnemonic, '123456');

        expect(ok, isFalse);
        final state = container.read(syncSetupProvider);
        expect(state.error, isNotNull);
        expect(
          state.error,
          contains('Setup handle no longer available'),
          reason: 'Expected the Phase 4D error message; got "${state.error}"',
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

    test('bootstrap_not_allowed falls back to structured message when reason '
        'is absent', () {
      final raw = _structuredErrorString({
        'error_type': 'core',
        'code': 'bootstrap_not_allowed',
        'message': 'guard failed: device already registered',
      });
      final structured = PrismSyncStructuredError.tryParse(raw);

      final message = friendlySyncSetupError(structured, raw);

      expect(message, contains('guard failed: device already registered'));
    });
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
