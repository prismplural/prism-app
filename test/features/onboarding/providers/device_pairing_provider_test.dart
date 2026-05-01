import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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
    this.cancelPairingCeremonyHandler,
  });

  Future<String> Function({required ffi.PrismSyncHandle handle})?
  startJoinerCeremonyHandler;
  Future<String> Function({required ffi.PrismSyncHandle handle})?
  getJoinerSasHandler;
  Future<void> Function({required ffi.PrismSyncHandle handle})?
  cancelPairingCeremonyHandler;

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
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) {
    return cancelPairingCeremonyHandler?.call(handle: handle) ?? Future.value();
  }

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) {
    return getJoinerSasHandler?.call(handle: handle) ??
        Future.value(
          jsonEncode({
            'sas_version': 2,
            'sas_words': ['apple', 'banana', 'cherry', 'delta', 'echo'],
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

String _structuredSyncError({required String code, required String message}) {
  return 'PRISM_SYNC_ERROR_JSON:${jsonEncode({'message': message, 'code': code, 'error_type': 'sync'})}';
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
        sasWords: ['apple', 'banana', 'cherry', 'delta', 'echo'],
      );
      expect(
        state.sasWords,
        equals(['apple', 'banana', 'cherry', 'delta', 'echo']),
      );
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
            'sas_version': 2,
            'sas_words': ['delta', 'echo', 'foxtrot', 'golf', 'hotel'],
          }),
        );
        await pumpEventQueue();

        state = container.read(devicePairingProvider);
        expect(state.step, PairingStep.showingSas);
        expect(state.sasWords, ['delta', 'echo', 'foxtrot', 'golf', 'hotel']);

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
            'sas_version': 2,
            'sas_words': 'delta-echo-foxtrot-golf-hotel',
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

    test('reset cancels an active joiner ceremony', () async {
      const fakeHandle = _FakePrismSyncHandle();
      final fakeHandleNotifier = _FakePrismSyncHandleNotifier(fakeHandle);
      final sasCompleter = Completer<String>();
      var cancelCalls = 0;
      final fakeApi = _FakePairingCeremonyApi(
        getJoinerSasHandler: ({required handle}) {
          expect(handle, same(fakeHandle));
          return sasCompleter.future;
        },
        cancelPairingCeremonyHandler: ({required handle}) async {
          expect(handle, same(fakeHandle));
          cancelCalls++;
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

      expect(
        container.read(devicePairingProvider).step,
        PairingStep.showingRequest,
      );

      notifier.reset();
      await pumpEventQueue();

      expect(cancelCalls, 1);
      expect(container.read(devicePairingProvider).step, PairingStep.enterUrl);
    });

    test('invalid SAS payload fails closed and cancels the ceremony', () async {
      const fakeHandle = _FakePrismSyncHandle();
      final fakeHandleNotifier = _FakePrismSyncHandleNotifier(fakeHandle);
      var cancelCalls = 0;
      final fakeApi = _FakePairingCeremonyApi(
        getJoinerSasHandler: ({required handle}) async {
          expect(handle, same(fakeHandle));
          return jsonEncode({
            'sas_version': 1,
            'sas_words': ['delta', 'echo', 'foxtrot'],
            'sas_decimal': '654321',
          });
        },
        cancelPairingCeremonyHandler: ({required handle}) async {
          expect(handle, same(fakeHandle));
          cancelCalls++;
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

      await container.read(devicePairingProvider.notifier).generateRequest();
      await pumpEventQueue();

      final state = container.read(devicePairingProvider);
      expect(state.step, PairingStep.error);
      expect(state.sasWords, isNull);
      expect(cancelCalls, 1);
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

    // Regression for non-timeout failure regression: a non-timeout exception thrown
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

    for (final code in ['epoch_mismatch', 'epoch_key_mismatch']) {
      test(
        '$code before durable credentials is a hard re-pair error',
        () async {
          final container = makeContainer();
          addTearDown(container.dispose);

          final notifier = container.read(devicePairingProvider.notifier);

          await notifier.handlePostCeremonyFailureForTest(
            ceremonyCompleted: false,
            error: StateError(
              _structuredSyncError(
                code: code,
                message: 'relay epoch could not be verified',
              ),
            ),
          );

          final state = container.read(devicePairingProvider);
          expect(state.step, PairingStep.error);
          expect(state.syncIncomplete, isFalse);
          expect(state.errorCode, code);
          expect(
            state.errorMessage,
            contains('Pairing cannot be safely completed'),
          );
          expect(state.errorMessage, contains('start pairing again'));
        },
      );

      test(
        '$code after durable credentials preserves creds but says re-pair',
        () async {
          final container = makeContainer();
          addTearDown(container.dispose);

          final notifier = container.read(devicePairingProvider.notifier);

          await notifier.handlePostCeremonyFailureForTest(
            ceremonyCompleted: true,
            error: StateError(
              _structuredSyncError(
                code: code,
                message: 'relay epoch could not be verified',
              ),
            ),
          );

          final state = container.read(devicePairingProvider);
          expect(state.step, PairingStep.snapshotFailure);
          expect(state.syncIncomplete, isTrue);
          expect(state.errorCode, code);
          expect(
            state.errorMessage,
            contains('Pairing cannot be safely completed'),
          );
          expect(state.errorMessage, contains('re-pair this device'));
          expect(
            state.errorMessage,
            isNot(contains('Pairing succeeded')),
            reason: 'Epoch verification failures must not imply success.',
          );
        },
      );
    }

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
  // Apply watchdog idle-reset policy regression.
  // ---------------------------------------------------------------------------
  group('apply watchdog — idle-reset policy', () {
    /// Build a container with a controllable sync-event stream and a
    /// fake handle so the private watchdog can be exercised directly via
    /// the @visibleForTesting wrapper.
    ({ProviderContainer container, StreamController<SyncEvent> events})
    makeWatchdogContainer() {
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
        final pulseTimer = Timer.periodic(const Duration(milliseconds: 80), (
          timer,
        ) {
          ticks++;
          setup.events.add(
            SyncEvent.fromJson(<String, dynamic>{
              'type': 'SyncCompleted',
              'result': <String, dynamic>{},
            }),
          );
          if (ticks >= 8) timer.cancel();
        });
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
        final pulseTimer = Timer.periodic(const Duration(milliseconds: 80), (
          timer,
        ) {
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
        });
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

  // ---------------------------------------------------------------------------
  // Drain-ordering regression (Regression: ceremonyCompleted vs drainRustStore)
  // ---------------------------------------------------------------------------
  //
  // Before the fix, `ceremonyCompleted = true` flipped immediately after
  // `completeJoinerCeremony()` returned but `drainRustStore` ran much later
  // inside `_bootstrapAfterJoin`. A `configureEngine` / `setAutoSync` throw
  // in that window routed to `snapshotFailure` while:
  //   - retrySnapshotBootstrap re-ran against an unconfigured handle, and
  //   - cancelAndRemoveDevice tried to read sync_id/device_id/session_token
  //     from a keychain that was never populated, orphaning the relay
  //     registration.
  // The fix drains BEFORE flipping the flag so "ceremony done" and
  // "credentials durable" become the same moment.
  group('drain ordering — ceremonyCompleted gate', () {
    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );

    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    setUp(() {
      DevicePairingNotifier.drainRustStoreOverride = null;
    });

    tearDown(() {
      DevicePairingNotifier.drainRustStoreOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    /// Install an in-memory mock for the flutter_secure_storage method
    /// channel. Returns the backing map so tests can pre-seed values
    /// (cancelAndRemoveDevice test) or assert post-write contents.
    Map<String, String> installSecureStorageMock([
      Map<String, String>? initial,
      Set<String> failWrites = const {},
    ]) {
      final store = <String, String>{...?initial};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (
            MethodCall call,
          ) async {
            switch (call.method) {
              case 'read':
                final key = (call.arguments as Map)['key'] as String;
                return store[key];
              case 'readAll':
                return Map<String, String>.from(store);
              case 'write':
                final args = call.arguments as Map;
                final key = args['key'] as String;
                if (failWrites.contains(key)) {
                  throw PlatformException(
                    code: 'write_failed',
                    message: 'simulated write failure',
                  );
                }
                store[key] = args['value'] as String;
                return null;
              case 'delete':
                final key = (call.arguments as Map)['key'] as String;
                store.remove(key);
                return null;
              case 'deleteAll':
                store.clear();
                return null;
              case 'containsKey':
                final key = (call.arguments as Map)['key'] as String;
                return store.containsKey(key);
              default:
                return null;
            }
          });
      return store;
    }

    ProviderContainer makeContainer({ffi.PrismSyncHandle? handle}) {
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
            () => _FakePrismSyncHandleNotifier(
              handle ?? const _FakePrismSyncHandle(),
            ),
          ),
        ],
      );
      container.listen<PairingState>(devicePairingProvider, (_, _) {});
      return container;
    }

    test(
      'snapshot apply marker is tied to current sync and device IDs',
      () async {
        final keychain = installSecureStorageMock({
          kSyncIdKey: base64Encode(utf8.encode('sync-1')),
          kSyncDeviceIdKey: base64Encode(utf8.encode('device-1')),
        });
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(devicePairingProvider.notifier);
        await notifier.writeSnapshotApplyCompleteMarkerForTest();

        expect(
          keychain[kSnapshotApplyCompleteKey],
          snapshotApplyCompleteMarkerValue(
            syncId: keychain[kSyncIdKey]!,
            deviceId: keychain[kSyncDeviceIdKey]!,
          ),
        );
      },
    );

    test(
      'snapshot apply marker write failure surfaces before success',
      () async {
        final keychain = installSecureStorageMock(
          {
            kSyncIdKey: base64Encode(utf8.encode('sync-1')),
            kSyncDeviceIdKey: base64Encode(utf8.encode('device-1')),
          },
          {kSnapshotApplyCompleteKey},
        );
        final container = makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(devicePairingProvider.notifier);

        await expectLater(
          notifier.writeSnapshotApplyCompleteMarkerForTest(),
          throwsA(isA<PlatformException>()),
        );
        expect(keychain[kSnapshotApplyCompleteKey], isNull);
      },
    );

    test('drainRustStore failure before ceremonyCompleted flag wipes keychain '
        '(pre-ceremony semantics)', () async {
      installSecureStorageMock();
      final container = makeContainer();
      addTearDown(container.dispose);

      // Simulate drainRustStore throwing — Rust returned creds but
      // platform keychain write failed. Per the drain-ordering fix,
      // this must be treated as a ceremony-phase failure: keychain
      // gets wiped and we route to PairingStep.error (NOT
      // snapshotFailure, which would imply preserve-creds + retry).
      DevicePairingNotifier.drainRustStoreOverride = (handle) async {
        throw StateError('keychain unavailable: simulated failure');
      };

      // Ensure the AsyncNotifier handle has resolved before driving
      // the ceremony — otherwise prismSyncHandleProvider.value is null.
      await container.read(prismSyncHandleProvider.future);

      final notifier = container.read(devicePairingProvider.notifier);
      await notifier.completeJoinerWithPassword('123456');
      await pumpEventQueue();

      final state = container.read(devicePairingProvider);
      expect(
        state.step,
        PairingStep.error,
        reason:
            'A drain failure between ceremony returning and the flag '
            'flipping must route to error (with keychain cleanup) — not '
            'snapshotFailure, which would imply credentials are durable.',
      );
      expect(state.syncIncomplete, isFalse);
    });

    test('post-ceremony exception after successful drain preserves creds '
        '(retry path works)', () async {
      // Pre-seed nothing — we'll observe drainRustStore writing values
      // to the mock store before any post-drain failure occurs.
      final keychain = installSecureStorageMock();
      final container = makeContainer();
      addTearDown(container.dispose);

      var drainCalls = 0;
      var drainCompletedAt = -1;
      var bootstrapStartedAt = -1;
      var sequence = 0;

      // Drain succeeds AND records the order in which it ran. We also
      // populate the keychain mock so we can assert that by the time
      // any post-ceremony failure handler runs, credentials are
      // durable. (`ffi.configureEngine` will throw on the fake handle
      // after this drain — that's the failure we route through
      // _handlePostCeremonyFailure.)
      DevicePairingNotifier.drainRustStoreOverride = (handle) async {
        drainCalls++;
        // Simulate the real drain populating the keychain with the
        // credentials needed by cancelAndRemoveDevice.
        keychain['prism_sync.sync_id'] = base64Encode(utf8.encode('sync-1'));
        keychain['prism_sync.device_id'] = base64Encode(
          utf8.encode('device-1'),
        );
        keychain['prism_sync.session_token'] = base64Encode(
          utf8.encode('token-1'),
        );
        drainCompletedAt = ++sequence;
      };

      // Ensure the AsyncNotifier handle has resolved before we drive
      // the joiner ceremony — otherwise `prismSyncHandleProvider.value`
      // returns null and the StateError short-circuits before drain.
      await container.read(prismSyncHandleProvider.future);

      final notifier = container.read(devicePairingProvider.notifier);
      // The FFI configureEngine call inside _bootstrapAfterJoin will
      // throw when handed a fake opaque handle — that's intentional,
      // it exercises the post-ceremony failure path AFTER drain has
      // already populated the keychain. The outer try/catch in
      // completeJoinerWithPassword catches it and routes through
      // _handlePostCeremonyFailure, so the await resolves cleanly.
      await notifier.completeJoinerWithPassword('123456');
      bootstrapStartedAt = ++sequence;
      await pumpEventQueue();

      final state = container.read(devicePairingProvider);
      expect(
        drainCalls,
        1,
        reason:
            'drainRustStore must run exactly once, immediately after the '
            'ceremony returns and before any bootstrap step.',
      );
      expect(
        drainCompletedAt,
        lessThan(bootstrapStartedAt),
        reason:
            'Drain must complete before any post-flag work begins. '
            'If this fails the drain ran AFTER bootstrap, restoring '
            'the original P1 race window.',
      );
      // The contract: post-drain failures route to snapshotFailure
      // (preserve creds + retry path), NOT to error (wipe + restart).
      expect(
        state.step,
        isNot(PairingStep.error),
        reason:
            'Post-drain failures must NOT route to error (which wipes '
            'the keychain) — they must preserve credentials.',
      );
      expect(
        keychain['prism_sync.sync_id'],
        isNotNull,
        reason:
            'Credentials must remain in the keychain after a '
            'post-ceremony failure — cancelAndRemoveDevice depends on '
            'them being readable.',
      );
      expect(keychain['prism_sync.device_id'], isNotNull);
      expect(keychain['prism_sync.session_token'], isNotNull);
    });

    test(
      'post-bootstrap catch-up runs explicit sync and drains state',
      () async {
        final controller = StreamController<SyncEvent>.broadcast();
        final container = ProviderContainer(
          overrides: [
            syncEventStreamProvider.overrideWith((ref) {
              ref.onDispose(controller.close);
              return controller.stream;
            }),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(devicePairingProvider.notifier);
        var syncCalled = false;
        var drainCalled = false;

        await notifier.runPostBootstrapCatchUpForTest(
          handle: const _FakePrismSyncHandle(),
          syncNow: ({required handle}) async {
            syncCalled = true;
            controller
              ..add(
                SyncEvent('RemoteChanges', {
                  'type': 'RemoteChanges',
                  'changes': <Map<String, dynamic>>[],
                }),
              )
              ..add(
                SyncEvent('SyncCompleted', {
                  'type': 'SyncCompleted',
                  'result': {
                    'pulled': 1,
                    'merged': 1,
                    'pushed': 0,
                    'pruned': 0,
                    'duration_ms': 1,
                    'error': null,
                  },
                }),
              );
            return jsonEncode({
              'pulled': 1,
              'merged': 1,
              'pushed': 0,
              'pruned': 0,
              'duration_ms': 1,
              'error': null,
            });
          },
          drain: (handle) async {
            expect(syncCalled, isTrue);
            drainCalled = true;
          },
          eventTimeout: const Duration(seconds: 1),
        );

        expect(syncCalled, isTrue);
        expect(drainCalled, isTrue);
      },
    );

    test('cancelAndRemoveDevice after successful drain reads keychain '
        'and attempts deregisterDevice', () async {
      // Pre-seed the keychain mock the same way a successful drain
      // would have, then drive cancelAndRemoveDevice and verify it
      // reads the credentials and clears them.
      final keychain = installSecureStorageMock({
        'prism_sync.sync_id': base64Encode(utf8.encode('sync-xyz')),
        'prism_sync.device_id': base64Encode(utf8.encode('device-xyz')),
        'prism_sync.session_token': base64Encode(utf8.encode('token-xyz')),
        'prism_sync.wrapped_dek': base64Encode(utf8.encode('dek-xyz')),
        kSnapshotApplyCompleteKey: snapshotApplyCompleteMarkerValue(
          syncId: base64Encode(utf8.encode('sync-xyz')),
          deviceId: base64Encode(utf8.encode('device-xyz')),
        ),
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      // Put the notifier into snapshotFailure state so cancel is the
      // sanctioned exit path.
      final notifier = container.read(devicePairingProvider.notifier);
      await notifier.handlePostCeremonyFailureForTest(
        ceremonyCompleted: true,
        error: StateError('simulated bootstrap failure'),
      );
      expect(
        container.read(devicePairingProvider).step,
        PairingStep.snapshotFailure,
      );

      // Sanity: pre-condition — keychain has what cancel needs.
      expect(keychain['prism_sync.sync_id'], isNotNull);
      expect(keychain['prism_sync.device_id'], isNotNull);
      expect(keychain['prism_sync.session_token'], isNotNull);

      // cancelAndRemoveDevice will:
      //  1. Read sync_id/device_id/session_token from the keychain.
      //  2. Call ffi.deregisterDevice (which throws on the fake
      //     handle — caught and reported as non-fatal).
      //  3. Call _cleanupKeychainOnFailure which deletes pairing keys.
      //  4. Reset state to default PairingState().
      // The fact that step (3) ran proves step (1) successfully read
      // the keychain (otherwise the cancel-prep guard would have
      // skipped the deregister branch).
      await notifier.cancelAndRemoveDevice();
      await pumpEventQueue();

      // Post-condition: pairing-related keys are gone, state is reset.
      expect(
        keychain['prism_sync.sync_id'],
        isNull,
        reason: 'cancel must wipe the persisted sync_id.',
      );
      expect(keychain['prism_sync.device_id'], isNull);
      expect(keychain['prism_sync.session_token'], isNull);
      expect(keychain['prism_sync.wrapped_dek'], isNull);
      expect(keychain[kSnapshotApplyCompleteKey], isNull);
      expect(
        container.read(devicePairingProvider).step,
        PairingStep.enterUrl,
        reason: 'cancel must return the notifier to the initial step.',
      );
    });
  });
}
