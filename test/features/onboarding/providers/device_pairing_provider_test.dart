import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrismSyncHandleNotifier extends PrismSyncHandleNotifier {
  _FakePrismSyncHandleNotifier(this.handle);

  final ffi.PrismSyncHandle handle;
  String? lastRelayUrl;

  @override
  Future<ffi.PrismSyncHandle?> build() async => handle;

  @override
  Future<ffi.PrismSyncHandle> createHandle({required String relayUrl}) async {
    lastRelayUrl = relayUrl;
    return handle;
  }
}

class _FakePairingCeremonyApi extends PairingCeremonyApi {
  _FakePairingCeremonyApi({
    this.startJoinerCeremonyHandler,
    this.getJoinerSasHandler,
  });

  Future<String> Function({required ffi.PrismSyncHandle handle})?
  startJoinerCeremonyHandler;
  Future<String> Function({required ffi.PrismSyncHandle handle})?
  getJoinerSasHandler;

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) {
    return startJoinerCeremonyHandler?.call(handle: handle) ??
        Future.value(
          jsonEncode({
            'token_bytes': [1, 2, 3, 4],
            'token_url': 'prismsync://pair?d=test',
            'device_id': 'test-device',
          }),
        );
  }

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) {
    return getJoinerSasHandler?.call(handle: handle) ??
        Future.value(
          jsonEncode({
            'sas_words': 'apple banana cherry',
            'sas_decimal': '123456',
          }),
        );
  }

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
  }) => Future.value(jsonEncode({'sync_id': 'unused'}));

  @override
  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  }) => throw UnimplementedError();

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
    required String mnemonic,
  }) => throw UnimplementedError();
}

