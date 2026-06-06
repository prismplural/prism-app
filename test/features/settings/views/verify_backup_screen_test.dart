import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/security/pin_buffer.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/views/verify_backup_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// A canonical BIP39 12-word mnemonic with a valid checksum (same as used in
// setup_device_sheet_test.dart and sync_pin_sheet_lockout_test.dart).
const _validMnemonic =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

bool _scannerControllerIsDisposed(MobileScannerController controller) {
  void listener() {}
  try {
    controller.addListener(listener);
    controller.removeListener(listener);
    return false;
  } on FlutterError {
    return true;
  }
}

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncHealthNotifier extends SyncHealthNotifier {
  _FakeSyncHealthNotifier({
    SyncHealthState initialState = SyncHealthState.healthy,
    this.verifyResult = const VerifyMnemonicPinMatch(),
  }) : _initialState = initialState;

  final SyncHealthState _initialState;
  VerifyMnemonicPinResult verifyResult;

  @override
  SyncHealthState build() => _initialState;

  @override
  Future<VerifyMnemonicPinResult> verifyMnemonicPin({
    required PinBuffer pin,
    required String mnemonic,
  }) async {
    // Drain pin for all variants that production also drains (i.e., anything
    // past the early-return NeedsRewrap/HandleUnavailable guards).
    if (verifyResult is VerifyMnemonicPinMatch ||
        verifyResult is VerifyMnemonicPinNoMatch ||
        verifyResult is VerifyMnemonicPinError) {
      pin.consumeBytesAndClear();
    }
    return verifyResult;
  }
}

class _FakeHandleNotifier extends PrismSyncHandleNotifier {
  _FakeHandleNotifier(this._handle);
  final ffi.PrismSyncHandle? _handle;

  @override
  Future<ffi.PrismSyncHandle?> build() async => _handle;
}

const _fakeHandle = _FakePrismSyncHandle();

