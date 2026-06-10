// H3: the destructive `device_revoked` path must be gated on a
// SIGNATURE-VERIFIED self-revocation check (the new Rust
// `ffi.confirmSelfRevocation`, surfaced in Dart as
// `_confirmRevokeViaRegistry`). An UNAUTHENTICATED relay hint — a WebSocket
// `device_revoked` frame echoing our own device_id, or a relay-injected
// `PRISM_SYNC_ERROR_JSON:{...remote_wipe:true...}` substring in an error body —
// must NOT, on its own, wipe a HEALTHY device.
//
// These drive the REAL `SyncStatusNotifier` event dispatch over an injected
// event stream (no FFI, no relay). The verified registry verdict is simulated
// via the `debugRevokeConfirmationOverride` seam (which stands in for the Rust
// `confirm_self_revocation` result). The destructive effects are observed
// through:
//   - an in-memory secure-storage method-channel fake (credential clear), and
//   - an in-memory Drift `AppDatabase` override (`_wipeLocalData` row deletes).
//
// Mirrors the harness in `sync_event_drain_test.dart` (ProviderContainer +
// event stream) and the secure-storage fake from
// `e2e/level1_false_revoke_e2e_test.dart`.

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

/// Stub quarantine service that returns false without touching the DB.
class _FakeQuarantineService implements SyncQuarantineService {
  @override
  Future<bool> hasQuarantinedItems() async => false;
  @override
  Future<int> count() async => 0;
  @override
  Future<int> repairLegacyMemberAgeStringMismatches() async => 0;
  @override
  Future<void> clearAll() async {}
  @override
  Future<void> quarantineField({
    required String entityType,
    required String entityId,
    String? fieldName,
    required String expectedType,
    required String receivedType,
    String? receivedValue,
    String? sourceDevice,
    String? errorMessage,
  }) async {}
}

const _credKeys = <String>[
  'relay_url',
  'sync_id',
  'device_id',
  'session_token',
  'device_secret',
];

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// In-memory secure-storage fake at the method-channel level. The production
/// `safeSecure*` wrappers talk over this channel, so faking here intercepts
/// every credential read/write/delete the revoke path performs.
class _SecureStorageFake {
  final Map<String, String> store = <String, String>{};

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (MethodCall call) async {
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
          return store[call.arguments['key'] as String];
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
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
    store.clear();
  }

  /// Seed all five credential slots the way the keychain stores them:
  /// base64(utf8(value)).
  void seedCreds() {
    for (final key in _credKeys) {
      store['prism_sync.$key'] = base64Encode(utf8.encode('$key-value'));
    }
  }

  bool hasAllCreds() =>
      _credKeys.every((k) => (store['prism_sync.$k'] ?? '').isNotEmpty);
}

/// A `DeviceRevoked` event that ECHOES our own device_id with `remote_wipe`.
/// This is the H3 spoof: the relay knows our device_id, so it can name us.
SyncEvent _confirmedSelfRevokeEvent({required bool remoteWipe}) =>
    SyncEvent('DeviceRevoked', {
      'type': 'DeviceRevoked',
      'device_id': 'device_id-value',
      'remote_wipe': remoteWipe,
    });

/// An AUTH-FAILURE `device_revoked` carried on a `SyncCompleted.result` whose
/// `device_id` ECHOES our own (confirmedSelf via the auth-failure route, not
/// the no-device_id ambiguous route). Drives `_handleDeviceRevokedFromAuthFailure`.
SyncEvent _confirmedSelfAuthFailureEvent({required bool remoteWipe}) =>
    SyncEvent('SyncCompleted', {
      'type': 'SyncCompleted',
      'result': {
        'pulled': 0,
        'merged': 0,
        'pushed': 0,
        'pruned': 0,
        'duration_ms': 0,
        'push_incomplete': false,
        'error': 'device revoked',
        'error_code': 'device_revoked',
        'device_id': 'device_id-value',
        'remote_wipe': remoteWipe,
      },
    });

/// A `SyncCompleted` whose `result.error` carries a relay-INJECTED
/// `PRISM_SYNC_ERROR_JSON:` marker claiming `device_revoked` + `remote_wipe`.
/// Substring-scanning this body must NOT, by itself, trigger a wipe.
SyncEvent _spoofedErrorStringEvent() => SyncEvent('SyncCompleted', {
      'type': 'SyncCompleted',
      'result': {
        'pulled': 0,
        'merged': 0,
        'pushed': 0,
        'pruned': 0,
        'duration_ms': 0,
        'push_incomplete': false,
        'error':
            'relay said no PRISM_SYNC_ERROR_JSON:{"message":"revoked",'
            '"code":"device_revoked","remote_wipe":true}',
      },
    });

