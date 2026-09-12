import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync/generated/frb_generated.dart';

import 'package:prism_plurality/core/services/pin_lock_service.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/features/settings/widgets/sync_rewrap_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

class _FixedHandleNotifier extends PrismSyncHandleNotifier {
  _FixedHandleNotifier(this.handle);

  final ffi.PrismSyncHandle handle;

  @override
  Future<ffi.PrismSyncHandle?> build() async => handle;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const pin = '123456';
  const wrappedDekKey = 'prism_sync.wrapped_dek';
  const syncIdKey = 'prism_sync.sync_id';
  const deviceIdKey = 'prism_sync.device_id';
  const deviceSecretKey = 'prism_sync.device_secret';
  final skipNonIos = !Platform.isIOS;

  Future<void> clearTestCredentials() async {
    final all = await safeSecureReadAll();
    await wipeSyncKeychainNamespace(
      readAll: () async => all.entries,
      deleteKey: (key) async {
        await safeSecureDelete(key);
      },
    );
    await PinLockService().clearPin();
    syncCredentialsPersisted.value = false;
    SecureStorageFaultInjector.disableForTesting();
    SyncRewrapSheet.debugGenerateSecretKeyOverride = null;
  }

  setUpAll(() async {
    if (skipNonIos) return;
    await RustLib.init();
  });

  tearDownAll(() {
    if (!skipNonIos) RustLib.dispose();
  });

  tearDown(() async {
    if (!skipNonIos) await clearTestCredentials();
  });

