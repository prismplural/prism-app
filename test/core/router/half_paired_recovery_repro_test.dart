import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';

void main() {
  group('half-paired recovery repro harness', () {
    test('current cold start strands a half-paired joiner on onboarding', () async {
      final harness = HalfPairedReproHarness.halfPaired(memberCount: 2);

      final result = await harness.restart();

      expect(result.recoveredOnboarding, isFalse);
      expect(result.route, AppRoutePaths.onboarding);
      expect(result.startupHealth, SyncHealthState.needsPassword);
      expect(result.appShellMounted, isFalse);
      expect(result.passwordPromptCanOpen, isFalse);
      expect(
        result.pairingStepAfterProviderRebuild,
        PairingStep.enterUrl,
        reason:
            'The retry/cancel affordance only lives in PairingStep.snapshotFailure. '
            'After a process restart, devicePairingProvider rebuilds at enterUrl.',
      );
    });

    test(
      'successful unlock still cannot complete onboarding without marker',
      () async {
        final harness = HalfPairedReproHarness.halfPaired(memberCount: 2);

        final result = await harness.afterSuccessfulUnlock();

        expect(result.recoveredOnboarding, isFalse);
        expect(result.route, AppRoutePaths.onboarding);
        expect(result.startupHealth, SyncHealthState.healthy);
        expect(result.appShellMounted, isFalse);
      },
    );

    test(
      'matching snapshot marker is the control that exits the trap',
      () async {
        final harness = HalfPairedReproHarness.halfPaired(memberCount: 2)
          ..writeMatchingSnapshotMarker();

        final result = await harness.restart();

        expect(result.recoveredOnboarding, isTrue);
        expect(result.route, AppRoutePaths.home);
        expect(result.appShellMounted, isTrue);
      },
    );
  });
}

class HalfPairedReproHarness {
  HalfPairedReproHarness._({required this.keychain, required this.memberCount});

  factory HalfPairedReproHarness.halfPaired({required int memberCount}) {
    return HalfPairedReproHarness._(
      memberCount: memberCount,
      keychain: {
        kSyncIdKey: _b64('sync-1'),
        kSyncDeviceIdKey: _b64('device-1'),
        kSyncRelayUrlKey: _b64('https://relay.example.test'),
        'prism_sync.wrapped_dek': _b64('wrapped-dek'),
        'prism_sync.dek_salt': _b64('dek-salt'),
        'prism_sync.device_secret': _b64('device-secret'),
        'prism_sync.session_token': _b64('session-token'),
        'prism_sync.epoch': _b64('0'),
      },
    );
  }

  final Map<String, String> keychain;
  final int memberCount;

  Future<HalfPairedStartupResult> restart() async {
    return _snapshot(startupHealth: _classifyCurrentStartupHealth(keychain));
  }

  Future<HalfPairedStartupResult> afterSuccessfulUnlock() async {
    keychain[kRuntimeDekWrappedKey] = 'cached-runtime-key';
    return _snapshot(startupHealth: SyncHealthState.healthy);
  }

  void writeMatchingSnapshotMarker() {
    keychain[kSnapshotApplyCompleteKey] = snapshotApplyCompleteMarkerValue(
      syncId: keychain[kSyncIdKey]!,
      deviceId: keychain[kSyncDeviceIdKey]!,
    );
  }

  Future<HalfPairedStartupResult> _snapshot({
    required SyncHealthState startupHealth,
  }) async {
    final recovered = await recoverCompletedOnboardingFromPairedState(
      readSecureValue: (key) async => keychain[key],
      getMemberCount: () async => memberCount,
      markOnboardingComplete: () async {},
    );
    final completed = recovered;
    final route = completed ? AppRoutePaths.home : AppRoutePaths.onboarding;
    final appShellMounted = route != AppRoutePaths.onboarding;

    return HalfPairedStartupResult(
      recoveredOnboarding: recovered,
      route: route,
      startupHealth: startupHealth,
      appShellMounted: appShellMounted,
      pairingStepAfterProviderRebuild: const PairingState().step,
    );
  }
}

class HalfPairedStartupResult {
  const HalfPairedStartupResult({
    required this.recoveredOnboarding,
    required this.route,
    required this.startupHealth,
    required this.appShellMounted,
    required this.pairingStepAfterProviderRebuild,
  });

  final bool recoveredOnboarding;
  final String route;
  final SyncHealthState startupHealth;
  final bool appShellMounted;
  final PairingStep pairingStepAfterProviderRebuild;

  bool get passwordPromptCanOpen =>
      appShellMounted && startupHealth == SyncHealthState.needsPassword;
}

SyncHealthState _classifyCurrentStartupHealth(Map<String, String> keychain) {
  final keychainOnly = classifyHealthFromKeychain(
    syncId: keychain[kSyncIdKey],
    deviceId: keychain[kSyncDeviceIdKey],
    deviceSecret: keychain[kSyncDeviceSecretKey],
  );
  if (keychainOnly != null) return keychainOnly;

  final runtimeCache =
      keychain[kRuntimeDekWrappedKey] ?? keychain[kRuntimeDekKey];
  final deviceSecret = keychain['prism_sync.device_secret'];
  if (runtimeCache != null && deviceSecret != null) {
    return SyncHealthState.healthy;
  }

  final wrappedDek = keychain['prism_sync.wrapped_dek'];
  if (wrappedDek != null && wrappedDek.isNotEmpty) {
    return SyncHealthState.needsPassword;
  }

  return SyncHealthState.disconnected;
}

String _b64(String value) => base64Encode(utf8.encode(value));