typedef _Wired = ({
  ProviderContainer container,
  StreamController<SyncEvent> events,
  List<SyncEvent> delivered,
  _SecureStorageFake secure,
  AppDatabase db,
  void Function() teardown,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugRevokeConfirmationOverride = null;
    debugDrainRustStoreOverride = null;
    debugDrainDebounceOverride = null;
    debugPostRevokeRecleanOverride = null;
  });

  /// Build a container wired with: an in-memory DB seeded with one
  /// `system_settings` row (the wipe sentinel), the secure-storage fake seeded
  /// with all creds, and an injectable sync-event stream.
  Future<_Wired> wire() async {
    final secure = _SecureStorageFake()..install();
    secure.seedCreds();

    final db = AppDatabase(NativeDatabase.memory());
    // A row in a table `_wipeLocalData` clears. Survives → no wipe; gone → wipe.
    await db.customStatement(
      "INSERT INTO system_settings (id) VALUES ('revoke-sentinel')",
    );

    // Single-subscription controller BUFFERS the event until the provider
    // attaches, so the push can't be dropped before the listener is live.
    final events = StreamController<SyncEvent>();
    final delivered = <SyncEvent>[];

    // Keep cleanup fast and observable.
    debugDrainDebounceOverride = const Duration(milliseconds: 5);
    debugPostRevokeRecleanOverride = const Duration(milliseconds: 20);
    // Don't write the Rust store back over our keychain fake during the test.
    debugDrainRustStoreOverride = () async {};

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncEventStreamProvider.overrideWith((ref) => events.stream),
        syncQuarantineServiceProvider.overrideWithValue(
          _FakeQuarantineService(),
        ),
      ],
    );

    final eventSub = container.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (prev, next) {
        next.whenData(delivered.add);
      },
      fireImmediately: true,
    );
    // Activate SyncStatusNotifier so its `ref.listen(syncEventStreamProvider)`
    // dispatch is live.
    final statusSub = container.listen<SyncStatus>(
      syncStatusProvider,
      (prev, next) {},
    );

    return (
      container: container,
      events: events,
      delivered: delivered,
      secure: secure,
      db: db,
      teardown: () {
        eventSub.close();
        statusSub.close();
        container.dispose();
        unawaited(events.close());
        unawaited(db.close());
        secure.uninstall();
      },
    );
  }

  Future<void> awaitDelivered(List<SyncEvent> delivered, int wantAtLeast) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (delivered.length < wantAtLeast) {
      if (DateTime.now().isAfter(deadline)) {
        fail('event was never delivered to the provider (got ${delivered.length})');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<int> sentinelCount(AppDatabase db) async {
    final rows = await db
        .customSelect('SELECT count(*) AS c FROM system_settings')
        .get();
    return rows.first.data['c'] as int;
  }

  test(
    'CORE FIX: confirmedSelf device_revoked with verified ACTIVE does NOT wipe '
    'and does NOT clear credentials',
    () async {
      final w = await wire();
      addTearDown(w.teardown);

      // The verified Rust check (simulated) says we are STILL ACTIVE even
      // though the relay echoed our device_id with remote_wipe:true.
      debugRevokeConfirmationOverride = () async =>
          RevokeConfirmationResult.stillActive;

      expect(w.secure.hasAllCreds(), isTrue);
      expect(await sentinelCount(w.db), 1);

      w.events.add(_confirmedSelfRevokeEvent(remoteWipe: true));
      await awaitDelivered(w.delivered, 1);
      // Give the (now-gated) handler time to run to completion.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        w.secure.hasAllCreds(),
        isTrue,
        reason:
            'a relay echoing our device_id must NOT clear credentials unless '
            'the verified registry marks us revoked (store now: '
            '${w.secure.store.keys.where((k) => k.startsWith('prism_sync.')).toList()})',
      );
      expect(
        await sentinelCount(w.db),
        1,
        reason: 'unverified confirmedSelf must NOT wipe local data',
      );
    },
  );

  test(
    'CORE FIX (auth-failure route): confirmedSelf device_revoked with verified '
    'ACTIVE does NOT wipe and does NOT clear credentials',
    () async {
      // Closes the coverage gap: the auth-failure handler
      // (`_handleDeviceRevokedFromAuthFailure`) confirmedSelf path — the event
      // carries `device_id` == OUR own id — must also be gated on the verified
      // check, not just the no-device_id ambiguous route.
      final w = await wire();
      addTearDown(w.teardown);

      // Relay echoes our device_id with remote_wipe, but the verified Rust
      // check (simulated) says we are STILL ACTIVE.
      debugRevokeConfirmationOverride = () async =>
          RevokeConfirmationResult.stillActive;

      expect(w.secure.hasAllCreds(), isTrue);
      expect(await sentinelCount(w.db), 1);

      w.events.add(_confirmedSelfAuthFailureEvent(remoteWipe: true));
      await awaitDelivered(w.delivered, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        w.secure.hasAllCreds(),
        isTrue,
        reason:
            'auth-failure confirmedSelf must NOT clear credentials unless the '
            'verified registry marks us revoked (store now: '
            '${w.secure.store.keys.where((k) => k.startsWith('prism_sync.')).toList()})',
      );
      expect(
        await sentinelCount(w.db),
        1,
        reason: 'unverified auth-failure confirmedSelf must NOT wipe local data',
      );
    },
  );

  test(
    'H3 Layer B: verified REVOKED with VERIFIED wipe=TRUE DOES wipe and clears '
    'credentials',
    () async {
      final w = await wire();
      addTearDown(w.teardown);

      // The verified Rust check confirms we are genuinely revoked AND the
      // admin-SIGNED wipe intent is true.
      debugRevokeConfirmationOverride = () async => const RevokeConfirmationResult(
            RevokeConfirmation.confirmedRevoked,
            remoteWipe: true,
          );

      expect(w.secure.hasAllCreds(), isTrue);
      expect(await sentinelCount(w.db), 1);

      // Relay frame agrees here, but the decision is driven by the verified bit.
      w.events.add(_confirmedSelfRevokeEvent(remoteWipe: true));
      await awaitDelivered(w.delivered, 1);

      // Wait for BOTH destructive effects to land.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (w.secure.hasAllCreds() || await sentinelCount(w.db) != 0) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        w.secure.hasAllCreds(),
        isFalse,
        reason: 'a VERIFIED revoke must clear credentials',
      );
      expect(
        await sentinelCount(w.db),
        0,
        reason: 'a VERIFIED revoke with VERIFIED wipe=true must wipe local data',
      );
    },
  );

  test(
    'H3 Layer B: verified REVOKED with VERIFIED wipe=FALSE but relay frame '
    'wipe=TRUE does NOT wipe local data (only clears credentials)',
    () async {
      // The load-bearing Layer B guarantee: a relay flipping the WS-frame
      // `remote_wipe` to true on a verifiably-revoked device whose SIGNED
      // registry says wipe=false must NOT trigger a local-data wipe. The device
      // still disconnects + clears credentials (it IS revoked), but the
      // orphaned local data survives because no admin signature covers wipe=true.
      final w = await wire();
      addTearDown(w.teardown);

      debugRevokeConfirmationOverride = () async => const RevokeConfirmationResult(
            RevokeConfirmation.confirmedRevoked,
            // VERIFIED wipe intent is FALSE.
            remoteWipe: false,
          );

      expect(w.secure.hasAllCreds(), isTrue);
      expect(await sentinelCount(w.db), 1);

      // Relay frame LIES: wipe=true. It is now only an ignored hint.
      w.events.add(_confirmedSelfRevokeEvent(remoteWipe: true));
      await awaitDelivered(w.delivered, 1);

      // Wait for the credential clear (the non-wipe destructive effect) to land.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (w.secure.hasAllCreds()) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Give any (incorrect) wipe a chance to fire so the assertion is real.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        w.secure.hasAllCreds(),
        isFalse,
        reason: 'a VERIFIED revoke still clears credentials',
      );
      expect(
        await sentinelCount(w.db),
        1,
        reason:
            'a relay-frame remote_wipe=true must NOT wipe local data when the '
            'VERIFIED signed wipe intent is false (H3 Layer B invariant)',
      );
    },
  );

  test(
    'relay-injected PRISM_SYNC_ERROR_JSON remote_wipe substring does NOT wipe '
    'on its own (verified check returns UNKNOWN)',
    () async {
      final w = await wire();
      addTearDown(w.teardown);

      // A spoofed error body cannot be verified — the Rust check returns
      // unknown. Nothing destructive may happen.
      debugRevokeConfirmationOverride = () async =>
          RevokeConfirmationResult.unknown;

      expect(w.secure.hasAllCreds(), isTrue);
      expect(await sentinelCount(w.db), 1);

      w.events.add(_spoofedErrorStringEvent());
      await awaitDelivered(w.delivered, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        w.secure.hasAllCreds(),
        isTrue,
        reason:
            'a relay-injected device_revoked/remote_wipe error string must NOT '
            'clear credentials without a verified revocation',
      );
      expect(
        await sentinelCount(w.db),
        1,
        reason:
            'a relay-injected remote_wipe error string must NOT wipe local data',
      );
    },
  );
}