  testWidgets(
    'real iOS keychain loss opens recovery and a new phrase rewraps the same DEK',
    (tester) async {
      await clearTestCredentials();

      final tempDirectory = await Directory.systemTemp.createTemp(
        'prism-rewrap-ios-',
      );
      final syncDbPath = '${tempDirectory.path}/prism_sync.db';
      final syncDatabaseKey = Uint8List.fromList(
        List<int>.generate(32, (index) => 255 - index),
      );
      final handle = await ffi.createPrismSync(
        relayUrl: 'https://relay.example.com',
        dbPath: syncDbPath,
        allowInsecure: false,
        schemaJson: '',
        databaseKey: syncDatabaseKey,
      );
      ProviderContainer? container;
      var handleDisposed = false;
      try {
        final originalMnemonic = await ffi.generateSecretKey();
        final originalSecret = await ffi.mnemonicToBytes(
          mnemonic: Uint8List.fromList(utf8.encode(originalMnemonic)),
        );
        await ffi.initialize(
          handle: handle,
          password: utf8.encode(pin),
          secretKey: originalSecret,
        );
        await ffi.seedSecureStore(
          handle: handle,
          entries: {
            'sync_id': Uint8List.fromList(utf8.encode('sim-sync-id')),
            'device_id': Uint8List.fromList(utf8.encode('sim-device-id')),
            'device_secret': Uint8List.fromList(
              List<int>.generate(32, (index) => index + 1),
            ),
            'relay_url': Uint8List.fromList(
              utf8.encode('https://relay.example.com'),
            ),
            'session_token': Uint8List.fromList(
              utf8.encode('sim-session-token'),
            ),
          },
        );

        final dekBefore = await ffi.databaseKey(handle: handle);
        final rustStoreBefore = await ffi.drainSecureStore(handle: handle);
        await drainRustStore(handle);
        expect(
          await PinLockService().isPinSet(),
          isFalse,
          reason: 'sync recovery must not require the optional app-lock PIN',
        );

        final originalWrappedRead = await safeSecureRead(wrappedDekKey);
        expect(originalWrappedRead.ok, isTrue);
        expect(originalWrappedRead.value, isNotEmpty);
        final originalWrapped = originalWrappedRead.value!;

        // Reproduce the pre-fix partial-seed deletion.
        final oldPartialHandle = await ffi.createPrismSync(
          relayUrl: 'https://relay.example.com',
          dbPath: ':memory:',
          allowInsecure: false,
          schemaJson: '',
        );
        try {
          final keychainSnapshot = await safeSecureReadAll();
          expect(keychainSnapshot.ok, isTrue);
          final partialEntries = buildSeedEntries(keychainSnapshot.entries)!;
          partialEntries.remove('wrapped_dek');
          await ffi.seedSecureStore(
            handle: oldPartialHandle,
            entries: partialEntries,
          );
          await drainRustStore(oldPartialHandle);
          expect(
            (await safeSecureRead(wrappedDekKey)).value,
            isNull,
            reason: 'reproduces the pre-fix partial-seed deletion',
          );
        } finally {
          oldPartialHandle.dispose();
        }
        await safeSecureWrite(wrappedDekKey, originalWrapped);

        // The fixed path defers until a complete seed is available.
        final keychainBeforeDeferredSeed = (await safeSecureReadAll()).entries;
        final fixedFallbackHandle = await ffi.createPrismSync(
          relayUrl: 'https://relay.example.com',
          dbPath: ':memory:',
          allowInsecure: false,
          schemaJson: '',
        );
        try {
          SecureStorageFaultInjector.enableForTesting();
          SecureStorageFaultInjector.queueNext(
            operation: SecureStorageFaultOperation.readAll,
            failure: SecureStorageFailure.transient,
          );
          SecureStorageFaultInjector.queueNext(
            operation: SecureStorageFaultOperation.read,
            failure: SecureStorageFailure.transient,
            key: wrappedDekKey,
          );
          expect(await seedRustStoreFromKeychain(fixedFallbackHandle), isFalse);
          expect(syncCredentialsPersisted.value, isFalse);
          expect(
            await ffi.drainSecureStore(handle: fixedFallbackHandle),
            isEmpty,
          );

          // A complete retry must preserve the Keychain snapshot.
          SecureStorageFaultInjector.disableForTesting();
          expect(await seedRustStoreFromKeychain(fixedFallbackHandle), isTrue);
          expect(
            syncCredentialsPersisted.value,
            isTrue,
            reason: 'a complete retry must restore durable outbox capture',
          );
          final seededAfterRetry = await ffi.drainSecureStore(
            handle: fixedFallbackHandle,
          );
          expect(
            seededAfterRetry['wrapped_dek'],
            orderedEquals(base64Decode(originalWrapped)),
          );
          await drainRustStore(fixedFallbackHandle);
          expect(
            (await safeSecureReadAll()).entries,
            keychainBeforeDeferredSeed,
          );
        } finally {
          SecureStorageFaultInjector.disableForTesting();
          fixedFallbackHandle.dispose();
        }
        expect((await safeSecureRead(wrappedDekKey)).value, originalWrapped);

        expect(
          classifyHealthFromKeychain(
            syncId: (await safeSecureRead(syncIdKey)).value,
            deviceId: (await safeSecureRead(deviceIdKey)).value,
            deviceSecret: (await safeSecureRead(deviceSecretKey)).value,
          ),
          isNull,
          reason: 'the simulated phone has a complete persisted sync identity',
        );
        expect(await ffi.isUnlocked(handle: handle), isTrue);

        await safeSecureDelete(wrappedDekKey);
        final missingRead = await safeSecureRead(wrappedDekKey);
        expect(missingRead.ok, isTrue);
        expect(missingRead.value, isNull);
        expect(
          classifyPairReadinessFromWrappedDekRead(missingRead),
          SyncHealthState.needsRewrap,
        );

        // A read failure is not evidence that the wrapper is missing.
        await safeSecureWrite(wrappedDekKey, originalWrapped);
        SecureStorageFaultInjector.enableForTesting();
        SecureStorageFaultInjector.queueNext(
          operation: SecureStorageFaultOperation.read,
          failure: SecureStorageFailure.transient,
          key: wrappedDekKey,
        );
        final failedRead = await safeSecureRead(wrappedDekKey);
        expect(failedRead.ok, isFalse);
        expect(
          classifyPairReadinessFromWrappedDek(failedRead.value),
          SyncHealthState.needsRewrap,
          reason: 'documents the old null-collapsing false positive',
        );
        expect(
          classifyPairReadinessFromWrappedDekRead(failedRead),
          SyncHealthState.healthy,
        );
        SecureStorageFaultInjector.disableForTesting();

        await safeSecureDelete(wrappedDekKey);

        container = ProviderContainer(
          overrides: [
            prismSyncHandleProvider.overrideWith(
              () => _FixedHandleNotifier(handle),
            ),
          ],
        );
        await container.read(prismSyncHandleProvider.future);
        container
            .read(syncHealthProvider.notifier)
            .setState(SyncHealthState.needsRewrap);

        final healthNotifier = container.read(syncHealthProvider.notifier);
        final missingWrapperSnapshot = (await safeSecureReadAll()).entries;
        final failedReplacementMnemonic = await ffi.generateSecretKey();

        expect(
          await healthNotifier.attemptRewrap(
            pin: pin,
            mnemonic: 'not a valid recovery phrase',
          ),
          isFalse,
        );
        expect((await safeSecureReadAll()).entries, missingWrapperSnapshot);

        // A failed mirror write must restore the prior snapshot.
        SecureStorageFaultInjector.enableForTesting();
        SecureStorageFaultInjector.queueNext(
          operation: SecureStorageFaultOperation.write,
          failure: SecureStorageFailure.transient,
          key: wrappedDekKey,
        );
        expect(
          await healthNotifier.attemptRewrap(
            pin: pin,
            mnemonic: failedReplacementMnemonic,
          ),
          isFalse,
        );
        SecureStorageFaultInjector.disableForTesting();
        expect((await safeSecureReadAll()).entries, missingWrapperSnapshot);
        expect((await safeSecureRead(wrappedDekKey)).value, isNull);
        expect(container.read(syncHealthProvider), SyncHealthState.needsRewrap);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const SyncRewrapSheet(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Restore your pairing key'), findsOneWidget);

        final lostPhraseButton = find.text('Lost your phrase?');
        await tester.ensureVisible(lostPhraseButton);
        await tester.tap(lostPhraseButton);
        await tester.pumpAndSettle();

        final numberedWords = tester
            .widgetList<Text>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    RegExp(r'^\d+\. ').hasMatch(widget.data ?? ''),
              ),
            )
            .map((text) => text.data!)
            .toList();
        expect(numberedWords, hasLength(12));
        final replacementMnemonic = numberedWords
            .map((label) => label.substring(label.indexOf(' ') + 1))
            .join(' ');
        expect(replacementMnemonic, isNot(originalMnemonic));

        final showQr = find.text('Show QR Code');
        await tester.ensureVisible(showQr);
        await tester.tap(showQr);
        await tester.pumpAndSettle();
        final savedCheckbox = find.text('I have saved my Secret Key');
        await tester.ensureVisible(savedCheckbox);
        await tester.tap(savedCheckbox);
        await tester.pumpAndSettle();
        final continueButton = find.widgetWithText(PrismButton, 'Continue');
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();

        for (final digit in pin.split('')) {
          await tester.tap(find.text(digit).first);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.text('Confirm PIN'), findsOneWidget);
        expect(find.byType(SyncRewrapSheet), findsOneWidget);
        expect(container.read(syncHealthProvider), SyncHealthState.needsRewrap);

        for (final digit in pin.split('')) {
          await tester.tap(find.text(digit).first);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.byType(SyncRewrapSheet), findsNothing);
        expect(container.read(syncHealthProvider), SyncHealthState.healthy);
        final newWrappedRead = await safeSecureRead(wrappedDekKey);
        expect(newWrappedRead.ok, isTrue);
        expect(newWrappedRead.value, isNotEmpty);
        expect(newWrappedRead.value, isNot(originalWrapped));

        final dekAfter = await ffi.databaseKey(handle: handle);
        expect(dekAfter, orderedEquals(dekBefore));
        final rustStoreAfter = await ffi.drainSecureStore(handle: handle);
        expect(
          rustStoreAfter['device_id'],
          orderedEquals(rustStoreBefore['device_id']!),
        );
        expect(
          rustStoreAfter['device_secret'],
          orderedEquals(rustStoreBefore['device_secret']!),
        );
        expect(
          rustStoreAfter['wrapped_dek'],
          isNot(orderedEquals(rustStoreBefore['wrapped_dek']!)),
        );

        await ffi.lock(handle: handle);
        final replacementSecret = await ffi.mnemonicToBytes(
          mnemonic: Uint8List.fromList(utf8.encode(replacementMnemonic)),
        );
        await ffi.unlock(
          handle: handle,
          password: utf8.encode(pin),
          secretKey: replacementSecret,
        );
        expect(await ffi.isUnlocked(handle: handle), isTrue);
        expect(
          await ffi.databaseKey(handle: handle),
          orderedEquals(dekBefore),
          reason: 'the replacement phrase unlocks the original DEK',
        );

        // Existing devices retain their local wrapper.
        final oldDeviceHandle = await ffi.createPrismSync(
          relayUrl: 'https://relay.example.com',
          dbPath: ':memory:',
          allowInsecure: false,
          schemaJson: '',
        );
        try {
          await ffi.seedSecureStore(
            handle: oldDeviceHandle,
            entries: rustStoreBefore,
          );
          await ffi.unlock(
            handle: oldDeviceHandle,
            password: utf8.encode(pin),
            secretKey: originalSecret,
          );
          expect(await ffi.isUnlocked(handle: oldDeviceHandle), isTrue);
          expect(
            await ffi.databaseKey(handle: oldDeviceHandle),
            orderedEquals(dekBefore),
            reason: 'the other device keeps its old phrase and shared DEK',
          );
        } finally {
          oldDeviceHandle.dispose();
        }

        // Verify the replacement survives a cold handle reopen.
        container.dispose();
        container = null;
        handle.dispose();
        handleDisposed = true;
        final reopenedHandle = await ffi.createPrismSync(
          relayUrl: 'https://relay.example.com',
          dbPath: syncDbPath,
          allowInsecure: false,
          schemaJson: '',
          databaseKey: syncDatabaseKey,
        );
        try {
          expect(await seedRustStoreFromKeychain(reopenedHandle), isTrue);
          await ffi.unlock(
            handle: reopenedHandle,
            password: utf8.encode(pin),
            secretKey: replacementSecret,
          );
          expect(await ffi.isUnlocked(handle: reopenedHandle), isTrue);
          expect(
            await ffi.databaseKey(handle: reopenedHandle),
            orderedEquals(dekBefore),
            reason: 'the replacement phrase survives a cold handle reopen',
          );
        } finally {
          reopenedHandle.dispose();
        }
      } finally {
        container?.dispose();
        if (!handleDisposed) handle.dispose();
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      }
    },
    skip: skipNonIos,
  );
}
