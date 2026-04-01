import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';

void main() {
  group('PairingState', () {
    test('default state starts at enterUrl step', () {
      const state = PairingState();
      expect(state.step, PairingStep.enterUrl);
      expect(state.url, isNull);
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
      expect(updated.url, isNull);
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

      final state2 = state1.copyWith(
        step: PairingStep.enterPassword,
        url: 'qr-approval:base64data',
      );
      expect(state2.step, PairingStep.enterPassword);
      expect(state2.url, 'qr-approval:base64data');
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
        url: 'some-url',
        errorMessage: 'some error',
        errorCode: 'ERR_001',
        requestQrPayload: [1, 2, 3],
        requestDeviceId: 'dev-x',
      );
      expect(state.url, 'some-url');
      expect(state.errorMessage, 'some error');
      expect(state.errorCode, 'ERR_001');

      final cleared = state.copyWith(
        url: null,
        errorMessage: null,
        errorCode: null,
        requestQrPayload: null,
        requestDeviceId: null,
      );
      expect(cleared.url, isNull);
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
        url: 'stale-url',
        requestQrPayload: [1, 2, 3],
        requestDeviceId: 'old-device',
      );
      expect(errorState.step, PairingStep.error);

      // Simulating reset(): rebuild returns default PairingState
      const resetState = PairingState();
      expect(resetState.step, PairingStep.enterUrl);
      expect(resetState.url, isNull);
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

    test('setApprovalQrBytes stores a joiner approval payload marker', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(devicePairingProvider.notifier).setApprovalQrBytes([
        1,
        2,
        3,
      ]);

      expect(
        container.read(devicePairingProvider).url,
        startsWith('qr-approval:'),
      );
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
          PairingStep.enterPassword,
          PairingStep.connecting,
          PairingStep.success,
          PairingStep.error,
        ]),
      );
    });
  });
}
