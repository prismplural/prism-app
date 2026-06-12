// Phase 4A — sync settings loading guard.
//
// The full `SyncSettingsScreen` body pulls in Drift, the Rust FFI, the
// keychain, and the localization stack. Exercising the configured branch
// is heavyweight, so we instead build a minimal `Consumer` that runs the
// same gating logic the screen uses. The tests cover both sides of the gate:
// a fresh onboarding handle without a sync identity still shows setup, while
// a configured identity does not flash setup during provider revalidation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/settings/views/sync_settings_screen.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandleNotifier extends PrismSyncHandleNotifier {
  _FakeHandleNotifier(this._handle);
  final ffi.PrismSyncHandle? _handle;

  @override
  Future<ffi.PrismSyncHandle?> build() async => _handle;
}

/// Mirror of the gating logic in `SyncSettingsScreen.build()`. Kept as a
/// freestanding widget so the test can assert behavior without dragging in
/// Drift, l10n, or the rest of the configured-view dependency graph.
class _GatingHarness extends ConsumerWidget {
  const _GatingHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relayUrlAsync = ref.watch(relayUrlProvider);
    final syncIdAsync = ref.watch(syncIdProvider);
    final deviceIdAsync = ref.watch(syncDeviceIdProvider);
    final deviceSecretAsync = ref.watch(syncDeviceSecretPresentProvider);
    final relayUrl = relayUrlAsync.value;
    final syncId = syncIdAsync.value;
    final deviceId = deviceIdAsync.value;
    final hasDeviceSecret = deviceSecretAsync.value ?? false;
    final handleAsyncForGate = ref.watch(prismSyncHandleProvider);
    final hasActiveHandle = handleAsyncForGate.value != null;
    final syncHealth = ref.watch(syncHealthProvider);
    final identityLoadComplete =
        relayUrlAsync.hasValue &&
        syncIdAsync.hasValue &&
        deviceIdAsync.hasValue &&
        deviceSecretAsync.hasValue;
    final isConfigured = isSyncSettingsConfigured(
      hasActiveHandle: hasActiveHandle,
      syncHealth: syncHealth,
      relayUrl: relayUrl,
      syncId: syncId,
      deviceId: deviceId,
      hasDeviceSecret: hasDeviceSecret,
      identityLoadComplete: identityLoadComplete,
    );

    if (syncHealth == SyncHealthState.disconnected) {
      return const Text('disconnected', textDirection: TextDirection.ltr);
    }

    if ((relayUrlAsync.isLoading || syncIdAsync.isLoading) &&
        !relayUrlAsync.hasValue &&
        !syncIdAsync.hasValue &&
        !isConfigured) {
      return const Text('loading', textDirection: TextDirection.ltr);
    }

    return Text(
      isConfigured ? 'configured' : 'setup',
      textDirection: TextDirection.ltr,
    );
  }
}

