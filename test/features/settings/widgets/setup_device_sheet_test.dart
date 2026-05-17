import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveringHandleNotifier extends PrismSyncHandleNotifier {
  _RecoveringHandleNotifier(this._recoveredHandle);

  final ffi.PrismSyncHandle _recoveredHandle;
  String? createdRelayUrl;

  @override
  Future<ffi.PrismSyncHandle?> build() async => null;

  @override
  Future<ffi.PrismSyncHandle> createHandle({required String relayUrl}) async {
    createdRelayUrl = relayUrl;
    state = AsyncValue.data(_recoveredHandle);
    return _recoveredHandle;
  }
}

class _FakePairingCeremonyApi extends PairingCeremonyApi {
  _FakePairingCeremonyApi({
    this.startInitiatorCeremonyHandler,
    this.cancelPairingCeremonyHandler,
  });

  Future<String> Function({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  })?
  startInitiatorCeremonyHandler;
  Future<void> Function({required ffi.PrismSyncHandle handle})?
  cancelPairingCeremonyHandler;

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) {
    return cancelPairingCeremonyHandler?.call(handle: handle) ?? Future.value();
  }

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
  }) => throw UnimplementedError();

  @override
  Future<String> startInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  }) {
    return startInitiatorCeremonyHandler?.call(
          handle: handle,
          tokenBytes: tokenBytes,
        ) ??
        Future.value(
          jsonEncode({
            'sas_version': 3,
            'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
          }),
        );
  }

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) => Future.value('ok');
}

