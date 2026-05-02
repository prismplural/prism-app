import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_router.dart';

void main() {
  group('recoverCompletedOnboardingFromPairedState', () {
    const markerKey = 'prism_sync.snapshot_apply_complete_v1';

    String markerFor(String syncId, String deviceId) => '$syncId\n$deviceId';

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
      'does not recover paired devices without snapshot apply marker',
      () async {
        final result = await runRecovery(
          keychain: {
            'prism_sync.sync_id': 'sync-1',
            'prism_sync.device_id': 'device-1',
            'prism_sync.wrapped_dek': 'wrapped',
          },
          memberCount: 2,
        );

        expect(result.recovered, isFalse);
        expect(result.markCalls, 0);
      },
    );

    test(
      'marks onboarding complete with matching snapshot apply marker',
      () async {
        final result = await runRecovery(
          keychain: {
            'prism_sync.sync_id': 'sync-1',
            'prism_sync.device_id': 'device-1',
            'prism_sync.wrapped_dek': 'wrapped',
            markerKey: markerFor('sync-1', 'device-1'),
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
          markerKey: markerFor('sync-1', 'device-1'),
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
          markerKey: markerFor('sync-1', 'device-1'),
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
          markerKey: markerFor('sync-1', 'device-1'),
        },
        memberCount: 1,
      );

      expect(result.recovered, isTrue);
      expect(result.markCalls, 1);
    });

    test('does not recover with a stale snapshot apply marker', () async {
      final result = await runRecovery(
        keychain: {
          'prism_sync.sync_id': 'sync-1',
          'prism_sync.device_id': 'device-1',
          'prism_sync.wrapped_dek': 'wrapped',
          markerKey: markerFor('sync-1', 'old-device'),
        },
        memberCount: 2,
      );

      expect(result.recovered, isFalse);
      expect(result.markCalls, 0);
    });
  });
}
