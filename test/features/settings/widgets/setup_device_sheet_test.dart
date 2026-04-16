import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:prism_plurality/core/sync/pairing_ceremony_api.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/widgets/setup_device_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePairingCeremonyApi extends PairingCeremonyApi {
  _FakePairingCeremonyApi({this.startInitiatorCeremonyHandler});

  Future<String> Function({
    required ffi.PrismSyncHandle handle,
    required Uint8List tokenBytes,
  })?
  startInitiatorCeremonyHandler;

  @override
  Future<void> validateMnemonic(String mnemonic) => Future.value();

  @override
  Future<String> startJoinerCeremony({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> getJoinerSas({required ffi.PrismSyncHandle handle}) =>
      throw UnimplementedError();

  @override
  Future<String> completeJoinerCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
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
            'sas_words': 'alpha bravo charlie',
            'sas_decimal': '112233',
          }),
        );
  }

  @override
  Future<String> completeInitiatorCeremony({
    required ffi.PrismSyncHandle handle,
    required String password,
    required String mnemonic,
  }) => Future.value('ok');
}

void main() {
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
    final fakeApi = _FakePairingCeremonyApi(
      startInitiatorCeremonyHandler:
          ({required handle, required tokenBytes}) async {
            expect(handle, same(fakeHandle));
            expect(tokenBytes, Uint8List.fromList([1, 2, 3, 4]));
            return jsonEncode({
              'sas_words': 'alpha bravo charlie',
              'sas_decimal': '112233',
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
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
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
    await tester.enterText(
      find.byType(TextField),
      'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about',
    );
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
    expect(find.text('112233'), findsOneWidget);

    await tester.tap(find.text('They Match'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your sync PIN'), findsOneWidget);
    // PIN dot indicators should be present (6 dots)
    expect(find.byType(AnimatedContainer), findsWidgets);
  });
}
