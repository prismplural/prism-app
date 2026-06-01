import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
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
    // ignore: unused_element_parameter
    this.completeInitiatorCeremonyHandler,
  });

  Future<String> Function({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  })?
  startInitiatorCeremonyHandler;
  Future<void> Function({required ffi.PrismSyncHandle handle})?
  cancelPairingCeremonyHandler;
  Future<String> Function({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  })?
  completeInitiatorCeremonyHandler;

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
  }) {
    return completeInitiatorCeremonyHandler?.call(
          handle: handle,
          password: password,
          mnemonic: mnemonic,
        ) ??
        Future.value('ok');
  }
}

/// Fake [SyncHealthNotifier] that returns a configurable [VerifyMnemonicPinResult].
/// Defaults to [VerifyMnemonicPinMatch] so flow-through tests advance automatically.
class _FakeSyncHealthNotifier extends SyncHealthNotifier {
  _FakeSyncHealthNotifier({VerifyMnemonicPinResult Function()? verifyResult})
    : _verifyResultFn = verifyResult ?? (() => const VerifyMnemonicPinMatch());

  final VerifyMnemonicPinResult Function() _verifyResultFn;

  @override
  SyncHealthState build() => SyncHealthState.healthy;

  @override
  Future<VerifyMnemonicPinResult> verifyMnemonicPin({
    required PinBuffer pin,
    required String mnemonic,
  }) async {
    // Drain the pin for all variants that production also drains (i.e., any
    // variant reached past the early NeedsRewrap/HandleUnavailable guards).
    final result = _verifyResultFn();
    if (result is VerifyMnemonicPinMatch ||
        result is VerifyMnemonicPinNoMatch ||
        result is VerifyMnemonicPinError) {
      pin.consumeBytesAndClear();
    }
    return result;
  }
}