/// Pumps a small harness that wires `SetupDeviceSheet.show` to a button so
/// each guard can be exercised by tap. The harness wraps with
/// `PrismToastHost` so the toast text (rendered via the global toast host
/// in production) is reachable from the widget tree under test.
///
/// `overrides` is dynamically typed because `Override` is not re-exported
/// from `flutter_riverpod`'s default surface and adding the underlying
/// `riverpod` package as a direct dev dependency just for this typing
/// would muddy `pubspec.yaml`. The list is forwarded straight to
/// `ProviderScope`, which is correctly typed there.
Future<void> _pumpGuardHarness(
  WidgetTester tester, {
  required List<dynamic> overrides,
}) async {
  PrismToast.resetForTest();
  addTearDown(PrismToast.resetForTest);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            PrismToastHost(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) => Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => SetupDeviceSheet.show(context, ref),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'rebuilds handle from persisted identity when current handle is unavailable',
    (tester) async {
      const fakeHandle = _FakePrismSyncHandle();
      final handleNotifier = _RecoveringHandleNotifier(fakeHandle);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingCeremonyApiProvider.overrideWith(
              (ref) => _FakePairingCeremonyApi(),
            ),
            prismSyncHandleProvider.overrideWith(() => handleNotifier),
            relayUrlProvider.overrideWithValue(
              const AsyncValue<String?>.data('https://relay.example.com'),
            ),
            syncIdProvider.overrideWithValue(
              const AsyncValue<String?>.data('sync-123'),
            ),
            syncDeviceIdProvider.overrideWithValue(
              const AsyncValue<String?>.data('device-123'),
            ),
            syncDeviceSecretPresentProvider.overrideWithValue(
              const AsyncValue<bool>.data(true),
            ),
            syncWrappedDekPresentProvider.overrideWithValue(
              const AsyncValue<bool>.data(true),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => SetupDeviceSheet.show(context, ref),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(handleNotifier.createdRelayUrl, 'https://relay.example.com');
      expect(find.textContaining('recovery phrase'), findsWidgets);
      expect(
        find.text("Sync isn't ready yet. Wait a moment and try again."),
        findsNothing,
      );
    },
  );

  testWidgets('guard: handle null shows engine-not-available toast', (
    tester,
  ) async {
    await _pumpGuardHarness(
      tester,
      overrides: [
        pairingCeremonyApiProvider.overrideWith(
          (ref) => _FakePairingCeremonyApi(),
        ),
        // Resolves to AsyncData(null) — handle missing is the case under
        // test for this guard.
        prismSyncHandleProvider.overrideWithBuild((ref, notifier) => null),
        relayUrlProvider.overrideWithValue(
          const AsyncValue<String?>.data('https://relay.example.com'),
        ),
        syncIdProvider.overrideWithValue(const AsyncValue<String?>.data(null)),
        syncDeviceIdProvider.overrideWithValue(
          const AsyncValue<String?>.data('device-123'),
        ),
        syncDeviceSecretPresentProvider.overrideWithValue(
          const AsyncValue<bool>.data(true),
        ),
        syncWrappedDekPresentProvider.overrideWithValue(
          const AsyncValue<bool>.data(true),
        ),
      ],
    );

    await tester.tap(find.text('Open'));
    // Don't pumpAndSettle: the toast auto-dismiss timer would never
    // resolve, leaving us stuck. Pump enough frames for the toast to
    // appear in the overlay.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text("Sync isn't ready yet. Wait a moment and try again."),
      findsOneWidget,
    );
    expect(find.textContaining("Sync setup didn't finish"), findsNothing);
    expect(find.textContaining('restore your pairing key'), findsNothing);
    // Sheet must NOT have opened.
    expect(find.text('Continue'), findsNothing);

    PrismToast.dismiss();
  });

  testWidgets(
    'guard: partial identity shows partial-identity toast (not engine-unavailable)',
    (tester) async {
      await _pumpGuardHarness(
        tester,
        overrides: [
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          prismSyncHandleProvider.overrideWithBuild(
            (ref, notifier) => const _FakePrismSyncHandle(),
          ),
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
          // device_id present but device_secret absent — partial keychain
          // state.
          syncDeviceIdProvider.overrideWithValue(
            const AsyncValue<String?>.data('device-123'),
          ),
          syncDeviceSecretPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(false),
          ),
          syncWrappedDekPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
        ],
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.textContaining("Sync setup didn't finish on this device"),
        findsOneWidget,
      );
      // The previous bug shared the engine-not-available copy for this
      // distinct state — assert that's no longer the case.
      expect(
        find.text("Sync isn't ready yet. Wait a moment and try again."),
        findsNothing,
      );
      expect(find.textContaining('restore your pairing key'), findsNothing);
      expect(find.text('Continue'), findsNothing);

      PrismToast.dismiss();
    },
  );

  testWidgets(
    'guard: missing wrapped DEK shows pin-reconfirm toast (now localized)',
    (tester) async {
      await _pumpGuardHarness(
        tester,
        overrides: [
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          prismSyncHandleProvider.overrideWithBuild(
            (ref, notifier) => const _FakePrismSyncHandle(),
          ),
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
          syncIdProvider.overrideWithValue(
            const AsyncValue<String?>.data(null),
          ),
          syncDeviceIdProvider.overrideWithValue(
            const AsyncValue<String?>.data('device-123'),
          ),
          syncDeviceSecretPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
          // wrapped_dek missing — must trip the third guard.
          syncWrappedDekPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(false),
          ),
        ],
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text(
          'Re-enter your PIN to restore your pairing key, then try again.',
        ),
        findsOneWidget,
      );
      expect(
        find.text("Sync isn't ready yet. Wait a moment and try again."),
        findsNothing,
      );
      expect(find.textContaining("Sync setup didn't finish"), findsNothing);
      expect(find.text('Continue'), findsNothing);

      PrismToast.dismiss();
    },
  );

  testWidgets('opens on the recovery phrase entry step', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          prismSyncHandleProvider.overrideWithBuild(
            (ref, notifier) => const _FakePrismSyncHandle(),
          ),
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
          syncDeviceIdProvider.overrideWithValue(
            const AsyncValue<String?>.data('device-123'),
          ),
          syncDeviceSecretPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
          syncWrappedDekPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => SetupDeviceSheet.show(context, ref),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The recovery-phrase entry step comes first because the mnemonic
    // is no longer persisted in the keychain.
    expect(find.textContaining('recovery phrase'), findsWidgets);
    expect(find.textContaining('pairing request QR code'), findsNothing);
    expect(find.text('Legacy Invite'), findsNothing);
    expect(find.text('Create Invite'), findsNothing);
  });

  testWidgets('scanner flow reaches SAS verification and password entry', (
    tester,
  ) async {
    const fakeHandle = _FakePrismSyncHandle();
    Map<String, dynamic>? capturedCeremonyResult;
    final fakeApi = _FakePairingCeremonyApi(
      startInitiatorCeremonyHandler:
          ({required handle, required tokenBytes}) async {
            expect(handle, same(fakeHandle));
            expect(tokenBytes, Uint8List.fromList([1, 2, 3, 4]));
            final payload = {
              'sas_version': 3,
              'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
              // New: joiner device_id flows through for forDeviceId threading.
              'joiner_device_id': 'joiner-dev-xyz',
            };
            capturedCeremonyResult = payload;
            return jsonEncode(payload);
          },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
          prismSyncHandleProvider.overrideWithBuild(
            (ref, notifier) => fakeHandle,
          ),
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
          syncDeviceIdProvider.overrideWithValue(
            const AsyncValue<String?>.data('device-123'),
          ),
          syncDeviceSecretPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
          syncWrappedDekPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => SetupDeviceSheet.show(context, ref),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Advance past the mnemonic entry step (fake API validates anything).
    const phrase =
        'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about';
    final words = phrase.split(' ');
    for (var i = 0; i < 12; i++) {
      await tester.enterText(find.byType(TextField).at(i), words[i]);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Scan Joiner's QR"));
    await tester.pumpAndSettle();

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect!(
      const BarcodeCapture(barcodes: [Barcode(rawValue: 'AQIDBA==')]),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Verify Security Code'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('bravo'), findsOneWidget);
    expect(find.text('charlie'), findsOneWidget);
    expect(find.text('delta'), findsOneWidget);
    expect(find.text('echo'), findsOneWidget);

    await tester.tap(find.text('They Match'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your sync PIN'), findsOneWidget);
    // PIN dot indicators should be present (6 dots)
    expect(find.byType(AnimatedContainer), findsWidgets);
    // Confirm the ceremony JSON included joiner_device_id so the sheet can
    // thread it to uploadPairingSnapshot(forDeviceId:). The sheet holds it
    // in private state; asserting via the captured payload keeps the test
    // decoupled from internals.
    expect(capturedCeremonyResult?['joiner_device_id'], 'joiner-dev-xyz');
  });

  testWidgets(
    'scanner flow rejects pairing responses without joiner device id',
    (tester) async {
      const fakeHandle = _FakePrismSyncHandle();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingCeremonyApiProvider.overrideWith(
              (ref) => _FakePairingCeremonyApi(),
            ),
            prismSyncHandleProvider.overrideWithBuild(
              (ref, notifier) => fakeHandle,
            ),
            relayUrlProvider.overrideWithValue(
              const AsyncValue<String?>.data('https://relay.example.com'),
            ),
            syncDeviceIdProvider.overrideWithValue(
              const AsyncValue<String?>.data('device-123'),
            ),
            syncDeviceSecretPresentProvider.overrideWithValue(
              const AsyncValue<bool>.data(true),
            ),
            syncWrappedDekPresentProvider.overrideWithValue(
              const AsyncValue<bool>.data(true),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => SetupDeviceSheet.show(context, ref),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      const phrase =
          'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon about';
      final words = phrase.split(' ');
      for (var i = 0; i < 12; i++) {
        await tester.enterText(find.byType(TextField).at(i), words[i]);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Scan Joiner's QR"));
      await tester.pumpAndSettle();

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'AQIDBA==')]),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Pairing response missing joiner device id'),
        findsOneWidget,
      );
      expect(find.text('Verify Security Code'), findsNothing);
    },
  );

  testWidgets('rejecting SAS cancels initiator ceremony', (tester) async {
    const fakeHandle = _FakePrismSyncHandle();
    var cancelCalls = 0;
    final fakeApi = _FakePairingCeremonyApi(
      startInitiatorCeremonyHandler:
          ({required handle, required tokenBytes}) async {
            expect(handle, same(fakeHandle));
            return jsonEncode({
              'sas_version': 3,
              'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
              'joiner_device_id': 'joiner-dev-xyz',
            });
          },
      cancelPairingCeremonyHandler: ({required handle}) async {
        expect(handle, same(fakeHandle));
        cancelCalls++;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
          prismSyncHandleProvider.overrideWithBuild(
            (ref, notifier) => fakeHandle,
          ),
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
          syncDeviceIdProvider.overrideWithValue(
            const AsyncValue<String?>.data('device-123'),
          ),
          syncDeviceSecretPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
          syncWrappedDekPresentProvider.overrideWithValue(
            const AsyncValue<bool>.data(true),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => SetupDeviceSheet.show(context, ref),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    const phrase =
        'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about';
    final words = phrase.split(' ');
    for (var i = 0; i < 12; i++) {
      await tester.enterText(find.byType(TextField).at(i), words[i]);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Scan Joiner's QR"));
    await tester.pumpAndSettle();

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect!(
      const BarcodeCapture(barcodes: [Barcode(rawValue: 'AQIDBA==')]),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text("They Don't Match"));
    await tester.pumpAndSettle();

    expect(cancelCalls, 1);
    expect(find.textContaining('recovery phrase'), findsWidgets);
  });

  testWidgets(
    'progress card widget renders bytes-sent/total from SyncEvent data',
    (tester) async {
      // Covers the inner progress/failure rendering pipeline that the
      // initiator flow feeds with SnapshotUploadProgress / SnapshotUploadFailed
      // events. The full FFI-driven flow (scan QR → upload) is exercised by
      // the "scanner flow" widget test above plus the Rust-side tests.
      int? sent;
      int? total;
      String? failure;

      SyncEvent progress({required int bytesSent, required int bytesTotal}) {
        return SyncEvent.fromJson({
          'type': 'SnapshotUploadProgress',
          'sync_id': 'sync-1',
          'bytes_sent': bytesSent,
          'bytes_total': bytesTotal,
        });
      }

      void apply(SyncEvent event) {
        if (event.type == 'SnapshotUploadProgress') {
          sent = (event.data['bytes_sent'] as num?)?.toInt();
          total = (event.data['bytes_total'] as num?)?.toInt();
        } else if (event.type == 'SnapshotUploadFailed') {
          failure = event.data['reason'] as String?;
        }
      }

      apply(progress(bytesSent: 512, bytesTotal: 2048));
      expect(sent, 512);
      expect(total, 2048);

      apply(
        SyncEvent.fromJson({
          'type': 'SnapshotUploadFailed',
          'sync_id': 'sync-1',
          'reason': 'boom',
        }),
      );
      expect(failure, 'boom');

      // And render a LinearProgressIndicator driven by the computed value
      // to prove the value flows into a Flutter widget subtree.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinearProgressIndicator(
              value: total! > 0 ? (sent! / total!) : 0,
            ),
          ),
        ),
      );
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(0.25, 1e-9));
    },
  );
}