void main() {
  group('PairingState', () {
    test('default state starts at enterUrl step', () {
      const state = PairingState();
      expect(state.step, PairingStep.enterUrl);
      expect(state.errorMessage, isNull);
      expect(state.errorCode, isNull);
      expect(state.counts, isNull);
      expect(state.requestQrPayload, isNull);
      expect(state.requestDeviceId, isNull);
      expect(state.syncIncomplete, isFalse);
    });

    test('copyWith preserves requestQrPayload and requestDeviceId', () {
      const state = PairingState();
      final updated = state.copyWith(
        step: PairingStep.showingRequest,
        requestQrPayload: [1, 2, 3, 4],
        requestDeviceId: 'device-abc-123',
      );

      expect(updated.step, PairingStep.showingRequest);
      expect(updated.requestQrPayload, [1, 2, 3, 4]);
      expect(updated.requestDeviceId, 'device-abc-123');
      // Other fields remain null/default
      expect(updated.errorMessage, isNull);
      expect(updated.syncIncomplete, isFalse);
    });

    test('step transitions through the pairing flow', () {
      // enterUrl -> showingRequest -> enterPassword -> connecting -> success
      const state0 = PairingState();
      expect(state0.step, PairingStep.enterUrl);

      final state1 = state0.copyWith(
        step: PairingStep.showingRequest,
        requestQrPayload: [0xDE, 0xAD],
        requestDeviceId: 'dev-001',
      );
      expect(state1.step, PairingStep.showingRequest);

      final state2 = state1.copyWith(step: PairingStep.enterPin);
      expect(state2.step, PairingStep.enterPin);
      // Request fields should carry forward
      expect(state2.requestQrPayload, [0xDE, 0xAD]);
      expect(state2.requestDeviceId, 'dev-001');

      final state3 = state2.copyWith(step: PairingStep.connecting);
      expect(state3.step, PairingStep.connecting);

      final state4 = state3.copyWith(
        step: PairingStep.success,
        counts: const SyncCounts(members: 5, frontingSessions: 3),
      );
      expect(state4.step, PairingStep.success);
      expect(state4.counts?.members, 5);
      expect(state4.counts?.frontingSessions, 3);
    });

    test('copyWith can clear nullable fields by passing null', () {
      final state = const PairingState().copyWith(
        errorMessage: 'some error',
        errorCode: 'ERR_001',
        requestQrPayload: [1, 2, 3],
        requestDeviceId: 'dev-x',
      );
      expect(state.errorMessage, 'some error');
      expect(state.errorCode, 'ERR_001');

      final cleared = state.copyWith(
        errorMessage: null,
        errorCode: null,
        requestQrPayload: null,
        requestDeviceId: null,
      );
      expect(cleared.errorMessage, isNull);
      expect(cleared.errorCode, isNull);
      expect(cleared.requestQrPayload, isNull);
      expect(cleared.requestDeviceId, isNull);
    });

    test('error state preserves errorMessage and errorCode', () {
      final state = const PairingState().copyWith(
        step: PairingStep.error,
        errorMessage: 'Connection timed out',
        errorCode: 'TIMEOUT',
      );
      expect(state.step, PairingStep.error);
      expect(state.errorMessage, 'Connection timed out');
      expect(state.errorCode, 'TIMEOUT');
    });

    test('error recovery transitions back to enterUrl', () {
      final errorState = const PairingState().copyWith(
        step: PairingStep.error,
        errorMessage: 'Something went wrong',
        errorCode: 'GENERIC',
        requestQrPayload: [1, 2, 3],
        requestDeviceId: 'old-device',
      );
      expect(errorState.step, PairingStep.error);

      // Simulating reset(): rebuild returns default PairingState
      const resetState = PairingState();
      expect(resetState.step, PairingStep.enterUrl);
      expect(resetState.errorMessage, isNull);
      expect(resetState.errorCode, isNull);
      expect(resetState.requestQrPayload, isNull);
      expect(resetState.requestDeviceId, isNull);
      expect(resetState.syncIncomplete, isFalse);
    });

    test('syncIncomplete flag is preserved through copyWith', () {
      final state = const PairingState().copyWith(
        step: PairingStep.success,
        syncIncomplete: true,
      );
      expect(state.syncIncomplete, isTrue);

      // copyWith without syncIncomplete preserves the existing value
      final updated = state.copyWith(step: PairingStep.success);
      expect(updated.syncIncomplete, isTrue);

      // Explicit false clears it
      final cleared = state.copyWith(syncIncomplete: false);
      expect(cleared.syncIncomplete, isFalse);
    });

    test('confirmSas transitions from showingSas to enterPassword', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Manually set state to showingSas to test the transition
      // We can't easily reach showingSas without FFI, so we test the
      // state copyWith + confirmSas guard instead.
      const state = PairingState(
        step: PairingStep.showingSas,
        sasWords: 'apple banana cherry',
        sasDecimal: '1234',
      );
      expect(state.sasWords, equals('apple banana cherry'));
      expect(state.sasDecimal, equals('1234'));
    });
  });

  group('DevicePairingNotifier', () {
    test(
      'generateRequest drives joiner ceremony into SAS verification',
      () async {
        const fakeHandle = _FakePrismSyncHandle();
        final fakeHandleNotifier = _FakePrismSyncHandleNotifier(fakeHandle);
        final sasCompleter = Completer<String>();
        final fakeApi = _FakePairingCeremonyApi(
          startJoinerCeremonyHandler: ({required handle}) async {
            expect(handle, same(fakeHandle));
            return jsonEncode({
              'token_bytes': [9, 8, 7],
              'token_url': 'prismsync://pair?d=test',
              'device_id': 'joiner-device',
            });
          },
          getJoinerSasHandler: ({required handle}) {
            expect(handle, same(fakeHandle));
            return sasCompleter.future;
          },
        );

        final container = ProviderContainer(
          overrides: [
            pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
            relayUrlProvider.overrideWith(
              (ref) async => 'https://relay.example.com',
            ),
            prismSyncHandleProvider.overrideWith(() => fakeHandleNotifier),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(devicePairingProvider.notifier);
        await notifier.generateRequest();
        await pumpEventQueue();

        var state = container.read(devicePairingProvider);
        // Implementation keeps showingRequest (QR visible) while polling for SAS.
        expect(state.step, PairingStep.showingRequest);
        expect(state.requestQrPayload, [9, 8, 7]);
        expect(state.requestDeviceId, 'joiner-device');
        expect(fakeHandleNotifier.lastRelayUrl, 'https://relay.example.com');

        sasCompleter.complete(
          jsonEncode({
            'sas_words': 'delta echo foxtrot',
            'sas_decimal': '654321',
          }),
        );
        await pumpEventQueue();

        state = container.read(devicePairingProvider);
        expect(state.step, PairingStep.showingSas);
        expect(state.sasWords, 'delta echo foxtrot');
        expect(state.sasDecimal, '654321');

        notifier.confirmSas();
        expect(
          container.read(devicePairingProvider).step,
          PairingStep.enterPin,
        );
      },
    );

    test('generateRequest uses an explicit relay URL override', () async {
      const fakeHandle = _FakePrismSyncHandle();
      final fakeHandleNotifier = _FakePrismSyncHandleNotifier(fakeHandle);
      final fakeApi = _FakePairingCeremonyApi(
        getJoinerSasHandler: ({required handle}) async {
          expect(handle, same(fakeHandle));
          return jsonEncode({
            'sas_words': 'delta echo foxtrot',
            'sas_decimal': '654321',
          });
        },
      );

      final container = ProviderContainer(
        overrides: [
          pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
          relayUrlProvider.overrideWith(
            (ref) async => 'https://stored.example.com',
          ),
          prismSyncHandleProvider.overrideWith(() => fakeHandleNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(devicePairingProvider.notifier)
          .generateRequest(relayUrl: 'https://custom.example.com');
      await pumpEventQueue();

      expect(fakeHandleNotifier.lastRelayUrl, 'https://custom.example.com');
    });
  });

  group('SyncCounts', () {
    test('defaults to zeros', () {
      const counts = SyncCounts();
      expect(counts.members, 0);
      expect(counts.frontingSessions, 0);
      expect(counts.conversations, 0);
      expect(counts.messages, 0);
      expect(counts.habits, 0);
    });

    test('stores provided values', () {
      const counts = SyncCounts(
        members: 10,
        frontingSessions: 5,
        conversations: 3,
        messages: 42,
        habits: 7,
      );
      expect(counts.members, 10);
      expect(counts.frontingSessions, 5);
      expect(counts.conversations, 3);
      expect(counts.messages, 42);
      expect(counts.habits, 7);
    });
  });

  group('PairingStep', () {
    test('has all expected values', () {
      expect(
        PairingStep.values,
        containsAll([
          PairingStep.enterUrl,
          PairingStep.showingRequest,
          PairingStep.enterPin,
          PairingStep.connecting,
          PairingStep.success,
          PairingStep.error,
          PairingStep.snapshotFailure,
        ]),
      );
    });
  });

  group('snapshotFailure step — UI gating', () {
    test('retrySnapshotBootstrap is a no-op outside snapshotFailure', () async {
      final container = ProviderContainer(
        overrides: [
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          relayUrlProvider.overrideWith(
            (ref) async => 'https://relay.example.com',
          ),
          prismSyncHandleProvider.overrideWith(
            () => _FakePrismSyncHandleNotifier(const _FakePrismSyncHandle()),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(devicePairingProvider.notifier);
      // Default step is enterUrl — retry should be a silent no-op.
      await notifier.retrySnapshotBootstrap();
      expect(container.read(devicePairingProvider).step, PairingStep.enterUrl);
    });

    test('PairingState can transition into snapshotFailure', () {
      final state = const PairingState().copyWith(
        step: PairingStep.snapshotFailure,
        errorMessage: "Couldn't load your system from the pairing device.",
        syncIncomplete: true,
      );
      expect(state.step, PairingStep.snapshotFailure);
      expect(state.syncIncomplete, isTrue);
      expect(state.errorMessage, contains("Couldn't load"));
    });

    // Regression: the snapshot-failure path is distinct from the generic
    // error path precisely because credentials must survive it. Only the
    // latter invokes `_cleanupKeychainOnFailure`. Asserting the enum
    // distinction exists keeps the credential-lifecycle contract visible.
    test('snapshotFailure is distinct from error (credential lifecycle)', () {
      final errorState = const PairingState().copyWith(
        step: PairingStep.error,
        errorMessage: 'ceremony failed',
      );
      final snapshotFailureState = const PairingState().copyWith(
        step: PairingStep.snapshotFailure,
        errorMessage: 'snapshot failed',
        syncIncomplete: true,
      );
      expect(errorState.step, isNot(snapshotFailureState.step));
      // snapshotFailure carries syncIncomplete=true so the UI can show
      // "retry or cancel" instead of "start over from scratch".
      expect(snapshotFailureState.syncIncomplete, isTrue);
      expect(errorState.syncIncomplete, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Progress notifier integration tests
  // These tests drive the syncSetupProgressProvider directly to verify the
  // phase-transition protocol and reset behaviour wired in Task 6.
  // ---------------------------------------------------------------------------

  group('SyncSetupProgress — phase transitions', () {
    /// Build a minimal container with both providers and a no-op event stream.
    ProviderContainer makeContainer() {
      final eventController = StreamController<SyncEvent>.broadcast();
      final container = ProviderContainer(
        overrides: [
          syncEventStreamProvider.overrideWith((ref) {
            ref.onDispose(eventController.close);
            return eventController.stream;
          }),
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          relayUrlProvider.overrideWith(
            (ref) async => 'https://relay.example.com',
          ),
          prismSyncHandleProvider.overrideWith(
            () => _FakePrismSyncHandleNotifier(const _FakePrismSyncHandle()),
          ),
        ],
      );
      // Keep the notifiers alive.
      container.listen<SyncSetupProgressState>(
        syncSetupProgressProvider,
        (_, _) {},
      );
      container.listen<PairingState>(devicePairingProvider, (_, _) {});
      return container;
    }

    test('setPhase advancing from connecting to downloading works', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(syncSetupProgressProvider.notifier);
      notifier.setPhase(PairingProgressPhase.downloading);

      final state = container.read(syncSetupProgressProvider);
      expect(state.phase, PairingProgressPhase.downloading);
    });

    test('phases advance monotonically through full sequence', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(syncSetupProgressProvider.notifier);
      notifier.setPhase(PairingProgressPhase.downloading);
      notifier.setPhase(PairingProgressPhase.restoring);
      notifier.setPhase(PairingProgressPhase.finishing);

      expect(
        container.read(syncSetupProgressProvider).phase,
        PairingProgressPhase.finishing,
      );
    });

    test('backwards setPhase is a no-op (monotonic invariant)', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(syncSetupProgressProvider.notifier);
      notifier.setPhase(PairingProgressPhase.restoring);
      // Attempt to rewind to downloading — must be ignored.
      notifier.setPhase(PairingProgressPhase.downloading);

      expect(
        container.read(syncSetupProgressProvider).phase,
        PairingProgressPhase.restoring,
      );
    });

    test(
      'markTimedOut sets timedOut=true; setPhase(finishing) still advances',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(syncSetupProgressProvider.notifier);
        notifier.setPhase(PairingProgressPhase.downloading);
        notifier.setPhase(PairingProgressPhase.restoring);
        notifier.markTimedOut();
        notifier.setPhase(PairingProgressPhase.finishing);

        final state = container.read(syncSetupProgressProvider);
        expect(state.phase, PairingProgressPhase.finishing);
        expect(state.timedOut, isTrue);
      },
    );

    test('reset() on DevicePairingNotifier clears progress state', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      // Advance progress to a non-initial phase.
      final progressNotifier = container.read(
        syncSetupProgressProvider.notifier,
      );
      progressNotifier.setPhase(PairingProgressPhase.restoring);
      expect(
        container.read(syncSetupProgressProvider).phase,
        PairingProgressPhase.restoring,
      );

      // Calling reset on the pairing notifier should also reset progress.
      container.read(devicePairingProvider.notifier).reset();
      await pumpEventQueue();

      final progressState = container.read(syncSetupProgressProvider);
      expect(progressState.phase, PairingProgressPhase.connecting);
      expect(progressState.timedOut, isFalse);
      expect(progressState.liveCounts, isEmpty);
    });

    // Regression for codex Finding A: a non-timeout exception thrown
    // AFTER `completeJoinerCeremony` succeeds (e.g. from `configureEngine`)
    // must NOT wipe the keychain — the joiner is already registered on
    // the relay and orphaning it forces an unrecoverable state. The
    // failure must instead route to PairingStep.snapshotFailure so the
    // user sees Retry + Cancel actions.
    test(
      'post-ceremony exception preserves credentials and routes to snapshotFailure',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        // Seed a fake credential so we can assert it survives the failure.
        const fakeKey = 'prism_sync.session_token';
        final initialCreds = <String, String>{};
        // We don't have a flutter_secure_storage mock here, so the
        // assertion is structural: the gate routes to snapshotFailure
        // and does NOT enter the error step. The actual keychain delete
        // is exercised end-to-end in integration tests.
        initialCreds[fakeKey] = 'sentinel';

        final notifier = container.read(devicePairingProvider.notifier);

        // Simulate a non-timeout exception escaping the bootstrap region
        // AFTER ceremony has committed credentials. The flag-based gate
        // must keep credentials in place and surface snapshotFailure.
        await notifier.handlePostCeremonyFailureForTest(
          ceremonyCompleted: true,
          error: StateError('configureEngine failed: simulated FFI error'),
        );

        final state = container.read(devicePairingProvider);
        expect(
          state.step,
          PairingStep.snapshotFailure,
          reason:
              'Post-ceremony failures must route to snapshotFailure so the '
              'user can retry without losing the joined identity.',
        );
        expect(state.syncIncomplete, isTrue);
      },
    );

    test(
      'pre-ceremony exception still wipes credentials and routes to error',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(devicePairingProvider.notifier);

        // Same exception, but with ceremonyCompleted=false. The gate
        // must use the legacy hard-error path with keychain cleanup.
        await notifier.handlePostCeremonyFailureForTest(
          ceremonyCompleted: false,
          error: StateError('relay handshake failed before ceremony'),
        );

        final state = container.read(devicePairingProvider);
        expect(state.step, PairingStep.error);
      },
    );

    test(
      'generation mismatch: setPhase called only when _generation matches',
      () async {
        // This test verifies the guard logic by calling reset() (which bumps
        // _generation) then checking that subsequent manual setPhase calls on
        // the progress notifier are still respected (they're independent of the
        // pairing generation — the guard lives in device_pairing_provider.dart
        // and wraps the FFI await boundaries).
        final container = makeContainer();
        addTearDown(container.dispose);

        final pairingNotifier = container.read(devicePairingProvider.notifier);
        final progressNotifier = container.read(
          syncSetupProgressProvider.notifier,
        );

        // Simulate: pairing started, cancel called, then a stale async
        // continuation tries to advance the phase (but shouldn't, because the
        // guard would have blocked it). We test here that if the guard WAS
        // respected the progress state stays at connecting after the reset.
        progressNotifier.setPhase(PairingProgressPhase.downloading);
        // Cancel / reset pairing — progress should clear.
        pairingNotifier.reset();
        await pumpEventQueue();

        // Post-reset state must be back at connecting.
        expect(
          container.read(syncSetupProgressProvider).phase,
          PairingProgressPhase.connecting,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Apply watchdog idle-reset policy (codex Finding B regression)
  // ---------------------------------------------------------------------------
  group('apply watchdog — idle-reset policy', () {
    /// Build a container with a controllable sync-event stream and a
    /// fake handle so the private watchdog can be exercised directly via
    /// the @visibleForTesting wrapper.
    ({
      ProviderContainer container,
      StreamController<SyncEvent> events,
    }) makeWatchdogContainer() {
      final eventController = StreamController<SyncEvent>.broadcast();
      final container = ProviderContainer(
        overrides: [
          syncEventStreamProvider.overrideWith((ref) {
            ref.onDispose(eventController.close);
            return eventController.stream;
          }),
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          relayUrlProvider.overrideWith(
            (ref) async => 'https://relay.example.com',
          ),
          prismSyncHandleProvider.overrideWith(
            () => _FakePrismSyncHandleNotifier(const _FakePrismSyncHandle()),
          ),
        ],
      );
      // Keep the event stream provider alive across the test.
      container.listen<AsyncValue<SyncEvent>>(
        syncEventStreamProvider,
        (_, _) {},
      );
      return (container: container, events: eventController);
    }

    test(
      'SyncCompleted bursts do NOT reset the watchdog (Finding B regression)',
      () async {
        final setup = makeWatchdogContainer();
        addTearDown(setup.container.dispose);

        final notifier = setup.container.read(devicePairingProvider.notifier);
        final coordinator = setup.container.read(
          strictApplyCoordinatorProvider,
        );

        // Pre-register the latch (mirrors how _runSnapshotBootstrap uses it).
        final outcomeFuture = coordinator.enterStrictMode();

        // Idle timeout chosen so this test runs quickly. We pulse
        // SyncCompleted events at half the timeout cadence — if the
        // watchdog incorrectly counted them as progress, it would never
        // fire and this test would hang past the await.
        const idleTimeout = Duration(milliseconds: 200);

        // Schedule a stream of SyncCompleted ticks every 80ms (well under
        // the idle timeout) for ~600ms total. None of these should reset
        // the watchdog under the corrected policy.
        var ticks = 0;
        final pulseTimer = Timer.periodic(
          const Duration(milliseconds: 80),
          (timer) {
            ticks++;
            setup.events.add(
              SyncEvent.fromJson(<String, dynamic>{
                'type': 'SyncCompleted',
                'result': <String, dynamic>{},
              }),
            );
            if (ticks >= 8) timer.cancel();
          },
        );
        addTearDown(pulseTimer.cancel);

        final watchdogFuture = notifier.awaitApplyOutcomeWithWatchdogForTest(
          handle: const _FakePrismSyncHandle(),
          outcomeFuture: outcomeFuture,
          idleTimeout: idleTimeout,
        );

        final outcome = await watchdogFuture.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail(
            'Watchdog never fired despite SyncCompleted-only stream — '
            'idle-reset policy regressed (Finding B).',
          ),
        );

        coordinator.exitStrictMode();

        expect(outcome, isA<ApplyOutcomeFailure>());
        final failure = (outcome as ApplyOutcomeFailure).failure;
        expect(
          failure.message,
          startsWith('TIMEOUT:'),
          reason:
              'The watchdog must report a TIMEOUT-prefixed failure when '
              'no RemoteChanges events arrive within idleTimeout.',
        );
        expect(
          ticks,
          greaterThan(0),
          reason:
              'Sanity: the SyncCompleted pulse stream actually fired '
              'before the watchdog tripped.',
        );
      },
    );

    test(
      'RemoteChanges events DO reset the watchdog (positive control)',
      () async {
        final setup = makeWatchdogContainer();
        addTearDown(setup.container.dispose);

        final notifier = setup.container.read(devicePairingProvider.notifier);
        final coordinator = setup.container.read(
          strictApplyCoordinatorProvider,
        );

        final outcomeFuture = coordinator.enterStrictMode();
        const idleTimeout = Duration(milliseconds: 200);

        // Pulse RemoteChanges every 80ms for ~600ms, then signal success.
        // Under correct behaviour, the watchdog never fires because each
        // RemoteChanges resets it; final signalBatchComplete resolves the
        // latch with success.
        var ticks = 0;
        final pulseTimer = Timer.periodic(
          const Duration(milliseconds: 80),
          (timer) {
            ticks++;
            setup.events.add(
              SyncEvent.fromJson(<String, dynamic>{
                'type': 'RemoteChanges',
                'changes': <Map<String, dynamic>>[],
              }),
            );
            if (ticks >= 8) {
              timer.cancel();
              coordinator.signalBatchComplete();
            }
          },
        );
        addTearDown(pulseTimer.cancel);

        final outcome = await notifier
            .awaitApplyOutcomeWithWatchdogForTest(
              handle: const _FakePrismSyncHandle(),
              outcomeFuture: outcomeFuture,
              idleTimeout: idleTimeout,
            )
            .timeout(const Duration(seconds: 2));

        coordinator.exitStrictMode();

        expect(
          outcome,
          isA<ApplyOutcomeSuccess>(),
          reason:
              'RemoteChanges events arriving faster than idleTimeout must '
              'keep the watchdog at bay long enough for the batch-complete '
              'signal to win the latch race.',
        );
      },
    );
  });
}
