// Phase 4A — sync settings loading guard.
//
// The full `SyncSettingsScreen` body pulls in Drift, the Rust FFI, the
// keychain, and the localization stack. Exercising the configured branch
// is heavyweight, so we instead build a minimal `Consumer` that runs the
// same gating logic the screen uses and assert that toggling
// `relayUrlProvider`/`syncIdProvider` between an active and a re-fetching
// state does NOT cause `_SetupView` to appear when the FFI handle is
// already non-null.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
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
    final relayUrl = relayUrlAsync.value;
    final syncId = syncIdAsync.value;
    final handleAsyncForGate = ref.watch(prismSyncHandleProvider);
    final hasActiveHandle = handleAsyncForGate.value != null;
    final hasKeychainCreds =
        relayUrl != null &&
        relayUrl.isNotEmpty &&
        syncId != null &&
        syncId.isNotEmpty;
    final isConfigured = hasActiveHandle || hasKeychainCreds;
    final syncHealth = ref.watch(syncHealthProvider);

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
          ),
          isTrue,
        );
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: true,
            isSyncActive: false,
            isHandleLoading: false,
          ),
          isTrue,
        );
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: false,
            isSyncActive: false,
            isHandleLoading: false,
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
          ),
          isFalse,
        );
        expect(
          canTriggerManualSync(
            hasHandle: false,
            hasRelayUrl: true,
            isSyncActive: false,
            isHandleLoading: true,
          ),
          isFalse,
        );
      },
    );
  });
}