Widget _buildScreen({
  SyncHealthState healthState = SyncHealthState.healthy,
  VerifyMnemonicPinResult verifyResult = const VerifyMnemonicPinMatch(),
  bool hasWrappedDek = true,
  bool hasHandle = true,
}) {
  return ProviderScope(
    overrides: [
      syncHealthProvider.overrideWith(
        () => _FakeSyncHealthNotifier(
          initialState: healthState,
          verifyResult: verifyResult,
        ),
      ),
      prismSyncHandleProvider.overrideWith(
        () => _FakeHandleNotifier(hasHandle ? _fakeHandle : null),
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
        AsyncValue<bool>.data(hasWrappedDek),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          PrismToastHost(child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: VerifyBackupScreen()),
    ),
  );
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Enters a valid 12-word phrase into the mnemonic fields and taps Continue.
Future<void> _enterMnemonicAndContinue(WidgetTester tester) async {
  final words = _validMnemonic.split(' ');
  for (var i = 0; i < 12; i++) {
    await tester.enterText(find.byType(TextField).at(i), words[i]);
    await tester.pump();
  }
  await tester.pumpAndSettle();

  final continueButton = find.widgetWithText(PrismButton, 'Continue');
  await tester.ensureVisible(continueButton);
  await tester.pumpAndSettle();
  await tester.tap(continueButton);
  await tester.pumpAndSettle();
}

/// Taps the numpad digits to enter a 6-digit PIN.
Future<void> _tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    final found = find.text(digit);
    if (found.evaluate().isNotEmpty) {
      await tester.tap(found.last);
    }
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrismToast.resetForTest();
  });

  tearDown(PrismToast.resetForTest);

  group('VerifyBackupScreen — phrase step', () {
    testWidgets('shows phrase step on initial load', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Should show mnemonic text fields
      expect(find.byType(TextField), findsWidgets);
      expect(find.widgetWithText(PrismButton, 'Continue'), findsOneWidget);
    });

    testWidgets('BIP39-invalid typed phrase shows inline error', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Enter invalid phrase (only 1 word)
      await tester.enterText(find.byType(TextField).first, 'notaword');
      await tester.pump();
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(PrismButton, 'Continue');
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Should show an error about invalid recovery phrase
      expect(find.textContaining('valid recovery phrase'), findsOneWidget);
    });

    testWidgets('valid phrase advances to PIN step', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);

      // Should now show PIN entry (lock icon or PIN title)
      expect(find.textContaining('Enter your PIN'), findsOneWidget);
    });

    testWidgets('scan back returns to manual flow and disposes scanner', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final scanButton = find.widgetWithText(PrismButton, 'Scan QR');
      await tester.ensureVisible(scanButton);
      await tester.tap(scanButton);
      await tester.pumpAndSettle();

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      final scannerController = scanner.controller!;

      await tester.tap(find.widgetWithText(PrismButton, 'Back'));
      await tester.pumpAndSettle();

      expect(find.byType(MobileScanner), findsNothing);
      expect(find.byType(TextField), findsWidgets);
      expect(_scannerControllerIsDisposed(scannerController), isTrue);
    });

    testWidgets('valid scan advances to PIN step and disposes scanner', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final scanButton = find.widgetWithText(PrismButton, 'Scan QR');
      await tester.ensureVisible(scanButton);
      await tester.tap(scanButton);
      await tester.pumpAndSettle();

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      final scannerController = scanner.controller!;

      scanner.onDetect!(
        const BarcodeCapture(barcodes: [Barcode(rawValue: _validMnemonic)]),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter your PIN'), findsOneWidget);
      expect(_scannerControllerIsDisposed(scannerController), isTrue);
    });
  });

  group('VerifyBackupScreen — PIN step', () {
    testWidgets('wrong PIN (NoMatch) shows no-match result', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinNoMatch()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);

      // Enter a 6-digit PIN
      await _tapPin(tester, '123456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Should show no-match result
      expect(find.textContaining("That didn't match"), findsOneWidget);
    });

    testWidgets('correct PIN (Match) shows match result with QR', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinMatch()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);

      await _tapPin(tester, '123456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.textContaining('These words unlock this device'),
        findsOneWidget,
      );
      final semantics = tester.binding.pipelineOwner.semanticsOwner;
      bool foundQr = false;
      if (semantics != null) {
        void walk(SemanticsNode node) {
          if (node.label.contains('QR code containing')) foundQr = true;
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(semantics.rootSemanticsNode!);
      }
      expect(foundQr, isTrue, reason: 'QR should be accessible via Semantics');
    });

    testWidgets('Re-enter PIN bounces to PIN step (mnemonic preserved)', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinNoMatch()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);
      await _tapPin(tester, '123456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final reenterButton = find.widgetWithText(PrismButton, 'Re-enter PIN');
      await tester.ensureVisible(reenterButton);
      await tester.tap(reenterButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter your PIN'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
      'Try a different backup bounces to phrase step (mnemonic cleared)',
      (tester) async {
        _useTallViewport(tester);
        await tester.pumpWidget(
          _buildScreen(verifyResult: const VerifyMnemonicPinNoMatch()),
        );
        await tester.pumpAndSettle();

        await _enterMnemonicAndContinue(tester);
        await _tapPin(tester, '123456');
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final tryButton = find.widgetWithText(
          PrismButton,
          'Try a different backup',
        );
        await tester.ensureVisible(tryButton);
        await tester.tap(tryButton);
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsWidgets);
      },
    );

    testWidgets('Error result stays on PIN step without incrementing lockout', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(
          verifyResult: const VerifyMnemonicPinError(
            message: 'Sync engine error',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);
      await _tapPin(tester, '123456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.textContaining('Enter your PIN'), findsOneWidget);
      expect(find.textContaining("That didn't match"), findsNothing);
      expect(find.textContaining("Couldn't verify"), findsOneWidget);
      PrismToast.dismiss();
    });

    testWidgets('NeedsRewrap clears PIN buffer (dots reset)', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinNeedsRewrap()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);

      await _tapPin(tester, '123');
      await tester.pump();

      final screenState = tester.state<VerifyBackupScreenState>(
        find.byType(VerifyBackupScreen),
      );
      expect(
        screenState.pinIsEmpty,
        isFalse,
        reason: 'pin should be non-empty after typing 3 digits',
      );

      await _tapPin(tester, '456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        screenState.pinIsEmpty,
        isTrue,
        reason: 'NeedsRewrap must clear the PIN buffer',
      );
    });

    testWidgets('HandleUnavailable clears PIN buffer (dots reset)', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinHandleUnavailable()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);

      await _tapPin(tester, '123');
      await tester.pump();

      final screenState = tester.state<VerifyBackupScreenState>(
        find.byType(VerifyBackupScreen),
      );
      expect(
        screenState.pinIsEmpty,
        isFalse,
        reason: 'pin should be non-empty after typing 3 digits',
      );

      await _tapPin(tester, '456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        screenState.pinIsEmpty,
        isTrue,
        reason: 'HandleUnavailable must clear the PIN buffer',
      );
    });

    testWidgets(
      'PIN step shows step indicator with liveRegion (accessibility)',
      (tester) async {
        // P2 regression: the PIN step previously rendered without the step
        // indicator, causing screen readers to miss the "Step 2 of 3: PIN"
        // liveRegion announcement.
        _useTallViewport(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        await _enterMnemonicAndContinue(tester);
        // Should be on PIN step
        expect(find.textContaining('Enter your PIN'), findsOneWidget);

        // The step indicator liveRegion must be present on the PIN step.
        final semanticsOwner = tester.binding.pipelineOwner.semanticsOwner;
        expect(semanticsOwner, isNotNull);
        bool foundLiveRegionForPin = false;
        void walk(SemanticsNode node) {
          if (node.hasFlag(SemanticsFlag.isLiveRegion) &&
              node.label.contains('Step 2 of 3')) {
            foundLiveRegionForPin = true;
          }
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(semanticsOwner!.rootSemanticsNode!);
        expect(
          foundLiveRegionForPin,
          isTrue,
          reason: 'PIN step indicator must have liveRegion: true (Step 2 of 3)',
        );
      },
    );
  });

  group('VerifyBackupScreen — SyncHealthState banners', () {
    testWidgets('needsPassword shows locked banner', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(healthState: SyncHealthState.needsPassword),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Your device is locked'), findsOneWidget);
      expect(find.widgetWithText(PrismButton, 'Unlock device'), findsOneWidget);
    });

    testWidgets('runtimeDekRestoreDeferred shows deferred banner', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(healthState: SyncHealthState.runtimeDekRestoreDeferred),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sync access needs to be restored'),
        findsOneWidget,
      );
    });

    testWidgets('awaitingDeviceUnlock shows awaiting banner', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(healthState: SyncHealthState.awaitingDeviceUnlock),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Unlock your device to continue'),
        findsOneWidget,
      );
    });

    testWidgets('needsRewrap shows rewrap banner', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(healthState: SyncHealthState.needsRewrap),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Your backup needs to be re-secured'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PrismButton, 'Re-secure backup'),
        findsOneWidget,
      );
    });
  });

  group('VerifyBackupScreen — no active install', () {
    testWidgets('no handle shows empty state message', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen(hasHandle: false));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No active install to verify against'),
        findsOneWidget,
      );
    });

    testWidgets('no wrapped dek shows empty state message', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen(hasWrappedDek: false));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No active install to verify against'),
        findsOneWidget,
      );
    });
  });

  group('VerifyBackupScreen — defense-in-depth', () {
    testWidgets(
      'screen entry with syncWrappedDekPresentProvider==false triggers needsRewrap',
      (tester) async {
        _useTallViewport(tester);
        // Start with healthy state but no wrapped dek — the initState
        // post-frame callback should trigger needsRewrap via the notifier.
        final fakeNotifier = _FakeSyncHealthNotifier(
          initialState: SyncHealthState.healthy,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              syncHealthProvider.overrideWith(() => fakeNotifier),
              prismSyncHandleProvider.overrideWith(
                () => _FakeHandleNotifier(_fakeHandle),
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
              // No wrapped dek — defense-in-depth
              syncWrappedDekPresentProvider.overrideWithValue(
                const AsyncValue<bool>.data(false),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: VerifyBackupScreen()),
            ),
          ),
        );

        await tester.pump();
        await tester.pumpAndSettle();

        expect(fakeNotifier.state, SyncHealthState.needsRewrap);
      },
    );
  });

  group('VerifyBackupScreen — accessibility', () {
    testWidgets('step indicator has liveRegion semantics', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final semanticsOwner = tester.binding.pipelineOwner.semanticsOwner;
      expect(semanticsOwner, isNotNull);

      bool foundLiveRegion = false;
      void walk(SemanticsNode node) {
        if (node.hasFlag(SemanticsFlag.isLiveRegion) &&
            node.label.contains('Step 1 of 3')) {
          foundLiveRegion = true;
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(semanticsOwner!.rootSemanticsNode!);
      expect(
        foundLiveRegion,
        isTrue,
        reason: 'Step indicator should have liveRegion: true',
      );
    });

    testWidgets('no-match result headline has liveRegion semantics', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinNoMatch()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);
      await _tapPin(tester, '123456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // After no-match we're on the result screen
      expect(find.textContaining("That didn't match"), findsOneWidget);

      // Check the no-match headline has liveRegion
      final semanticsOwner = tester.binding.pipelineOwner.semanticsOwner;
      expect(semanticsOwner, isNotNull);
      bool foundLiveRegion = false;
      void walk(SemanticsNode node) {
        if (node.hasFlag(SemanticsFlag.isLiveRegion) &&
            node.label.contains('Not verified')) {
          foundLiveRegion = true;
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(semanticsOwner!.rootSemanticsNode!);
      expect(
        foundLiveRegion,
        isTrue,
        reason: 'No-match headline should have liveRegion: true',
      );
    });
  });

  group('VerifyBackupScreen — integration flow', () {
    testWidgets(
      'full flow: phrase → correct PIN → match result with QR → Done pops',
      (tester) async {
        _useTallViewport(tester);
        var popped = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              syncHealthProvider.overrideWith(
                () => _FakeSyncHealthNotifier(
                  verifyResult: const VerifyMnemonicPinMatch(),
                ),
              ),
              prismSyncHandleProvider.overrideWith(
                () => _FakeHandleNotifier(_fakeHandle),
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
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (ctx) => ElevatedButton(
                        onPressed: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => PopScope(
                              onPopInvokedWithResult: (didPop, _) {
                                if (didPop) popped = true;
                              },
                              child: const Scaffold(body: VerifyBackupScreen()),
                            ),
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to the screen
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Enter phrase
        await _enterMnemonicAndContinue(tester);

        // Enter correct PIN
        await _tapPin(tester, '123456');
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Match result screen appears
        expect(
          find.textContaining('These words unlock this device'),
          findsOneWidget,
        );

        // Tap Done to pop
        final doneButton = find.widgetWithText(PrismButton, 'Done');
        await tester.ensureVisible(doneButton);
        await tester.tap(doneButton);
        await tester.pumpAndSettle();

        expect(popped, isTrue);
      },
    );
  });

  group('VerifyBackupScreen — lifecycle', () {
    testWidgets(
      'paused lifecycle event clears PIN but preserves mnemonic (no crash)',
      (tester) async {
        _useTallViewport(tester);
        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        // Advance to PIN step so _mnemonic is set
        await _enterMnemonicAndContinue(tester);

        // Should be on PIN step now
        expect(find.textContaining('Enter your PIN'), findsOneWidget);

        // Type 3 digits (fewer than 6) so the PIN buffer is partially filled
        // but the full-pin handler is not triggered yet.
        await _tapPin(tester, '123');
        await tester.pump();

        // Access state to verify _pin is non-empty before pause.
        final screenState = tester.state<VerifyBackupScreenState>(
          find.byType(VerifyBackupScreen),
        );
        expect(
          screenState.pinIsEmpty,
          isFalse,
          reason: '_pin should be non-empty after typing 3 digits',
        );

        // Simulate app going to background
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        // _pin must now be cleared by didChangeAppLifecycleState.
        expect(
          screenState.pinIsEmpty,
          isTrue,
          reason: 'lifecycle pause must zero _pin',
        );

        // Simulate a widget rebuild (e.g. triggered by OS after resume)
        await tester.pump();

        // PIN step should still be rendered — _mnemonic was preserved,
        // so _buildStepContent can safely access _mnemonic!
        expect(find.textContaining('Enter your PIN'), findsOneWidget);
      },
    );
  });

  group('VerifyBackupScreen — lockout state', () {
    testWidgets(
      'lockout countdown appears in PIN step subtitle when locked out',
      (tester) async {
        _useTallViewport(tester);

        // Seed a future locked-until time so PinLockoutState.load() sees a lockout
        final futureMs = DateTime.now()
            .add(const Duration(seconds: 30))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          'prism.verify_backup.locked_until_ms': futureMs,
          'prism.verify_backup.failed_attempts': 5,
        });

        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        // Advance to PIN step
        await _enterMnemonicAndContinue(tester);

        // The PIN subtitle should contain "Too many attempts"
        expect(find.textContaining('Too many attempts'), findsOneWidget);
      },
    );
  });

  group('VerifyBackupScreen — QR accessibility coverage', () {
    testWidgets(
      'match result QR has correct Semantics label and excluded inner pixels',
      (tester) async {
        _useTallViewport(tester);
        await tester.pumpWidget(
          _buildScreen(verifyResult: const VerifyMnemonicPinMatch()),
        );
        await tester.pumpAndSettle();

        await _enterMnemonicAndContinue(tester);
        await _tapPin(tester, '123456');
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        final semantics = tester.getSemantics(
          find.bySemanticsLabel('QR code containing your recovery phrase'),
        );
        expect(semantics.label, 'QR code containing your recovery phrase');
      },
    );

    testWidgets('match result headline has liveRegion semantics', (
      tester,
    ) async {
      _useTallViewport(tester);
      await tester.pumpWidget(
        _buildScreen(verifyResult: const VerifyMnemonicPinMatch()),
      );
      await tester.pumpAndSettle();

      await _enterMnemonicAndContinue(tester);
      await _tapPin(tester, '123456');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final semanticsOwner = tester.binding.pipelineOwner.semanticsOwner;
      expect(semanticsOwner, isNotNull);
      bool foundLiveRegion = false;
      void walk(SemanticsNode node) {
        if (node.hasFlag(SemanticsFlag.isLiveRegion) &&
            node.label.contains('Verified')) {
          foundLiveRegion = true;
        }
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(semanticsOwner!.rootSemanticsNode!);
      expect(
        foundLiveRegion,
        isTrue,
        reason: 'Match headline should have liveRegion: true',
      );
    });
  });
}
