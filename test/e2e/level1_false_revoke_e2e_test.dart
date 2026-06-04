// Level-1 end-to-end: drive the REAL Dart sync orchestration
// (`SyncStatusNotifier` from prism-app's prism_sync_providers.dart) over a REAL
// Rust FFI handle and a REAL spawned relay. No fakes for the engine.
//
// Reproduce-or-exonerate the field "device drops sync" bug: an AMBIGUOUS
// `device_revoked` signal (a mid-cycle 401 whose result carries no `device_id`)
// must be confirmed against the relay device registry BEFORE anything
// destructive happens. The documented invariant (0.11.2 false-revoke fix): when
// the registry check is INCONCLUSIVE (relay unreachable → `ffi.listDevices`
// throws), credentials are PRESERVED and health does NOT flip to
// disconnected/unpaired.
//
// This wires the REAL engine ↔ REAL decision-logic seam: the event flows
// through `SyncStatusNotifier`'s `ref.listen(syncEventStreamProvider, …)`
// dispatch → `_handleDeviceRevokedFromAuthFailure` → `classifyRevokeSelfCheck`
// (ambiguous) → `_confirmRevokeViaRegistry` → the REAL `ffi.listDevices`
// against a stopped relay.
//
// The teeth check forces `debugRevokeConfirmationOverride` to confirmedRevoked
// on the SAME event and proves the destructive path actually fires (health →
// disconnected AND creds wiped), so the real-ambiguous assertions are not
// tautological.
//
// Prereqs (from the prism-sync worktree):
//   cargo build --release -p prism_sync_ffi
//   cargo build --release -p prism-sync-relay --example test_relay

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';
import 'package:drift/native.dart';

import 'e2e_fixture.dart';
import 'e2e_support.dart';

/// Live-handle override: exposes a REAL FFI handle to the providers that read
/// `prismSyncHandleProvider`. Extends the production notifier (so the provider's
/// type/identity are unchanged) but replaces `build()` to hand back the live
/// handle. We do NOT chain `super.build()` — its onDispose would dispose the
/// handle out from under our own teardown.
class _LiveHandleNotifier extends PrismSyncHandleNotifier {
  _LiveHandleNotifier(this._handle);
  final ffi.PrismSyncHandle _handle;

  @override
  Future<ffi.PrismSyncHandle?> build() async => _handle;
}

/// The five credential slots the revoke path reads. Keys are the bare names;
/// the keychain stores them under the `prism_sync.` prefix, base64(utf8(value)).
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

/// In-memory secure-storage fake at the method-channel level — the same
/// mechanism `prism_sync_providers_test.dart` uses. The production
/// `safeSecure*` wrappers default to the `secureStorage` singleton, which talks
/// over this channel, so faking here intercepts every credential read/write.
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

  /// Seed all five credential slots from a live device's drained Rust store,
  /// encoded the way the app's keychain stores them: base64 of the raw stored
  /// bytes. For the UTF-8 string slots (relay_url/sync_id/device_id/
  /// session_token) this is exactly base64(utf8(value)) — what
  /// `_readDecodedCredential` reverses. `device_secret` is raw key material
  /// (not UTF-8); it's only ever presence-checked, so base64 of its bytes is
  /// the faithful keychain form.
  Future<void> seedFrom(E2EDevice device) async {
    final raw = await ffi.drainSecureStore(handle: device.handle);
    for (final key in _credKeys) {
      final bytes = raw[key];
      expect(
        bytes,
        isNotNull,
        reason: 'drained Rust store should contain "$key" for a live device',
      );
      store['prism_sync.$key'] = base64Encode(bytes!);
    }
  }

  bool hasAllCreds() =>
      _credKeys.every((k) => (store['prism_sync.$k'] ?? '').isNotEmpty);
}

/// The ambiguous `device_revoked` SyncCompleted event: `error_code` is set but
/// NO `device_id` is present anywhere, and `push_incomplete` is false so
/// `isMidDrainContinuation` returns false (the handler does NOT early-return).
SyncEvent _ambiguousRevokeEvent() => SyncEvent('SyncCompleted', {
      'type': 'SyncCompleted',
      'result': {
        'error_code': 'device_revoked',
        'error': 'device revoked',
        'remote_wipe': false,
        'push_incomplete': false,
      },
    });

/// What `wire()` returns: the live container plus the handles a test drives.
/// `delivered` records every event the provider actually handed to listeners,
/// so a test can prove its injected event was processed before asserting.
typedef _Wired = ({
  ProviderContainer container,
  StreamController<SyncEvent> events,
  List<SyncEvent> delivered,
  _SecureStorageFake secure,
  AppDatabase db,
  void Function() teardown,
});

