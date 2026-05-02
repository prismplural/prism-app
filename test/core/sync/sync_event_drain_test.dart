import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Tests for the event-driven `drainRustStore` hook inside
/// `SyncStatusNotifier` (Bucket 2B of the 2026-04-11 sync-robustness plan).
///
/// The drain path is redirected via `debugDrainRustStoreOverride` so we
/// can observe drain invocations without exercising the FFI or secure
/// storage. The debounce interval is set to 10ms via
/// `debugDrainDebounceOverride` to keep tests fast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ------------------------------------------------------------------
  // Pure predicate
  // ------------------------------------------------------------------

  group('shouldDrainForCompletedErrorKind', () {
    test('null (success) drains', () {
      expect(shouldDrainForCompletedErrorKind(null), isTrue);
    });

    test('transient error kinds drain', () {
      expect(shouldDrainForCompletedErrorKind('Network'), isTrue);
      expect(shouldDrainForCompletedErrorKind('Server'), isTrue);
      expect(shouldDrainForCompletedErrorKind('Timeout'), isTrue);
    });

    test('credential-state error kinds skip drain', () {
      expect(shouldDrainForCompletedErrorKind('Auth'), isFalse);
      expect(shouldDrainForCompletedErrorKind('KeyChanged'), isFalse);
      expect(
          shouldDrainForCompletedErrorKind('DeviceIdentityMismatch'), isFalse);
    });

    test('protocol/epoch/clock errors skip drain', () {
      expect(shouldDrainForCompletedErrorKind('EpochRotation'), isFalse);
      expect(shouldDrainForCompletedErrorKind('Protocol'), isFalse);
      expect(shouldDrainForCompletedErrorKind('ClockSkew'), isFalse);
    });

    test('unknown future kind drains conservatively', () {
      expect(shouldDrainForCompletedErrorKind('NeverBeforeSeen'), isTrue);
    });
  });

  // ------------------------------------------------------------------
  // Event-driven drain via SyncStatusNotifier
  // ------------------------------------------------------------------

  const testDebounce = Duration(milliseconds: 10);
  const settleAfterDebounce = Duration(milliseconds: 40);

  /// Bind a test ProviderContainer with:
  /// - a controllable SyncEvent broadcast stream
  /// - a counter incremented by the debug drain override
  /// - a live subscription to `syncStatusProvider` so the listener fires
  ({
    StreamController<SyncEvent> controller,
    ProviderContainer container,
    ProviderSubscription<SyncStatus> subscription,
    ProviderSubscription<AsyncValue<SyncEvent>> eventSubscription,
    int Function() drainCount,
  }) bindContainer() {
    // ignore: close_sinks
    final controller = StreamController<SyncEvent>.broadcast();
    var count = 0;
    debugDrainRustStoreOverride = () async {
      count++;
    };
    debugDrainDebounceOverride = testDebounce;
    final container = ProviderContainer(
      overrides: [
        syncEventStreamProvider.overrideWith((ref) => controller.stream),
        syncQuarantineServiceProvider.overrideWithValue(
          _FakeQuarantineService(),
        ),
      ],
    );
    // Keep an active subscription on both providers. `container.listen`
    // creates a live subscriber, unlike `container.read` which is a
    // one-shot query. The StreamProvider only subscribes to its stream
    // while something is actively listening.
    final eventSub = container.listen<AsyncValue<SyncEvent>>(
      syncEventStreamProvider,
      (prev, next) {},
    );
    final sub = container.listen<SyncStatus>(
      syncStatusProvider,
      (prev, next) {},
    );
    return (
      controller: controller,
      container: container,
      subscription: sub,
      eventSubscription: eventSub,
      drainCount: () => count,
    );
  }

  tearDown(() {
    debugDrainRustStoreOverride = null;
    debugDrainRustStoreOverrideWithAbort = null;
    debugDrainDebounceOverride = null;
    debugPostRevokeRecleanOverride = null;
    debugPostRevokeRecleanOverrideCallback = null;
    debugQueryPendingOpsOverride = null;
  });

  SyncEvent completedEvent({String? errorKind, String? errorMessage}) {
    return SyncEvent('SyncCompleted', {
      'type': 'SyncCompleted',
      'result': {
        'pulled': 0,
        'merged': 0,
        'pushed': 0,
        'pruned': 0,
        'duration_ms': 0,
        'error': errorMessage,
        'error_kind': errorKind,
      },
    });
  }

  test('drain fires on SyncCompleted success after debounce', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(completedEvent());
    // Let the stream deliver and listener schedule the timer.
    await Future<void>.delayed(Duration.zero);
    expect(ctx.drainCount(), 0,
        reason: 'drain must not fire before debounce elapses');

    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 1, reason: 'drain must fire after debounce');
  });

  test('drain fires on EpochRotated event', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(
      SyncEvent('EpochRotated', {'type': 'EpochRotated', 'epoch': 2}),
    );
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 1);
  });

  test('drain is SKIPPED on Auth error SyncCompleted', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(
      completedEvent(errorKind: 'Auth', errorMessage: 'auth failed'),
    );
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 0);
  });

  test('drain is SKIPPED on KeyChanged error SyncCompleted', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(
      completedEvent(errorKind: 'KeyChanged', errorMessage: 'key changed'),
    );
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 0);
  });

  test('drain fires on Network-error SyncCompleted (transient)', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(
      completedEvent(errorKind: 'Network', errorMessage: 'timeout'),
    );
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 1);
  });

  test('5 rapid events coalesce into a single drain within the window',
      () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    for (var i = 0; i < 5; i++) {
      ctx.controller.add(completedEvent());
    }
    // Before the debounce window expires the drain must not have fired.
    await Future<void>.delayed(Duration.zero);
    expect(ctx.drainCount(), 0);

    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 1,
        reason:
            'trailing-edge debouncer should coalesce burst into exactly 1 drain');
  });

  test('spaced events produce separate drains', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(completedEvent());
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 1);

    // Give enough real time between bursts that the first debounce
    // timer has fired and is gone.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    ctx.controller.add(completedEvent());
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 2);
  });

  test('SyncStarted / Error events do not schedule a drain', () async {
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(SyncEvent('SyncStarted', {'type': 'SyncStarted'}));
    ctx.controller.add(SyncEvent('Error', {
      'type': 'Error',
      'kind': 'Network',
      'message': 'pull failed',
    }));
    await Future<void>.delayed(settleAfterDebounce);
    expect(ctx.drainCount(), 0);
  });

  test('terminal Error wins over delayed SyncStarted status refresh', () async {
    final pendingOps = Completer<int>();
    debugQueryPendingOpsOverride = () => pendingOps.future;
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(SyncEvent('SyncStarted', {'type': 'SyncStarted'}));
    await Future<void>.delayed(Duration.zero);
    expect(ctx.container.read(syncStatusProvider).isSyncing, isTrue);

    ctx.controller.add(
      SyncEvent('Error', {
        'type': 'Error',
        'kind': 'EpochRotation',
        'message': 'epoch mismatch',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(ctx.container.read(syncStatusProvider).isSyncing, isFalse);

    pendingOps.complete(7);
    await Future<void>.delayed(Duration.zero);

    final status = ctx.container.read(syncStatusProvider);
    expect(status.isSyncing, isFalse);
    expect(status.pendingOps, 0);
    expect(status.lastError, 'epoch mismatch');
  });

  // ------------------------------------------------------------------
  // Fix 2: device_revoked arriving via SyncCompleted.result.error_code
  // ------------------------------------------------------------------

  SyncEvent revokedCompletedEvent({bool remoteWipe = true}) {
    return SyncEvent('SyncCompleted', {
      'type': 'SyncCompleted',
      'result': {
        'pulled': 0,
        'merged': 0,
        'pushed': 0,
        'pruned': 0,
        'duration_ms': 0,
        'error': 'device_revoked',
        'error_kind': 'Auth',
        'error_code': 'device_revoked',
        'remote_wipe': remoteWipe,
      },
    });
  }

  test('SyncCompleted with error_code=device_revoked skips the drain',
      () async {
    // The Rust engine may wrap a 401 device-revoked response into an
    // `Ok(result)` branch. The Dart side must detect this via the new
    // `error_code` field on the result payload and NOT schedule a
    // drain (the cleanup path wipes credentials and we must not write
    // them back). See Fix 2 of the 2026-04-11 robustness plan.
    final ctx = bindContainer();
    addTearDown(() async {
      ctx.subscription.close();
      ctx.eventSubscription.close();
      ctx.container.dispose();
      await ctx.controller.close();
    });

    ctx.controller.add(revokedCompletedEvent(remoteWipe: false));
    await Future<void>.delayed(settleAfterDebounce);
    expect(
      ctx.drainCount(),
      0,
      reason:
          'device_revoked via result.error_code must NOT schedule a drain',
    );
  });

  // ------------------------------------------------------------------
  // Fix 1: a pending drain must not resurrect credentials after revoke
  // ------------------------------------------------------------------

  test(
    'pending debounced drain is cancelled when device_revoked arrives',
    () async {
      // Sequence: success SyncCompleted schedules a drain; BEFORE the
      // debounce window elapses, a revoked SyncCompleted arrives. The
      // scheduled drain must be cancelled so `drainRustStore` never
      // runs against a wiped keychain. See Fix 1 of the 2026-04-11
      // robustness plan.
      final ctx = bindContainer();
      addTearDown(() async {
        ctx.subscription.close();
        ctx.eventSubscription.close();
        ctx.container.dispose();
        await ctx.controller.close();
      });

      ctx.controller.add(completedEvent());
      // Do NOT wait for the debounce — the drain is pending.
      await Future<void>.delayed(Duration.zero);
      expect(ctx.drainCount(), 0);

      // Revocation arrives while the drain is still queued.
      ctx.controller.add(revokedCompletedEvent(remoteWipe: false));
      await Future<void>.delayed(settleAfterDebounce);

      expect(
        ctx.drainCount(),
        0,
        reason:
            'pending drain must be cancelled by the revocation, not fire 500ms later',
      );
    },
  );

  test(
    'subsequent success events after revoke still do not resurrect the drain',
    () async {
      // Even if a stray SyncCompleted arrives after revocation (e.g. a
      // race between the WebSocket revoke notification and an in-flight
      // engine cycle), the drain must stay suppressed until a fresh
      // handle is created. The `_credentialsRevoked` gate in
      // `SyncStatusNotifier` is what makes this work.
      final ctx = bindContainer();
      addTearDown(() async {
        ctx.subscription.close();
        ctx.eventSubscription.close();
        ctx.container.dispose();
        await ctx.controller.close();
      });

      // Trigger revocation first.
      ctx.controller.add(revokedCompletedEvent(remoteWipe: false));
      await Future<void>.delayed(settleAfterDebounce);
      expect(ctx.drainCount(), 0);

      // Stray success event while we're already in the revoked state.
      ctx.controller.add(completedEvent());
      await Future<void>.delayed(settleAfterDebounce);
      expect(
        ctx.drainCount(),
        0,
        reason:
            'post-revoke success must not re-arm the drain until a new handle exists',
      );
    },
  );

  // ------------------------------------------------------------------
  // Fix 5: async drain race tests (Round 3)
  //
  // Prior tests only prove that a PENDING timer is cancelled on
  // revocation. These tests exercise the scenario where the drain
  // has already fired and is awaiting mid-write when revocation
  // lands, proving:
  //
  //   Test A: the notifier's `shouldAbort` closure flips mid-drain,
  //           and the drain callback observes the flip and bails.
  //   Test B: `applyDrainedEntries` (pure core of `drainRustStore`)
  //           short-circuits its write loop when `shouldAbort` flips.
  //   Test C: `_abortPendingDrainForRevoke`'s delayed belt-and-suspenders
  //           re-cleanup fires after the configured delay and calls
  //           `_wipeSyncKeychainEntries` (via the test override).
  // ------------------------------------------------------------------

  test(
    'Test A: in-flight drain observes shouldAbort flip mid-drain',
    () async {
      // Use the abort-aware override so we can hold a drain in-flight
      // and inspect `shouldAbort` before and after revocation fires.
      final drainStarted = Completer<void>();
      final releaseDrain = Completer<void>();
      bool? shouldAbortBeforeRevoke;
      bool? shouldAbortAfterRevoke;

      debugDrainRustStoreOverride = null;
      debugDrainRustStoreOverrideWithAbort = (shouldAbort) async {
        // Sample the gate on entry.
        shouldAbortBeforeRevoke = shouldAbort();
        drainStarted.complete();
        // Hold in-flight until the test releases us.
        await releaseDrain.future;
        // Sample again after the test has fired revocation.
        shouldAbortAfterRevoke = shouldAbort();
      };
      debugDrainDebounceOverride = testDebounce;

      // We reuse the normal fake quarantine + event stream setup.
      final controller = StreamController<SyncEvent>.broadcast();
      final container = ProviderContainer(
        overrides: [
          syncEventStreamProvider.overrideWith((ref) => controller.stream),
          syncQuarantineServiceProvider.overrideWithValue(
            _FakeQuarantineService(),
          ),
        ],
      );
      final eventSub = container.listen<AsyncValue<SyncEvent>>(
        syncEventStreamProvider,
        (prev, next) {},
      );
      final sub = container.listen<SyncStatus>(
        syncStatusProvider,
        (prev, next) {},
      );
      addTearDown(() async {
        sub.close();
        eventSub.close();
        container.dispose();
        await controller.close();
      });

      // Fire a success event → scheduleDrain → timer → our override.
      controller.add(completedEvent());
      await drainStarted.future.timeout(const Duration(seconds: 2));
      expect(
        shouldAbortBeforeRevoke,
        isFalse,
        reason: 'shouldAbort must be false before revocation',
      );

      // Now fire a revoked-result SyncCompleted. This hits
      // `_handleDeviceRevokedFromAuthFailure` which calls
      // `_abortPendingDrainForRevoke()`, bumping the drain generation.
      controller.add(revokedCompletedEvent(remoteWipe: false));
      // Let the listener process the event.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Release the in-flight drain so it can sample `shouldAbort`
      // again after the generation bump.
      releaseDrain.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(
        shouldAbortAfterRevoke,
        isTrue,
        reason:
            'shouldAbort must flip to true after revocation bumps the generation',
      );
    },
  );

  test(
    'Test B: applyDrainedEntries short-circuits writes when shouldAbort flips',
    () async {
      // Direct unit test of the pure helper. The first write succeeds,
      // then we flip `shouldAbort` to true via a mutable flag, then
      // assert that no further writes land. This proves the
      // per-iteration abort check actually short-circuits the loop.
      var abortNow = false;
      final deleted = <String>[];
      final written = <MapEntry<String, String>>[];

      final entries = {
        'wrapped_dek': 'd3JhcA==',
        'dek_salt': 'c2FsdA==',
        'device_id': 'ZGV2',
        'sync_id': 'c3luYw==',
        'session_token': 'dG9rZW4=',
        'epoch_key_1': 'a2V5MQ==',
      };

      final committed = await applyDrainedEntries(
        entries: entries,
        deleteKey: (full) async {
          deleted.add(full);
        },
        writeKey: (full, value) async {
          written.add(MapEntry(full, value));
          // Flip the abort gate after the very first write. Every
          // subsequent iteration must observe the flip and bail.
          abortNow = true;
        },
        shouldAbort: () => abortNow,
      );

      expect(
        written.length,
        1,
        reason:
            'only one write should commit before shouldAbort flips; got: $written',
      );
      expect(
        committed,
        1,
        reason: 'applyDrainedEntries should report 1 committed write',
      );
      // The delete loop ran before the first write (possibly empty
      // depending on entries vs _secureStoreKeys), but more importantly
      // the remaining writes in `entries` must NOT have landed.
      expect(
        written.length < entries.length,
        isTrue,
        reason: 'the write loop must have short-circuited early',
      );
    },
  );

  test(
    'Test B2: applyDrainedEntries respects pre-loop shouldAbort',
    () async {
      // If `shouldAbort` is already `true` before entering the loop,
      // no mutations should occur at all.
      final deleted = <String>[];
      final written = <MapEntry<String, String>>[];
      final committed = await applyDrainedEntries(
        entries: const {
          'wrapped_dek': 'x',
          'epoch_key_1': 'y',
        },
        deleteKey: (full) async {
          deleted.add(full);
        },
        writeKey: (full, value) async {
          written.add(MapEntry(full, value));
        },
        shouldAbort: () => true,
      );
      expect(committed, 0);
      expect(deleted, isEmpty);
      expect(written, isEmpty);
    },
  );

  test(
    'Test C: post-revoke delayed re-cleanup fires after abort',
    () async {
      // The belt-and-suspenders cleanup must fire ~2s after
      // `_abortPendingDrainForRevoke()` so a drain whose writes landed
      // after the main wipe gets re-wiped.
      var recleanCalls = 0;
      debugPostRevokeRecleanOverrideCallback = () async {
        recleanCalls++;
      };
      // Tiny delay so the test doesn't wait 2 real seconds.
      debugPostRevokeRecleanOverride = const Duration(milliseconds: 20);
      debugDrainDebounceOverride = testDebounce;

      final ctx = bindContainer();
      addTearDown(() async {
        ctx.subscription.close();
        ctx.eventSubscription.close();
        ctx.container.dispose();
        await ctx.controller.close();
      });

      // Fire a revoked-result SyncCompleted; the notifier calls
      // `_handleDeviceRevokedFromAuthFailure` -> `_abortPendingDrainForRevoke`
      // which schedules the delayed re-cleanup.
      ctx.controller.add(revokedCompletedEvent(remoteWipe: false));
      // Before the delay elapses, no re-cleanup has fired.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Wait past the override delay.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        recleanCalls,
        greaterThanOrEqualTo(1),
        reason: 'post-revoke re-cleanup must fire',
      );
    },
  );

  test(
    'Test C2: post-revoke re-cleanup skips if a fresh handle appeared first',
    () async {
      // If a new handle is created between the abort and the delayed
      // timer firing, the notifier resets `_credentialsRevoked = false`
      // and the re-cleanup callback bails early (via the `if
      // (!_credentialsRevoked) return;` check). Simulating this in a
      // pure unit test would require handle-override plumbing that
      // doesn't exist in the test harness; the code path is covered by
      // the production gate: `if (!_credentialsRevoked) return;`.
      //
      // Instead, confirm the reverse invariant: manually toggling
      // `_credentialsRevoked` back to false via the test helper
      // suppresses the re-cleanup, even when the timer had been
      // scheduled. This uses the same escape route that the live
      // `prismSyncHandleProvider` listener takes.
      var recleanCalls = 0;
      debugPostRevokeRecleanOverrideCallback = () async {
        recleanCalls++;
      };
      debugPostRevokeRecleanOverride = const Duration(milliseconds: 20);
      debugDrainDebounceOverride = testDebounce;

      final ctx = bindContainer();
      addTearDown(() async {
        ctx.subscription.close();
        ctx.eventSubscription.close();
        ctx.container.dispose();
        await ctx.controller.close();
      });

      ctx.controller.add(revokedCompletedEvent(remoteWipe: false));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Simulate "fresh handle appeared" by resetting the flag.
      final notifier = ctx.container.read(syncStatusProvider.notifier);
      notifier.debugResetCredentialsRevoked();

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        recleanCalls,
        0,
        reason:
            'if a new handle resets _credentialsRevoked before the delay, '
            're-cleanup must be suppressed',
      );
    },
  );

  // ------------------------------------------------------------------
  // Round 4 Fix 2: generation is never reset — stale drains stay stale
  // even after a fresh handle appears.
  // ------------------------------------------------------------------

  test(
    'stale drain after fresh handle respects monotonic generation',
    () async {
      // Scenario that reproduces the Round 3 bug:
      //   1. Schedule drain at generation 0
      //   2. Hold drain in-flight via the abort-aware override
      //   3. Fire revoke → generation bumps to 1
      //   4. Simulate fresh handle → flag clears (but generation stays 1)
      //   5. Release the in-flight drain
      //   6. Assert shouldAbort is true (myGeneration 0 != _drainGeneration 1)
      //
      // Without Fix 2, generation was reset to 0 at step 4, so the stale
      // drain's captured `myGeneration = 0` would match and proceed.
      final drainStarted = Completer<void>();
      final releaseDrain = Completer<void>();
      bool? shouldAbortAfterRelease;

      debugDrainRustStoreOverrideWithAbort = (shouldAbort) async {
        drainStarted.complete();
        await releaseDrain.future;
        shouldAbortAfterRelease = shouldAbort();
      };
      debugDrainDebounceOverride = testDebounce;

      final controller = StreamController<SyncEvent>.broadcast();
      final container = ProviderContainer(
        overrides: [
          syncEventStreamProvider.overrideWith((ref) => controller.stream),
          syncQuarantineServiceProvider.overrideWithValue(
            _FakeQuarantineService(),
          ),
        ],
      );
      final eventSub = container.listen<AsyncValue<SyncEvent>>(
        syncEventStreamProvider,
        (prev, next) {},
      );
      final sub = container.listen<SyncStatus>(
        syncStatusProvider,
        (prev, next) {},
      );
      addTearDown(() async {
        sub.close();
        eventSub.close();
        container.dispose();
        await controller.close();
      });

      // 1. Schedule a drain (captured myGeneration = 0).
      controller.add(completedEvent());
      await drainStarted.future.timeout(const Duration(seconds: 2));

      // 3. Revoke fires → generation bumps.
      controller.add(revokedCompletedEvent(remoteWipe: false));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 4. Simulate fresh handle → flag clears, generation stays.
      final notifier = container.read(syncStatusProvider.notifier);
      notifier.debugResetCredentialsRevoked();

      // 5. Release the stale drain.
      releaseDrain.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // 6. The stale drain must see shouldAbort == true because
      //    `_drainGeneration` (bumped to >=1) != `myGeneration` (0).
      expect(
        shouldAbortAfterRelease,
        isTrue,
        reason:
            'stale drain must abort even after fresh-handle reset, because '
            'generation is monotonic and was bumped by the revoke '
            '(_drainGeneration >= 1 != myGeneration 0)',
      );
    },
  );
}
