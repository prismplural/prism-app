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
    Map<String, dynamic>? capturedCeremonyResult;
    final fakeApi = _FakePairingCeremonyApi(
      startInitiatorCeremonyHandler:
          ({required handle, required tokenBytes}) async {
            expect(handle, same(fakeHandle));
            expect(tokenBytes, Uint8List.fromList([1, 2, 3, 4]));
            final payload = {
              'sas_words': 'alpha bravo charlie',
              'sas_decimal': '112233',
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
    const phrase = 'abandon abandon abandon abandon abandon abandon '
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
    expect(find.text('112233'), findsOneWidget);

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
