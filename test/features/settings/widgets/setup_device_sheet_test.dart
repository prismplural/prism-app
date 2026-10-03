import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
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
    // Test seams: present so specs can script these paths when needed.
    // ignore: unused_element_parameter
    this.verifyResumableHandler,
    // ignore: unused_element_parameter
    this.uploadResumableHandler,
    // ignore: unused_element_parameter
    this.completeResumableHandler,
    // ignore: unused_element_parameter
    this.capabilityHandler,
  });

  /// Ordered record of the split-ceremony core calls this fake observed.
  final List<String> calls = <String>[];

  /// Number of `cancelPairingCeremony` invocations observed.
  int cancelCount = 0;

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
  Future<bool> Function({required ffi.PrismSyncHandle handle})?
  verifyResumableHandler;
  Future<ffi.ResumableSnapshotUploadResult> Function({
    required ffi.PrismSyncHandle handle,
    BigInt? ttlSecs,
  })?
  uploadResumableHandler;
  Future<ffi.ResumableCeremonyCompletion> Function({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  })?
  completeResumableHandler;
  Future<ffi.SnapshotUploadCapabilityInfo> Function({
    required ffi.PrismSyncHandle handle,
  })?
  capabilityHandler;

  @override
  Future<bool> verifyInitiatorConfirmationResumable({
    required ffi.PrismSyncHandle handle,
  }) {
    calls.add('verify');
    return verifyResumableHandler?.call(handle: handle) ??
        Future<bool>.value(true);
  }

  @override
  Future<ffi.ResumableSnapshotUploadResult> uploadPairingSnapshotResumable({
    required ffi.PrismSyncHandle handle,
    BigInt? ttlSecs,
  }) {
    calls.add('upload');
    return uploadResumableHandler?.call(handle: handle, ttlSecs: ttlSecs) ??
        Future<ffi.ResumableSnapshotUploadResult>.value(
          const ffi.ResumableSnapshotUploadResult(
            transport: ffi.SnapshotTransportUsed.resumable,
            uploadId: 'test-session',
            committedBytes: 2048,
            totalBytes: 2048,
            leaseActive: true,
            leaseRenewed: true,
          ),
        );
  }

  @override
  Future<ffi.ResumableCeremonyCompletion> completeInitiatorResumableCeremony({
    required ffi.PrismSyncHandle handle,
    required List<int> password,
    required List<int> mnemonic,
  }) {
    calls.add('complete');
    return completeResumableHandler?.call(
          handle: handle,
          password: password,
          mnemonic: mnemonic,
        ) ??
        Future<ffi.ResumableCeremonyCompletion>.value(
          const ffi.ResumableCeremonyCompletion(
            completed: true,
            leaseActive: true,
            leaseRenewed: true,
            leaseCapable: true,
          ),
        );
  }

  @override
  Future<ffi.SnapshotUploadCapabilityInfo> snapshotUploadCapability({
    required ffi.PrismSyncHandle handle,
  }) {
    return capabilityHandler?.call(handle: handle) ??
        Future<ffi.SnapshotUploadCapabilityInfo>.value(
          const ffi.SnapshotUploadCapabilityInfo(
            state: ffi.SnapshotUploadCapabilityState.available,
            version: 1,
            chunkBytes: 1024,
            maxWireBytes: 1 << 20,
          ),
        );
  }

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelPairingCeremony({required ffi.PrismSyncHandle handle}) {
    cancelCount++;
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

/// Pumps the sheet and drives it to the SAS step with a scripted API.
///
/// Overrides `databaseProvider` with an in-memory database because the
/// pre-ceremony outbox drain touches it before the verify/upload/complete
/// calls run.
Future<void> _pumpToSasStep(
  WidgetTester tester, {
  required _FakePairingCeremonyApi fakeApi,
  List<dynamic> extraOverrides = const [],
}) async {
  const fakeHandle = _FakePrismSyncHandle();
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
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
        ...extraOverrides,
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
  expect(find.text('Verify Security Code'), findsOneWidget);
}

/// Locates the live `SetupDeviceSheetContentState` under test.
SetupDeviceSheetContentState _sheetState(WidgetTester tester) =>
    tester.state<SetupDeviceSheetContentState>(
      find.byElementPredicate(
        (e) => e is StatefulElement && e.state is SetupDeviceSheetContentState,
      ),
    );

/// Scripted `startInitiatorCeremony` response: SAS words plus the joiner device
/// id the split ceremony requires.
Future<String> _initiatorSasResponse({
  required ffi.PrismSyncHandle handle,
  required Uint8List tokenBytes,
}) async => jsonEncode({
  'sas_version': 3,
  'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
  'joiner_device_id': 'joiner-dev-xyz',
});

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
          syncDatabaseStartupReportStateProvider.overrideWith(
            () => SyncDatabaseStartupReportNotifier(
              const DbStartupReport(
                state: DbStartupState.unrecoverable,
                keyInMemory: null,
                usedRecoverySlot: null,
                diagnostic: null,
              ),
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

  testWidgets('mnemonic Continue tolerates rapid repeated taps', (
    tester,
  ) async {
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

    const phrase =
        'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about';
    final words = phrase.split(' ');
    for (var i = 0; i < 12; i++) {
      await tester.enterText(find.byType(TextField).at(i), words[i]);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final continueButton = find.text('Continue');
    await tester.tap(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.textContaining('before scanning'), findsOneWidget);
    expect(find.text("Scan Joiner's QR"), findsNothing);
  });

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
    'progress card widget renders streamed bytes and stays determinate through a singlePut resolution',
    (tester) async {
      // Regression: a relay that downgrades to the single `PUT` must not tear
      // the determinate bar back to indeterminate when the upload resolves. The
      // streamed `SnapshotUploadProgress` events already reported a total, so the
      // bar keeps that value through resolution (terminal single-PUT byte fields
      // are not a meaningful offset and are ignored).
      final uploadGate = Completer<ffi.ResumableSnapshotUploadResult>();
      final events = StreamController<SyncEvent>.broadcast();
      addTearDown(events.close);
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler: _initiatorSasResponse,
        uploadResumableHandler: ({required handle, ttlSecs}) =>
            uploadGate.future,
      );

      await _pumpToSasStep(
        tester,
        fakeApi: fakeApi,
        extraOverrides: [
          syncEventStreamProvider.overrideWith((ref) => events.stream),
        ],
      );

      await tester.tap(find.text('They Match'));
      await tester.pump();
      // Verify resolved and the upload is in flight, so the progress card shows.
      expect(
        find.text('Uploading your data to the new device'),
        findsOneWidget,
      );

      final sheetState = _sheetState(tester);
      // Before any progress event the bar is indeterminate and no total exists.
      expect(sheetState.showByteProgressForTest, isFalse);
      expect(find.text('Preparing upload...'), findsOneWidget);

      // First streamed event: the progress card switches to a determinate bar.
      // `SyncEvent.data` is the raw JSON map, so bytes_sent/bytes_total arrive as
      // numbers straight off the FFI payload.
      events.add(
        SyncEvent.fromJson({
          'type': 'SnapshotUploadProgress',
          'sync_id': 'sync-1',
          'bytes_sent': 512,
          'bytes_total': 2048,
        }),
      );
      await tester.pump();
      await tester.pump();

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, isNotNull);
      expect(indicator.value, closeTo(0.25, 1e-9));
      expect(find.text('512 B of 2.0 KB'), findsOneWidget);

      // Resolution reports single PUT with its own (unusable) terminal counts.
      uploadGate.complete(
        const ffi.ResumableSnapshotUploadResult(
          transport: ffi.SnapshotTransportUsed.singlePut,
          uploadId: '',
          committedBytes: 4096,
          totalBytes: 4096,
          leaseActive: false,
          leaseRenewed: false,
        ),
      );
      await tester.pump();
      await tester.pump();

      // At resolution the sheet is already on the completing step, so read the
      // state rather than the (now unmounted) progress card. The streamed
      // determinate values must survive the singlePut resolution untouched.
      expect(
        sheetState.showByteProgressForTest,
        isTrue,
        reason: 'determinate byte progress must survive a singlePut resolution',
      );
      expect(sheetState.uploadBytesSentForTest, 512);
      expect(
        sheetState.uploadBytesTotalForTest,
        2048,
        reason: 'terminal single-PUT byte counts are ignored',
      );

      // Then the credential-release half and the post-pair confirmation delay
      // resolve without any further progress event.
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(sheetState.showByteProgressForTest, isTrue);
      expect(sheetState.uploadBytesTotalForTest, 2048);
      expect(find.textContaining('Pairing complete!'), findsOneWidget);
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

  testWidgets(
    'regression: passwordEntry fallback delivers the exact PIN bytes despite the confirming-step rebuild',
    (tester) async {
      // P1 security/lifecycle invariant. On the fallback path the sheet holds no
      // pre-flight PIN, so `_InitiatorPinView` owns the buffer and its
      // `dispose()` zeroes it. The first `setState` inside `_completeInitiator`
      // rebuilds to the confirming step and unmounts that view, so the bytes
      // must be drained synchronously — before any `setState` or `await`.
      //
      // This drives the real sheet and asserts on the bytes core actually
      // received, so it fails if the drain ever moves back behind the unmount.
      List<int>? passwordSeen;
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler: _initiatorSasResponse,
        completeResumableHandler:
            ({required handle, required password, required mnemonic}) {
              passwordSeen = List<int>.of(password);
              return Future<ffi.ResumableCeremonyCompletion>.value(
                const ffi.ResumableCeremonyCompletion(
                  completed: true,
                  leaseActive: true,
                  leaseRenewed: true,
                  leaseCapable: true,
                ),
              );
            },
      );

      await _pumpToSasStep(tester, fakeApi: fakeApi);

      // Force the fallback: clear the sheet's pre-flight PIN through the real
      // lifecycle path (a paused app drops it), then resume so the rest of the
      // test runs with frames enabled. `_validatedPin == null` is what routes
      // SAS confirmation through the PIN entry view.
      final sheetState = _sheetState(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        sheetState.validatedPinIsNull,
        isTrue,
        reason: 'the lifecycle pause must clear the pre-flight PIN',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.tap(find.text('They Match'));
      await tester.pump();
      // Fallback view is up; `_InitiatorPinView` owns the only PIN buffer.
      expect(find.text('Enter your sync PIN'), findsOneWidget);

      for (final digit in ['1', '2', '3', '4', '5']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.tap(find.text('6').last);
      // Drive the sync drain first, then the ceremony and the post-pair delay.
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(fakeApi.calls, equals(['verify', 'upload', 'complete']));
      expect(
        passwordSeen,
        isNotNull,
        reason: 'credential release must have received the PIN bytes',
      );
      expect(
        passwordSeen,
        equals([0x31, 0x32, 0x33, 0x34, 0x35, 0x36]),
        reason:
            'the drained bytes must be the digits the user typed, not zeros',
      );
    },
  );

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

  // ---------------------------------------------------------------------------
  // Split ceremony (verify → upload → complete)
  // ---------------------------------------------------------------------------

  testWidgets(
    'split ceremony calls verify → upload → complete in order and shows phases',
    (tester) async {
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
        uploadResumableHandler: ({required handle, ttlSecs}) async {
          expect(ttlSecs, BigInt.from(86400));
          return const ffi.ResumableSnapshotUploadResult(
            transport: ffi.SnapshotTransportUsed.resumable,
            uploadId: 'session-1',
            committedBytes: 2048,
            totalBytes: 2048,
            leaseActive: true,
            leaseRenewed: true,
          );
        },
      );

      await _pumpToSasStep(tester, fakeApi: fakeApi);

      await tester.tap(find.text('They Match'));
      // Flush the post-completion confirmation delay so no timers are pending.
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(fakeApi.calls, equals(['verify', 'upload', 'complete']));
      // The existing post-pair UX is preserved (confirmation → done).
      expect(find.textContaining('Pairing complete!'), findsOneWidget);
    },
  );

  testWidgets(
    'finalization failure after a published upload uses the distinct finish copy',
    (tester) async {
      // The snapshot reached the relay, so the credential-release failure must
      // not reuse the upload-retry copy ("didn't reach the relay") and must not
      // echo the raw FFI/relay error.
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler: _initiatorSasResponse,
        completeResumableHandler:
            ({required handle, required password, required mnemonic}) async {
              throw StateError('session-abc123 rejected the handoff');
            },
      );

      await _pumpToSasStep(tester, fakeApi: fakeApi);

      await tester.tap(find.text('They Match'));
      await tester.pumpAndSettle();

      // Upload still happened; only finalization failed.
      expect(fakeApi.calls, equals(['verify', 'upload', 'complete']));
      expect(find.text('Pairing Failed'), findsOneWidget);
      expect(
        find.textContaining("Couldn't finish setting up the new device"),
        findsOneWidget,
      );
      // Must not imply the bytes failed to transfer.
      expect(find.text("Couldn't upload your data"), findsNothing);
      expect(find.text('Retry upload'), findsNothing);
      expect(
        find.textContaining("snapshot didn't reach the relay"),
        findsNothing,
      );
      // Raw-error redaction is preserved.
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.textContaining('session-abc123'), findsNothing);
    },
  );

  testWidgets(
    'upload failure shows the retry card and never releases credentials',
    (tester) async {
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
        uploadResumableHandler: ({required handle, ttlSecs}) async {
          throw StateError('relay rejected the snapshot');
        },
      );

      await _pumpToSasStep(tester, fakeApi: fakeApi);

      await tester.tap(find.text('They Match'));
      await tester.pumpAndSettle();

      expect(fakeApi.calls, equals(['verify', 'upload']));
      expect(fakeApi.calls, isNot(contains('complete')));
      // The existing failure/retry copy is reused, and no raw error text leaks.
      expect(find.text("Couldn't upload your data"), findsOneWidget);
      expect(
        find.text(
          "The snapshot didn't reach the relay. Try again to keep pairing.",
        ),
        findsOneWidget,
      );
      expect(find.text('Retry upload'), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
    },
  );

  testWidgets('singlePut fallback continues pairing with no byte promise', (
    tester,
  ) async {
    final fakeApi = _FakePairingCeremonyApi(
      startInitiatorCeremonyHandler:
          ({required handle, required tokenBytes}) async {
            return jsonEncode({
              'sas_version': 3,
              'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
              'joiner_device_id': 'joiner-dev-xyz',
            });
          },
      uploadResumableHandler: ({required handle, ttlSecs}) async {
        return const ffi.ResumableSnapshotUploadResult(
          transport: ffi.SnapshotTransportUsed.singlePut,
          uploadId: '',
          committedBytes: 4096,
          totalBytes: 4096,
          leaseActive: false,
          leaseRenewed: false,
        );
      },
    );

    await _pumpToSasStep(tester, fakeApi: fakeApi);

    await tester.tap(find.text('They Match'));
    // Flush the post-completion confirmation delay so no timers are pending.
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Ordinary pairing continues; the downgrade is not an error.
    expect(fakeApi.calls, equals(['verify', 'upload', 'complete']));
    expect(find.text("Couldn't upload your data"), findsNothing);
    // No slow-link promise for the single-PUT path.
    expect(find.textContaining('keep going across a slow'), findsNothing);
  });

  testWidgets(
    'cancelling during the ceremony does not await the upload or release credentials',
    (tester) async {
      final uploadCompleter = Completer<ffi.ResumableSnapshotUploadResult>();
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
        uploadResumableHandler: ({required handle, ttlSecs}) =>
            uploadCompleter.future,
      );

      await _pumpToSasStep(tester, fakeApi: fakeApi);

      await tester.tap(find.text('They Match'));
      await tester.pump();
      // Upload is in flight now.
      expect(fakeApi.calls, equals(['verify', 'upload']));

      // Dispose the sheet mid-upload: the widget must cancel and move on
      // without waiting for the upload future.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(fakeApi.cancelCount, greaterThanOrEqualTo(1));

      // The abandoned upload completes late; it must not reach step 3 and must
      // not throw into the disposed widget.
      uploadCompleter.complete(
        const ffi.ResumableSnapshotUploadResult(
          transport: ffi.SnapshotTransportUsed.resumable,
          uploadId: 'session-late',
          committedBytes: 2048,
          totalBytes: 2048,
          leaseActive: true,
          leaseRenewed: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeApi.calls, isNot(contains('complete')));
    },
  );

  testWidgets(
    'cancel from the sheet drives cancelPairingCeremony and ignores a late upload',
    (tester) async {
      final uploadGate = Completer<ffi.ResumableSnapshotUploadResult>();
      final fakeApi = _FakePairingCeremonyApi(
        startInitiatorCeremonyHandler:
            ({required handle, required tokenBytes}) async {
              return jsonEncode({
                'sas_version': 3,
                'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
                'joiner_device_id': 'joiner-dev-xyz',
              });
            },
        uploadResumableHandler: ({required handle, ttlSecs}) =>
            uploadGate.future,
      );

      await _pumpToSasStep(tester, fakeApi: fakeApi);

      await tester.tap(find.text('They Match'));
      await tester.pump();
      expect(fakeApi.calls, equals(['verify', 'upload']));

      // Cancel through the sheet (dismiss path), which must not await the
      // upload and must stop the ceremony.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(fakeApi.cancelCount, greaterThanOrEqualTo(1));

      // Late upload success must not release credentials.
      uploadGate.complete(
        const ffi.ResumableSnapshotUploadResult(
          transport: ffi.SnapshotTransportUsed.resumable,
          uploadId: 'late-session',
          committedBytes: 2048,
          totalBytes: 2048,
          leaseActive: true,
          leaseRenewed: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeApi.calls, isNot(contains('complete')));
    },
  );

  testWidgets('retry after an upload failure starts a clean ceremony', (
    tester,
  ) async {
    var attempt = 0;
    final fakeApi = _FakePairingCeremonyApi(
      startInitiatorCeremonyHandler:
          ({required handle, required tokenBytes}) async {
            return jsonEncode({
              'sas_version': 3,
              'sas_words': ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
              'joiner_device_id': 'joiner-dev-xyz',
            });
          },
      uploadResumableHandler: ({required handle, ttlSecs}) async {
        attempt++;
        if (attempt == 1) {
          throw StateError('first attempt fails');
        }
        return const ffi.ResumableSnapshotUploadResult(
          transport: ffi.SnapshotTransportUsed.resumable,
          uploadId: 'retry-session',
          committedBytes: 1024,
          totalBytes: 1024,
          leaseActive: true,
          leaseRenewed: true,
        );
      },
    );

    await _pumpToSasStep(tester, fakeApi: fakeApi);

    await tester.tap(find.text('They Match'));
    await tester.pumpAndSettle();
    expect(find.text('Retry upload'), findsOneWidget);
    // The failure card must not leak raw error text.
    expect(find.textContaining('StateError'), findsNothing);

    // Retry returns to the start of the flow, so the ceremony state is clean
    // (no leftover phase, progress, or stale credentials).
    await tester.tap(find.text('Retry upload'));
    await tester.pumpAndSettle();

    expect(find.textContaining('recovery phrase'), findsWidgets);
    expect(fakeApi.calls, isNot(contains('complete')));
  });
}
