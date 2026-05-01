import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_router.dart';

void main() {
  group('recoverCompletedOnboardingFromPairedState', () {
    Future<({bool recovered, int markCalls})> runRecovery({
      required Map<String, String> keychain,
      required int memberCount,
    }) async {
      var markCalls = 0;
      final recovered = await recoverCompletedOnboardingFromPairedState(
        readSecureValue: (key) async => keychain[key],
        getMemberCount: () async => memberCount,
        markOnboardingComplete: () async {
          markCalls++;
        },
      );
      return (recovered: recovered, markCalls: markCalls);
    }

    test(
      'marks onboarding complete for paired devices with restored members',
      () async {
        final result = await runRecovery(
          keychain: {
            'prism_sync.sync_id': 'sync-1',
            'prism_sync.device_id': 'device-1',
            'prism_sync.wrapped_dek': 'wrapped',
          },
          memberCount: 2,
        );

        expect(result.recovered, isTrue);
        expect(result.markCalls, 1);
      },
    );

    test('does not recover without paired device identity', () async {
      final result = await runRecovery(
        keychain: {
          'prism_sync.sync_id': 'sync-1',
          'prism_sync.wrapped_dek': 'wrapped',
        },
        memberCount: 2,
      );

      expect(result.recovered, isFalse);
      expect(result.markCalls, 0);
    });

    test('does not recover without unlock material', () async {
      final result = await runRecovery(
        keychain: {
          'prism_sync.sync_id': 'sync-1',
          'prism_sync.device_id': 'device-1',
        },
        memberCount: 2,
      );

      expect(result.recovered, isFalse);
      expect(result.markCalls, 0);
    });

    test('does not recover before restored members are present', () async {
      final result = await runRecovery(
        keychain: {
          'prism_sync.sync_id': 'sync-1',
          'prism_sync.device_id': 'device-1',
          'prism_sync.wrapped_dek': 'wrapped',
        },
        memberCount: 0,
      );

      expect(result.recovered, isFalse);
      expect(result.markCalls, 0);
    });

    test('accepts cached runtime keys as unlock material', () async {
      final result = await runRecovery(
        keychain: {
          'prism_sync.sync_id': 'sync-1',
          'prism_sync.device_id': 'device-1',
          'prism_sync.runtime_dek_wrapped_v1': 'cached-runtime-key',
        },
        memberCount: 1,
      );

      expect(result.recovered, isTrue);
      expect(result.markCalls, 1);
    });
  });
}