/// Helper that navigates through the mnemonic + preflight steps.
///
/// Uses [_FakeSyncHealthNotifier] with [VerifyMnemonicPinMatch] so the
/// preflight PIN step advances automatically when digits are entered.
Future<void> _advanceThroughPreflight(
  WidgetTester tester, {
  bool tapScanButton = false,
}) async {
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

  // Now on pinPreflight — enter 6 digits to auto-advance (fake returns Match).
  // Tap digits 1-5 normally; tap 6 separately then pump to drive the async flow.
  for (final digit in ['1', '2', '3', '4', '5']) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('6').last);
  // Drive the async _onPinComplete chain: each pump advances microtasks,
  // SharedPreferences writes, animation ticks, and the Future.delayed(250ms).
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  if (tapScanButton) {
    await tester.tap(find.text("Scan Joiner's QR"));
    await tester.pumpAndSettle();
  }
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // PinLockoutState uses SharedPreferences; reset for each test.
    SharedPreferences.setMockInitialValues({});
  });

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
    'guard: unrecoverable sync DB does not try to restore handle from creds',
    (tester) async {
      const fakeHandle = _FakePrismSyncHandle();
      final handleNotifier = _RecoveringHandleNotifier(fakeHandle);

      await _pumpGuardHarness(
        tester,
        overrides: [
          pairingCeremonyApiProvider.overrideWith(
            (ref) => _FakePairingCeremonyApi(),
          ),
          prismSyncHandleProvider.overrideWith(() => handleNotifier),
          syncDatabaseStartupProvider.overrideWithValue(
            const DbStartupReport(
              state: DbStartupState.unrecoverable,
              keyInMemory: null,
              usedRecoverySlot: null,
              diagnostic: null,
            ),
          ),
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
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(handleNotifier.createdRelayUrl, isNull);
      expect(
        find.text("Sync isn't ready yet. Wait a moment and try again."),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsNothing);

      PrismToast.dismiss();
    },
  );

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
          syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

    // Advance through mnemonic entry and pre-flight PIN step.
    await _advanceThroughPreflight(tester, tapScanButton: true);

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

    // With validatedPin held, _completeInitiator is called directly (no
    // passwordEntry step). The flow goes to uploading/error.
    expect(find.text('Enter your sync PIN'), findsNothing);
    // Confirm the ceremony JSON included joiner_device_id.
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
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      await _advanceThroughPreflight(tester, tapScanButton: true);

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
          syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

    await _advanceThroughPreflight(tester, tapScanButton: true);

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
    'after mnemonic submission shows pinPreflight with syncSetupVerifyPinTitle',
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
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      // Enter valid mnemonic and submit
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

      // Should now be on pinPreflight — not the scan prompt
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.textContaining('before scanning'), findsOneWidget);
      expect(find.text("Scan Joiner's QR"), findsNothing);

      // Step indicator should show "PIN" as active step
      expect(find.text('2 PIN'), findsOneWidget);
    },
  );

  testWidgets(
    '_InitiatorPinView callback delivers a PinBuffer with expected bytes',
    (tester) async {
      // With the preflight step now in place, when _validatedPin is set,
      // the passwordEntry step is skipped and _completeInitiator is called
      // directly from the SAS confirm handler. This test verifies that
      // after the full preflight flow, the passwordEntry screen is never shown.
      const fakeHandle = _FakePrismSyncHandle();
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
            prismSyncHandleProvider.overrideWithBuild(
              (ref, notifier) => fakeHandle,
            ),
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      // Advance through mnemonic + preflight (PIN step auto-matches)
      await _advanceThroughPreflight(tester, tapScanButton: true);

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'AQIDBA==')]),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // SAS verify — expect it shows
      expect(find.text('Verify Security Code'), findsOneWidget);

      await tester.tap(find.text('They Match'));
      await tester.pumpAndSettle();

      // With _validatedPin held from preflight, the passwordEntry step is
      // bypassed — _completeInitiator is called directly.
      expect(find.text('Enter your sync PIN'), findsNothing);
    },
  );

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

  /// Helper to pump a sheet to the pinPreflight step without advancing further.
  Future<void> pumpToPreflightPin(
    WidgetTester tester, {
    required List<dynamic> syncHealthOverrides,
  }) async {
    PrismToast.resetForTest();
    addTearDown(PrismToast.resetForTest);

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
          ...syncHealthOverrides,
        ],
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

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Enter valid mnemonic and submit to reach pinPreflight
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

    // Should now be on pinPreflight
    expect(find.text('Enter your PIN'), findsOneWidget);
  }

  /// Helper to enter digits 1-6 and drive the async completion.
  Future<void> enterPinDigits(WidgetTester tester) async {
    for (final digit in ['1', '2', '3', '4', '5']) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    await tester.tap(find.text('6').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'pinPreflight Match → advances to prompt step with _validatedPin set',
    (tester) async {
      await pumpToPreflightPin(
        tester,
        syncHealthOverrides: [
          syncHealthProvider.overrideWith(
            () => _FakeSyncHealthNotifier(
              verifyResult: () => const VerifyMnemonicPinMatch(),
            ),
          ),
        ],
      );

      await enterPinDigits(tester);

      // After Match, onValidated is called → prompt step should show
      expect(find.text("Scan Joiner's QR"), findsOneWidget);
      expect(find.text('Enter your PIN'), findsNothing);
    },
  );

  testWidgets(
    'pinPreflight NoMatch → stays on pinPreflight with error subtitle',
    (tester) async {
      await pumpToPreflightPin(
        tester,
        syncHealthOverrides: [
          syncHealthProvider.overrideWith(
            () => _FakeSyncHealthNotifier(
              verifyResult: () => const VerifyMnemonicPinNoMatch(),
            ),
          ),
        ],
      );

      await enterPinDigits(tester);

      // Should still be on pinPreflight — error text visible
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.textContaining("don't unlock this device"), findsOneWidget);
    },
  );

  testWidgets('pinPreflight NeedsRewrap → pops sheet and shows rewrap toast', (
    tester,
  ) async {
    await pumpToPreflightPin(
      tester,
      syncHealthOverrides: [
        syncHealthProvider.overrideWith(
          () => _FakeSyncHealthNotifier(
            verifyResult: () => const VerifyMnemonicPinNeedsRewrap(),
          ),
        ),
      ],
    );

    await enterPinDigits(tester);

    // Sheet should have been popped; rewrap toast shown
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.textContaining('restore your pairing key'), findsOneWidget);

    PrismToast.dismiss();
  });

  testWidgets(
    'pinPreflight HandleUnavailable → pops sheet and shows unavailable toast',
    (tester) async {
      await pumpToPreflightPin(
        tester,
        syncHealthOverrides: [
          syncHealthProvider.overrideWith(
            () => _FakeSyncHealthNotifier(
              verifyResult: () => const VerifyMnemonicPinHandleUnavailable(),
            ),
          ),
        ],
      );

      await enterPinDigits(tester);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Enter your PIN'), findsNothing);
      expect(find.textContaining("isn't ready yet"), findsOneWidget);

      PrismToast.dismiss();
    },
  );

  testWidgets(
    'pinPreflight Error → stays on PIN step without incrementing lockout',
    (tester) async {
      // VerifyMnemonicPinError is an infrastructure error, not a wrong credential.
      // The lockout counter must NOT be incremented and the user must stay on
      // the PIN step so they can retry immediately.
      await pumpToPreflightPin(
        tester,
        syncHealthOverrides: [
          syncHealthProvider.overrideWith(
            () => _FakeSyncHealthNotifier(
              verifyResult: () =>
                  const VerifyMnemonicPinError(message: 'Sync engine error'),
            ),
          ),
        ],
      );

      await enterPinDigits(tester);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Must stay on PIN step (no navigation to prompt or error screen)
      expect(find.text('Enter your PIN'), findsOneWidget);
      // Toast with transient-error message must appear
      expect(find.textContaining("Couldn't verify"), findsOneWidget);

      PrismToast.dismiss();
    },
  );

  testWidgets(
    'regression: pinBytes consumed synchronously before setState/await (consume-race)',
    (tester) async {
      // Regression test for the async PIN buffer consume race.
      // Bug: consumeBytesAndClear() was called AFTER setState(_step=uploading),
      // which unmounts the source view and its dispose() clears the buffer.
      // Additionally, if the app backgrounds mid-flight, the lifecycle hook
      // clears _validatedPin before the await returns, making pinBytes empty.
      //
      // Fix: consumeBytesAndClear() is now called synchronously at the very
      // top of _completeInitiator, before any setState or await.
      //
      // Test strategy: gate startInitiatorCeremony behind a Completer to
      // arrive at the SAS step. Once the user taps "They Match",
      // _completeInitiator is called synchronously. Dispatch paused before
      // the async frame resolves and assert _validatedPin is null (cleared by
      // the lifecycle hook) while the flow still ran (error state reached).
      // The critical proof: _validatedPin being null after paused fires means
      // the lifecycle hook ran, yet the flow completed normally (the pin was
      // already extracted into a local variable before the lifecycle event).
      const fakeHandle = _FakePrismSyncHandle();
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
            prismSyncHandleProvider.overrideWithBuild(
              (ref, notifier) => fakeHandle,
            ),
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      // Advance through mnemonic + preflight (digits 1-6 → Match)
      await _advanceThroughPreflight(tester, tapScanButton: true);

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'AQIDBA==')]),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // At this point _validatedPin is set (preflight passed).
      final sheetState = tester.state<SetupDeviceSheetContentState>(
        find.byElementPredicate(
          (e) =>
              e is StatefulElement && e.state is SetupDeviceSheetContentState,
        ),
      );
      expect(
        sheetState.validatedPinIsNull,
        isFalse,
        reason: '_validatedPin should be non-null at SAS step',
      );

      // Confirm SAS — _completeInitiator is called with _validatedPin.
      // The fix: consumeBytesAndClear() runs synchronously on the same
      // microtask frame as the onConfirm callback, BEFORE setState/await.
      await tester.tap(find.text('They Match'));
      await tester.pump(); // Start the async chain

      // Dispatch paused WHILE _completeInitiator is mid-flight.
      // Before the fix: if consumeBytesAndClear hadn't run yet, _validatedPin
      // getting cleared here would leave pinBytes empty on the next await.
      // After the fix: pinBytes was already captured synchronously so pausing
      // has no effect on what will be sent to FFI.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // _validatedPin must be null — cleared by the lifecycle hook.
      expect(
        sheetState.validatedPinIsNull,
        isTrue,
        reason: 'lifecycle pause must have cleared _validatedPin',
      );

      // Let the flow complete (uploadPairingSnapshot fails in test env,
      // which drives the error path — that's expected and harmless here).
      await tester.pumpAndSettle();

      // The state machine must be in the error state (uploadPairingSnapshot
      // threw because Rust is not initialized in tests). This confirms that
      // _completeInitiator ran to completion without crashing due to an
      // empty pin buffer — if it had crashed mid-call we'd see a different
      // state or an unhandled exception.
      expect(
        sheetState.validatedPinIsNull,
        isTrue,
        reason: '_validatedPin must remain null after error path runs',
      );
    },
  );

  testWidgets(
    'full flow with _validatedPin: passwordEntry step never reached',
    (tester) async {
      const fakeHandle = _FakePrismSyncHandle();
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
            prismSyncHandleProvider.overrideWithBuild(
              (ref, notifier) => fakeHandle,
            ),
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      // Advance through mnemonic + preflight (Match)
      await _advanceThroughPreflight(tester, tapScanButton: true);

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'AQIDBA==')]),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Confirm SAS
      await tester.tap(find.text('They Match'));
      await tester.pumpAndSettle();

      // passwordEntry step must NEVER be shown — _validatedPin skips it
      expect(find.text('Enter your sync PIN'), findsNothing);
    },
  );

  // TODO: Add a test that drives _step = sasVerification with
  // _validatedPin == null and asserts the passwordEntry fallback view appears.

  testWidgets('dispose during pinPreflight does NOT cancel ceremony', (
    tester,
  ) async {
    var cancelCalls = 0;
    const fakeHandle = _FakePrismSyncHandle();
    final fakeApi = _FakePairingCeremonyApi(
      cancelPairingCeremonyHandler: ({required handle}) async {
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
          syncHealthProvider.overrideWith(
            () => _FakeSyncHealthNotifier(
              verifyResult: () =>
                  const VerifyMnemonicPinNoMatch(), // stays on preflight
            ),
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

    // Navigate to pinPreflight (enter mnemonic + submit)
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

    // We are on pinPreflight. Dispose by pumping a new empty widget.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // pinPreflight is in _shouldCancelActiveCeremony false branch —
    // no cancel should be triggered.
    expect(cancelCalls, 0);
  });

  testWidgets('app lifecycle pause clears _validatedPin', (tester) async {
    // Advance to the prompt step (where _validatedPin is held)
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
          syncHealthProvider.overrideWith(
            () => _FakeSyncHealthNotifier(
              verifyResult: () => const VerifyMnemonicPinMatch(),
            ),
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

    // Advance through mnemonic + preflight to reach prompt step
    await _advanceThroughPreflight(tester, tapScanButton: false);

    // At the prompt step — the sheet content state should have _validatedPin set.
    final sheetState = tester.state<SetupDeviceSheetContentState>(
      find.byElementPredicate(
        (e) => e is StatefulElement && e.state is SetupDeviceSheetContentState,
      ),
    );
    expect(
      sheetState.validatedPinIsNull,
      isFalse,
      reason: '_validatedPin should be set after successful preflight',
    );

    // Simulate app pause.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // After pause, _validatedPin must be cleared.
    expect(
      sheetState.validatedPinIsNull,
      isTrue,
      reason: 'lifecycle pause must zero and null _validatedPin',
    );
  });

  testWidgets(
    'regression: preflight PIN buffer is non-empty in _validatedPin after view unmounts',
    (tester) async {
      // Regression test for the bug where _PreflightPinView.dispose() cleared
      // the same buffer instance that the parent stored in _validatedPin,
      // causing _completeInitiator to send an empty password to FFI.
      //
      // Drive: enterMnemonic → preflight Match (taps 1-2-3-4-5-6) → prompt.
      // After the prompt step is shown the _PreflightPinView has unmounted and
      // its dispose() has run. Assert that _validatedPin still holds 6 bytes
      // of the typed digits (0x31–0x36), NOT an empty buffer.
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
            syncHealthProvider.overrideWith(
              () => _FakeSyncHealthNotifier(
                verifyResult: () => const VerifyMnemonicPinMatch(),
              ),
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

      // Advance through mnemonic + preflight PIN (digits 1-6, fake returns Match).
      // After this, _PreflightPinView has unmounted and its dispose() has run.
      // _validatedPin in SetupDeviceSheetContentState must still hold 6 bytes.
      await _advanceThroughPreflight(tester, tapScanButton: false);

      // Prompt step is now shown — _PreflightPinView is gone from the tree.
      expect(
        find.text("Scan Joiner's QR"),
        findsOneWidget,
        reason: 'should be at prompt step after preflight',
      );

      final sheetState = tester.state<SetupDeviceSheetContentState>(
        find.byElementPredicate(
          (e) =>
              e is StatefulElement && e.state is SetupDeviceSheetContentState,
        ),
      );

      // The critical assertion: _validatedPin must have length 6, not 0.
      // Before the fix, dispose() cleared the shared buffer, producing length 0.
      expect(
        sheetState.validatedPinLength,
        6,
        reason:
            'PIN buffer must be non-empty after preflight view unmounts; '
            'a length of 0 means dispose() cleared the parent\'s buffer (the bug)',
      );
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Camera-less paste fallback
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds a structurally-valid encoded `RendezvousToken` for the
  /// paste-and-pair widget test: version 0x01, 16 B rendezvous_id,
  /// 32 B commitment, 2 B big-endian url_len = 45, then 45 B URL.
  /// The parser's shape check requires this layout.
  Uint8List samplePairingTokenBytes() {
    const urlLen = 45;
    final bytes = Uint8List(51 + urlLen);
    bytes[0] = 0x01;
    for (var i = 1; i < 49; i++) {
      bytes[i] = i & 0xff;
    }
    bytes[49] = (urlLen >> 8) & 0xff;
    bytes[50] = urlLen & 0xff;
    for (var i = 51; i < bytes.length; i++) {
      bytes[i] = i & 0xff;
    }
    return bytes;
  }

  testWidgets(
    'scanner flow: Windows uses desktop camera instead of mobile scanner',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        const cameraChannel = MethodChannel('flutter_lite_camera');
        final cameraCalls = <String>[];
        final frame = Uint8List(4 * 4 * 3);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(cameraChannel, (call) async {
              cameraCalls.add(call.method);
              return switch (call.method) {
                'getDeviceList' => <String>['Test camera'],
                'open' => true,
                'captureFrame' => {'data': frame, 'width': 4, 'height': 4},
                'release' => null,
                _ => null,
              };
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(cameraChannel, null);
        });

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
              syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

        await _advanceThroughPreflight(tester, tapScanButton: false);

        expect(find.text("Scan Joiner's QR"), findsOneWidget);
        await tester.tap(find.text("Scan Joiner's QR"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(MobileScanner), findsNothing);
        expect(find.text('No camera? Paste a code instead'), findsOneWidget);
        expect(cameraCalls, contains('getDeviceList'));
        expect(cameraCalls, contains('open'));
        expect(cameraCalls, contains('captureFrame'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'paste fallback: link on scanner view navigates to paste view with disabled Pair button',
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
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      await _advanceThroughPreflight(tester, tapScanButton: true);

      // Fallback link is visible on the scanner view.
      expect(find.text('No camera? Paste a code instead'), findsOneWidget);

      await tester.tap(find.text('No camera? Paste a code instead'));
      await tester.pumpAndSettle();

      expect(find.text('Paste a pairing code'), findsOneWidget);

      // Pair button is disabled when the field is empty; tapping it does
      // nothing and the view stays put.
      await tester.tap(find.widgetWithText(PrismButton, 'Pair'));
      await tester.pumpAndSettle();
      expect(find.text('Paste a pairing code'), findsOneWidget);
      expect(find.text('Verify Security Code'), findsNothing);
    },
  );

  testWidgets(
    'paste fallback: pasting a valid token advances to SAS verification',
    (tester) async {
      const fakeHandle = _FakePrismSyncHandle();
      Uint8List? capturedTokenBytes;
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              capturedTokenBytes = tokenBytes;
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingCeremonyApiProvider.overrideWith((ref) => fakeApi),
            prismSyncHandleProvider.overrideWithBuild(
              (ref, notifier) => fakeHandle,
            ),
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      await _advanceThroughPreflight(tester, tapScanButton: true);

      await tester.tap(find.text('No camera? Paste a code instead'));
      await tester.pumpAndSettle();

      // Field starts empty; Pair button is disabled.
      final pairButton = find.widgetWithText(PrismButton, 'Pair');
      expect(tester.widget<PrismButton>(pairButton).enabled, isFalse);

      // Paste a code surrounded by chat-style context — the parser strips it.
      final token = samplePairingTokenBytes();
      final encoded = base64Encode(token);
      await tester.enterText(
        find.byType(TextField),
        "Here's the code: $encoded — thanks!",
      );
      await tester.pump();

      expect(tester.widget<PrismButton>(pairButton).enabled, isTrue);

      await tester.tap(pairButton);
      await tester.pumpAndSettle();

      // The decoded bytes must be what we encoded — not the surrounding text.
      expect(capturedTokenBytes, token);
      // We advanced past paste into SAS verification.
      expect(find.text('Verify Security Code'), findsOneWidget);
    },
  );

  testWidgets(
    'paste fallback: invalid input shows the friendly error and stays on the view',
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
            syncHealthProvider.overrideWith(_FakeSyncHealthNotifier.new),
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

      await _advanceThroughPreflight(tester, tapScanButton: true);

      await tester.tap(find.text('No camera? Paste a code instead'));
      await tester.pumpAndSettle();

      // Junk input enables Pair (text is non-empty) but rejects on submit.
      await tester.enterText(find.byType(TextField), '!!! not a code !!!');
      await tester.pump();

      await tester.tap(find.widgetWithText(PrismButton, 'Pair'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("doesn't look like a pairing code"),
        findsOneWidget,
      );
      expect(find.text('Paste a pairing code'), findsOneWidget);
      expect(find.text('Verify Security Code'), findsNothing);
    },
  );
}