void main() {
  test('fresh onboarding handle without sync identity is not configured', () {
    expect(
      isSyncSettingsConfigured(
        hasActiveHandle: true,
        syncHealth: SyncHealthState.healthy,
        relayUrl: null,
        syncId: null,
        deviceId: null,
        hasDeviceSecret: false,
      ),
      isFalse,
    );
  });

  testWidgets('SetupView does not flash on invalidate when configured', (
    tester,
  ) async {
    const handle = _FakePrismSyncHandle();
    final container = ProviderContainer(
      overrides: [
        prismSyncHandleProvider.overrideWith(() => _FakeHandleNotifier(handle)),
        relayUrlProvider.overrideWith(
          (ref) async => 'https://relay.example.com',
        ),
        syncIdProvider.overrideWith((ref) async => 'sync-123'),
        syncDeviceIdProvider.overrideWith((ref) async => 'device-123'),
        syncDeviceSecretPresentProvider.overrideWith((ref) async => true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _GatingHarness(),
      ),
    );

    // Initial frame: providers still resolving — but the handle override
    // resolves synchronously to AsyncData, so we should already be
    // "configured" via the handle path. Confirm we never see "setup".
    expect(find.text('setup'), findsNothing);

    // Let the FutureProviders resolve.
    await tester.pumpAndSettle();
    expect(find.text('configured'), findsOneWidget);
    expect(find.text('setup'), findsNothing);

    // Now reproduce the user-reported flow: invalidate the
    // keychain-backed providers. With the gating still based on
    // `relayUrl/syncId.value`, this would briefly flip the screen to
    // `_SetupView` while the providers re-fetch. With the handle-based
    // gating from Phase 4A, the FFI handle stays non-null across the
    // invalidate, so `_SetupView` must NEVER appear.
    container.invalidate(relayUrlProvider);
    container.invalidate(syncIdProvider);

    // Pump (don't pumpAndSettle) — we want to catch the intermediate
    // frame where the providers are still re-fetching.
    await tester.pump();
    expect(
      find.text('setup'),
      findsNothing,
      reason: 'mid-invalidate frame must not flash _SetupView',
    );

    // After re-fetch completes, we are still configured.
    await tester.pumpAndSettle();
    expect(find.text('configured'), findsOneWidget);
    expect(find.text('setup'), findsNothing);
  });

  testWidgets(
    'SetupView is shown when there is no handle and no keychain creds',
    (tester) async {
      // Sanity guard: the new gating must still let an unpaired device
      // reach `_SetupView`. Otherwise the user could never start setup.
      final container = ProviderContainer(
        overrides: [
          prismSyncHandleProvider.overrideWith(() => _FakeHandleNotifier(null)),
          relayUrlProvider.overrideWith((ref) async => null),
          syncIdProvider.overrideWith((ref) async => null),
          syncDeviceIdProvider.overrideWith((ref) async => null),
          syncDeviceSecretPresentProvider.overrideWith((ref) async => false),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _GatingHarness(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('setup'), findsOneWidget);
      expect(find.text('configured'), findsNothing);
    },
  );

  testWidgets('partial sync_id/relay_url state is not treated as configured', (
    tester,
  ) async {
    const handle = _FakePrismSyncHandle();
    final container = ProviderContainer(
      overrides: [
        prismSyncHandleProvider.overrideWith(() => _FakeHandleNotifier(handle)),
        syncHealthProvider.overrideWith(() {
          final notifier = SyncHealthNotifier();
          return notifier;
        }),
        relayUrlProvider.overrideWith(
          (ref) async => 'https://relay.example.com',
        ),
        syncIdProvider.overrideWith((ref) async => 'sync-123'),
        syncDeviceIdProvider.overrideWith((ref) async => null),
        syncDeviceSecretPresentProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(syncHealthProvider.notifier)
        .setState(SyncHealthState.unpaired);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _GatingHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('setup'), findsOneWidget);
    expect(find.text('configured'), findsNothing);
  });

  group('canSetUpAnotherDeviceRow', () {
    // Block 2 — the "Set up another device" row must require all three:
    //   1. handle alive
    //   2. complete persistent sync identity
    //   3. wrapped_dek present
    // Otherwise the user lands in `SetupDeviceSheet.show` which fires error
    // toasts for these partial states.

    test('hidden when handle is null', () {
      expect(
        canSetUpAnotherDeviceRow(
          hasActiveHandle: false,
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-123',
          deviceId: 'device-123',
          hasDeviceSecret: true,
          hasWrappedDek: true,
        ),
        isFalse,
      );
    });

    test(
      'hidden when identity is partial (deviceId present but device_secret absent)',
      () {
        expect(
          canSetUpAnotherDeviceRow(
            hasActiveHandle: true,
            relayUrl: 'https://relay.example.com',
            syncId: 'sync-123',
            deviceId: 'device-123',
            hasDeviceSecret: false,
            hasWrappedDek: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'hidden when identity is partial (relayUrl/syncId present but deviceId null)',
      () {
        expect(
          canSetUpAnotherDeviceRow(
            hasActiveHandle: true,
            relayUrl: 'https://relay.example.com',
            syncId: 'sync-123',
            deviceId: null,
            hasDeviceSecret: false,
            hasWrappedDek: true,
          ),
          isFalse,
        );
      },
    );

    test('hidden when wrapped_dek is missing', () {
      expect(
        canSetUpAnotherDeviceRow(
          hasActiveHandle: true,
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-123',
          deviceId: 'device-123',
          hasDeviceSecret: true,
          hasWrappedDek: false,
        ),
        isFalse,
      );
    });

    test('visible only when all three conditions hold', () {
      expect(
        canSetUpAnotherDeviceRow(
          hasActiveHandle: true,
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-123',
          deviceId: 'device-123',
          hasDeviceSecret: true,
          hasWrappedDek: true,
        ),
        isTrue,
      );
    });
  });

  group('shouldShowLocalDisconnectState', () {
    test('shows the local-only state after preserved-data disconnect', () {
      final marker = SyncDisconnectMarker(
        markerId: 'marker-1',
        deviceInstallId: 'install-1',
        reason: SyncDisconnectReason.userDisconnect,
        startedAt: DateTime.utc(2026, 5, 22),
        relayCleanupOutcome: RelayCleanupMarkerOutcome.deregistered,
        localAppDataOutcome: LocalAppDataOutcome.preserved,
        nextSetupConstraint: SyncSetupConstraint.localOnly,
        previousSyncId: 'sync-123',
      );

      expect(shouldShowLocalDisconnectState(marker), isTrue);
    });

    test('does not show local-only state for replace-by-pairing marker', () {
      final marker = SyncDisconnectMarker(
        markerId: 'marker-1',
        deviceInstallId: 'install-1',
        reason: SyncDisconnectReason.replaceByPairing,
        startedAt: DateTime.utc(2026, 5, 22),
        relayCleanupOutcome: RelayCleanupMarkerOutcome.deregistered,
        localAppDataOutcome: LocalAppDataOutcome.wiped,
        nextSetupConstraint: SyncSetupConstraint.joinOnlyReplaceLocalData,
      );

      expect(shouldShowLocalDisconnectState(marker), isFalse);
    });
  });

  group('shouldShowJoinOnlyReplaceState', () {
    test(
      'shows the join-only state after local data was wiped for pairing',
      () {
        final marker = SyncDisconnectMarker(
          markerId: 'marker-1',
          deviceInstallId: 'install-1',
          reason: SyncDisconnectReason.replaceByPairing,
          startedAt: DateTime.utc(2026, 5, 22),
          relayCleanupOutcome: RelayCleanupMarkerOutcome.deregistered,
          localAppDataOutcome: LocalAppDataOutcome.wiped,
          nextSetupConstraint: SyncSetupConstraint.joinOnlyReplaceLocalData,
        );

        expect(shouldShowJoinOnlyReplaceState(marker), isTrue);
      },
    );

    test('does not treat a preserved local-only marker as join-only', () {
      final marker = SyncDisconnectMarker(
        markerId: 'marker-1',
        deviceInstallId: 'install-1',
        reason: SyncDisconnectReason.userDisconnect,
        startedAt: DateTime.utc(2026, 5, 22),
        relayCleanupOutcome: RelayCleanupMarkerOutcome.deregistered,
        localAppDataOutcome: LocalAppDataOutcome.preserved,
        nextSetupConstraint: SyncSetupConstraint.localOnly,
      );

      expect(shouldShowJoinOnlyReplaceState(marker), isFalse);
    });
  });

  group('canTriggerManualSync', () {
    test(
      'enables reconnect when stored relay settings exist but handle is null',
      () {
        expect(
          canTriggerManualSync(
            hasHandle: true,
            hasRelayUrl: false,
            isSyncActive: false,
            isHandleLoading: false,
            syncDatabaseReady: true,
          ),
          isTrue,
        );
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: true,
            isSyncActive: false,
            isHandleLoading: false,
            syncDatabaseReady: true,
          ),
          isTrue,
        );
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: false,
            isSyncActive: false,
            isHandleLoading: false,
            syncDatabaseReady: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'keeps manual sync disabled while sync or handle restoration is active',
      () {
        expect(
          canTriggerManualSync(
            hasHandle: true,
            hasRelayUrl: true,
            isSyncActive: true,
            isHandleLoading: false,
            syncDatabaseReady: true,
          ),
          isFalse,
        );
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: true,
            isSyncActive: false,
            isHandleLoading: true,
            syncDatabaseReady: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'disabled when boot probe says the sync database is unrecoverable',
      () {
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: true,
            isSyncActive: false,
            isHandleLoading: false,
            syncDatabaseReady: false,
          ),
          isFalse,
        );
        expect(
          canTriggerManualSync(
            hasHandle: true,
            hasRelayUrl: true,
            isSyncActive: false,
            isHandleLoading: false,
            syncDatabaseReady: false,
          ),
          isFalse,
        );
      },
    );
  });

  group('buildSyncSummaryPresentation', () {
    test('keeps a connected headline while a quick sync is active', () {
      final lastSyncAt = DateTime.utc(2026, 6, 11, 12);

      final idle = buildSyncSummaryPresentation(
        syncStatus: SyncStatus(lastSyncAt: lastSyncAt),
        hasActiveHandle: true,
        handleIsLoading: false,
        canAttemptReconnect: true,
        wsConnected: true,
        syncDatabaseReady: true,
      );
      final syncing = buildSyncSummaryPresentation(
        syncStatus: SyncStatus(isSyncing: true, lastSyncAt: lastSyncAt),
        hasActiveHandle: true,
        handleIsLoading: false,
        canAttemptReconnect: true,
        wsConnected: true,
        syncDatabaseReady: true,
      );

      expect(idle.headline, SyncSummaryHeadline.connected);
      expect(syncing.headline, SyncSummaryHeadline.connected);
      expect(idle.activity, SyncSummaryActivity.checkingForChanges);
      expect(syncing.activity, SyncSummaryActivity.syncing);
    });

    test('uses pending uploads as the activity when local ops are queued', () {
      final summary = buildSyncSummaryPresentation(
        syncStatus: const SyncStatus(pendingOps: 3),
        hasActiveHandle: true,
        handleIsLoading: false,
        canAttemptReconnect: true,
        wsConnected: true,
        syncDatabaseReady: true,
      );

      expect(summary.headline, SyncSummaryHeadline.connected);
      expect(summary.activity, SyncSummaryActivity.pendingUploads);
      expect(summary.pendingUploads, 3);
    });

    test('surfaces attention and offline states separately', () {
      final attention = buildSyncSummaryPresentation(
        syncStatus: const SyncStatus(lastError: 'Relay unavailable'),
        hasActiveHandle: true,
        handleIsLoading: false,
        canAttemptReconnect: true,
        wsConnected: true,
        syncDatabaseReady: true,
      );
      final offline = buildSyncSummaryPresentation(
        syncStatus: const SyncStatus(),
        hasActiveHandle: false,
        handleIsLoading: false,
        canAttemptReconnect: true,
        wsConnected: false,
        syncDatabaseReady: true,
      );

      expect(attention.headline, SyncSummaryHeadline.needsAttention);
      expect(attention.tone, SyncSummaryTone.error);
      expect(offline.headline, SyncSummaryHeadline.offline);
      expect(offline.tone, SyncSummaryTone.error);
    });
  });

  group('Verify saved backup row visibility', () {
    // The "Verify saved backup" row uses the same canSetUpAnotherDeviceRow
    // gate as "Set up another device" — it should appear only when handle,
    // complete identity, and wrapped_dek are all present.
    test('row is hidden when canSetUpAnotherDeviceRow returns false', () {
      // No handle
      expect(
        canSetUpAnotherDeviceRow(
          hasActiveHandle: false,
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-123',
          deviceId: 'device-123',
          hasDeviceSecret: true,
          hasWrappedDek: true,
        ),
        isFalse,
      );
    });

    test('row is shown when canSetUpAnotherDeviceRow returns true', () {
      expect(
        canSetUpAnotherDeviceRow(
          hasActiveHandle: true,
          relayUrl: 'https://relay.example.com',
          syncId: 'sync-123',
          deviceId: 'device-123',
          hasDeviceSecret: true,
          hasWrappedDek: true,
        ),
        isTrue,
      );
    });
  });
}