void main() {
  setUpAll(() async {
    if (e2eSkip() != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(resolveFfiLib()));
  });
  tearDownAll(() {
    if (e2eSkip() != null) return;
    RustLib.dispose();
  });

  tearDown(() {
    // The teeth check sets this; always reset so cases can't leak into each
    // other.
    debugRevokeConfirmationOverride = null;
  });

  /// Build a container wired with: live handle, in-memory DB, the secure-storage
  /// fake, and an injectable sync-event stream. Returns the pieces the test
  /// drives. Caller disposes via the returned teardown.
  Future<_Wired> wire(E2EDevice device) async {
    final secure = _SecureStorageFake()..install();
    await secure.seedFrom(device);

    // Single-subscription (NOT broadcast): a single-sub controller BUFFERS an
    // event until the StreamProvider attaches, so a push can't be dropped on
    // the floor. A broadcast controller discards events emitted with no live
    // listener — the source of an intermittent failure under load where the
    // provider subscribed a beat after the event was pushed.
    final events = StreamController<SyncEvent>();
    final db = AppDatabase(NativeDatabase.memory());

    final container = ProviderContainer(
      overrides: [
        prismSyncHandleProvider.overrideWith(() => _LiveHandleNotifier(device.handle)),
        syncEventStreamProvider.overrideWith((ref) => events.stream),
        databaseProvider.overrideWithValue(db),
      ],
    );

    // Force the handle to resolve so `ref.read(prismSyncHandleProvider).value`
    // is the live handle by the time we push the event.
    final resolved = await container.read(prismSyncHandleProvider.future);
    expect(resolved, same(device.handle), reason: 'live handle override active');

    // Build the status notifier — this registers the
    // `ref.listen(syncEventStreamProvider, …)` dispatch that routes
    // SyncCompleted→revoke. This is the event-injection seam under test.
    container.read(syncStatusProvider);

    // Eagerly subscribe so the StreamProvider attaches to the controller, AND
    // record every delivered event. A test asserts `delivered` is non-empty
    // before judging the outcome — that's what keeps the non-destructive case
    // honest: "health stayed healthy" only means something once we know the
    // event was actually processed (a dropped event would look identical).
    final delivered = <SyncEvent>[];
    final keepAlive = container.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (_, next) => next.whenData(delivered.add),
    );
    // Let the subscription attach to the controller.
    await _settle();

    void teardown() {
      keepAlive.close();
      container.dispose();
      events.close();
      db.close();
      secure.uninstall();
    }

    return (
      container: container,
      events: events,
      delivered: delivered,
      secure: secure,
      db: db,
      teardown: teardown,
    );
  }

  // -------------------------------------------------------------------------
  // The false-revoke invariant: an ambiguous device_revoked with the relay
  // UNREACHABLE (registry check inconclusive) must NOT go destructive.
  // -------------------------------------------------------------------------
  test('ambiguous device_revoked with unreachable relay preserves credentials',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a;
    _Wired? w;
    try {
      a = await createDevice(relay);
      await a.sync();
      w = await wire(a); // builds syncStatusProvider + subscribes the stream

      expect(
        w.container.read(syncHealthProvider),
        equals(SyncHealthState.healthy),
        reason: 'baseline health before the event',
      );
      expect(w.secure.hasAllCreds(), isTrue, reason: 'creds seeded');

      // Stop the relay so the REAL `ffi.listDevices` inside
      // `_confirmRevokeViaRegistry` fails → inconclusive (unknown).
      relay.stop();
      await _settle();

      // Push the ambiguous event (no device_id anywhere).
      w.events.add(_ambiguousRevokeEvent());
      // Prove the event actually reached the notifier — otherwise the
      // "credentials preserved" assertion below would pass even on a dropped
      // event, which looks identical to a correctly-preserved one.
      await _awaitDelivered(w.delivered);

      // Let the async revoke handler settle. It does: read device_id from the
      // (faked) store → classify ambiguous → _confirmRevokeViaRegistry →
      // ffi.listDevices against the dead relay → throws → unknown → preserve.
      final finalHealth = await _awaitHealthSettled(
        w.container,
        // Any non-baseline terminal we'd care about; we mainly need time to
        // pass, then assert. Poll until creds change or a few seconds elapse.
        () => !w!.secure.hasAllCreds() ||
            w.container.read(syncHealthProvider) ==
                SyncHealthState.disconnected,
      );

      // INVARIANT 1 — health did not go destructive.
      expect(
        finalHealth,
        isNot(anyOf(
          equals(SyncHealthState.disconnected),
          equals(SyncHealthState.unpaired),
        )),
        reason:
            'ambiguous + inconclusive registry must NOT flip health to a '
            'destructive state (was: $finalHealth)',
      );

      // INVARIANT 2 — credentials are still present (not wiped).
      expect(
        w.secure.hasAllCreds(),
        isTrue,
        reason:
            'ambiguous + inconclusive registry must preserve all credentials '
            '(store now: ${w.secure.store.keys.where((k) => k.startsWith('prism_sync.')).toList()})',
      );
      // Spot-check the specific durable creds survive intact.
      for (final key in _credKeys) {
        expect(
          (w.secure.store['prism_sync.$key'] ?? ''),
          isNotEmpty,
          reason: 'credential "$key" must still be present',
        );
      }
    } finally {
      w?.teardown();
      a?.dispose();
      relay.stop();
    }
  });

  // -------------------------------------------------------------------------
  // TEETH CHECK — force the registry verdict to confirmedRevoked on the SAME
  // event. The destructive path MUST fire: health → disconnected AND creds
  // wiped. This both proves the assertions above are real and pins down exactly
  // what mutates on a true revoke.
  // -------------------------------------------------------------------------
  test('teeth: forced confirmedRevoked DOES wipe creds and disconnect',
      skip: e2eSkip(), () async {
    final relay = await spawnRelay();
    E2EDevice? a;
    _Wired? w;
    try {
      a = await createDevice(relay);
      await a.sync();
      w = await wire(a);

      // Force the ambiguous → registry confirmation to confirmedRevoked,
      // bypassing the real `ffi.listDevices`. Everything else is the SAME path.
      debugRevokeConfirmationOverride = () async =>
          RevokeConfirmation.confirmedRevoked;
      // Drains run on a 2s post-revoke timer + 500ms debounce by default; shrink
      // so the test settles fast and the re-clean timer is observable.
      debugDrainDebounceOverride = const Duration(milliseconds: 5);
      debugPostRevokeRecleanOverride = const Duration(milliseconds: 30);

      expect(
        w.container.read(syncHealthProvider),
        equals(SyncHealthState.healthy),
      );
      expect(w.secure.hasAllCreds(), isTrue);

      // Relay can stay up; the override short-circuits the registry check, so
      // the confirmed-self branch runs the destructive cleanup regardless.
      w.events.add(_ambiguousRevokeEvent());
      await _awaitDelivered(w.delivered);

      // Wait for the FULL destructive effect — BOTH the health flip AND the
      // wipe. An OR here would return the instant creds are cleared, a beat
      // before `setState(disconnected)` runs, sampling a stale `healthy`.
      final finalHealth = await _awaitHealthSettled(
        w.container,
        () => w!.container.read(syncHealthProvider) ==
                SyncHealthState.disconnected &&
            !w.secure.hasAllCreds(),
        timeout: const Duration(seconds: 6),
      );

      // The destructive path fired: health is disconnected.
      expect(
        finalHealth,
        equals(SyncHealthState.disconnected),
        reason:
            'a confirmed self-revoke MUST set health to disconnected '
            '(was: $finalHealth)',
      );
      // And the credentials were wiped from the keychain fake.
      expect(
        w.secure.hasAllCreds(),
        isFalse,
        reason:
            'a confirmed self-revoke MUST wipe credentials (store still has: '
            '${w.secure.store.keys.where((k) => k.startsWith('prism_sync.')).toList()})',
      );
    } finally {
      debugDrainDebounceOverride = null;
      debugPostRevokeRecleanOverride = null;
      w?.teardown();
      a?.dispose();
      relay.stop();
    }
  });
}

/// Wait until the provider has delivered at least one event to its listeners,
/// asserting it actually arrived. This converts a silent drop (which would make
/// a non-destructive assertion vacuously pass) into an explicit failure.
Future<void> _awaitDelivered(
  List<SyncEvent> delivered, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (delivered.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    delivered,
    isNotEmpty,
    reason: 'the injected sync event must reach the notifier; a dropped event '
        'would make the outcome assertion meaningless',
  );
}

/// Poll [done] for up to [timeout], returning the final health state. Used to
/// give the async revoke handler time to run its FFI + storage work. Returns
/// as soon as [done] is true, otherwise after the timeout (so the ambiguous
/// case, where nothing should change, still exercises the full settle window).
Future<SyncHealthState> _awaitHealthSettled(
  ProviderContainer container,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (done()) break;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return container.read(syncHealthProvider);
}

/// Yield to the event loop so a just-killed relay's socket is released before
/// the next FFI network call.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
