import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:prism_plurality/core/constants/app_constants.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/reset/full_reset_service.dart';
import 'package:prism_plurality/core/reset/native_reset_keys.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugForceMacSecureStorageEntitlementFallback = false;
    debugTreatFreshInstallSecureClearAsMacOS = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall methodCall) async => null,
        );
  });

  tearDown(() {
    debugForceMacSecureStorageEntitlementFallback = false;
    debugTreatFreshInstallSecureClearAsMacOS = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  test(
    'fresh install guard enters recovery when app files exist without sentinel',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-guard-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final mediaDir = Directory(p.join(tempDir.path, 'prism_media'));
      await mediaDir.create(recursive: true);
      await File(
        p.join(mediaDir.path, 'media.enc'),
      ).writeAsString('ciphertext');
      await File(p.join(tempDir.path, 'prism.db')).writeAsString('db');
      await File(
        p.join(tempDir.path, AppConstants.syncDatabaseName),
      ).writeAsString('sync-db');

      SharedPreferences.setMockInitialValues({
        'prism.cache.theme_style': 'dreamy',
        'pk.auto_poll_enabled': true,
      });

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret'
        ..values['prism_pluralkit_token'] = 'pk-token';
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async => mediaDir,
        clearMediaCache: () async {
          if (await mediaDir.exists()) {
            await mediaDir.delete(recursive: true);
          }
        },
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.freshInstallRecoveryRequired);
      expect(decision.report.hasAppContainerResidue, isTrue);
      expect(await File(p.join(tempDir.path, 'prism.db')).exists(), isTrue);
      expect(
        await File(
          p.join(tempDir.path, AppConstants.syncDatabaseName),
        ).exists(),
        isTrue,
      );
      expect(await mediaDir.exists(), isTrue);
      expect(secureStore.values, isNotEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isTrue);
    },
  );

  test(
    'fresh install guard marks a clean fresh install after secure cleanup',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-fresh-secure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final secureStore = _FakeFullResetSecureStore();
      final nativeKeys = _FakeNativeResetKeys();
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.normal);
      expect(secureStore.deleteAllCalls, 1);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isNull);
    },
  );

  test(
    'fresh install guard tolerates macOS errSecParam cleanup on empty install',
    () async {
      debugTreatFreshInstallSecureClearAsMacOS = true;
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-fresh-mac-deleteall-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final secureStore = _FakeFullResetSecureStore()
        ..deleteAllError = StateError(
          'secure store deleteAll failed '
          '(failure=SecureStorageFailure.unknown, '
          'code=Unexpected security result code, message=Code: -50, '
          'Message: One or more parameters passed to a function were not valid.)',
        );
      final nativeKeys = _FakeNativeResetKeys();
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.normal);
      expect(secureStore.deleteAllCalls, 1);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isNull);
    },
  );

  test('fresh install guard clears native keys before FSS cleanup', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'prism-fresh-cleanup-order-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final order = <String>[];
    final secureStore = _FakeFullResetSecureStore()
      ..onDeleteAll = () => order.add('secure');
    final nativeKeys = _FakeNativeResetKeys()
      ..onDeleteKnownKeys = () => order.add('native');
    final service = FullResetService(
      secureStore: secureStore,
      nativeResetKeys: nativeKeys,
      appDataDirectory: () async => tempDir,
      temporaryDirectory: () async => tempDir,
      mediaCacheDirectory: () async => Directory(p.join(tempDir.path, 'none')),
    );

    final decision = await service.runFreshInstallResidueGuard();

    expect(decision.mode, ResetStartupMode.normal);
    expect(order, ['native', 'secure']);
  });

  test('fresh install guard clears FSS-only residue and continues', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'prism-fresh-fss-only-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final secureStore = _FakeFullResetSecureStore()
      ..values['prism_sync.database_key'] = 'secret';
    final nativeKeys = _FakeNativeResetKeys();
    final service = FullResetService(
      secureStore: secureStore,
      nativeResetKeys: nativeKeys,
      appDataDirectory: () async => tempDir,
      temporaryDirectory: () async => tempDir,
      mediaCacheDirectory: () async => Directory(p.join(tempDir.path, 'none')),
    );

    final decision = await service.runFreshInstallResidueGuard();

    expect(decision.mode, ResetStartupMode.normal);
    expect(decision.report.hasResidue, isFalse);
    expect(secureStore.deleteAllCalls, 1);
    expect(secureStore.values, isEmpty);
    expect(nativeKeys.deleteKnownKeysCalls, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
    expect(prefs.getBool(kFreshInstallAnomalyKey), isNull);
  });

  test(
    'fresh install guard ignores empty native-created media directory',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-empty-media-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final mediaDir = Directory(p.join(tempDir.path, 'prism_media'));
      await mediaDir.create(recursive: true);

      final secureStore = _FakeFullResetSecureStore();
      final nativeKeys = _FakeNativeResetKeys();
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async => mediaDir,
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.normal);
      expect(decision.report.files, isEmpty);
      expect(secureStore.deleteAllCalls, 1);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isNull);
    },
  );

  test(
    'fresh install guard enters recovery when media directory has data',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-media-residue-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final mediaDir = Directory(p.join(tempDir.path, 'prism_media'));
      await mediaDir.create(recursive: true);
      await File(
        p.join(mediaDir.path, 'media.enc'),
      ).writeAsString('ciphertext');

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async => mediaDir,
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.freshInstallRecoveryRequired);
      expect(decision.report.files, contains(mediaDir.path));
      expect(secureStore.values, isNotEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isTrue);
    },
  );

  test(
    'fresh install guard clears secure-only residue and continues',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-fresh-native-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.normal);
      expect(decision.report.hasSecureResidue, isTrue);
      expect(secureStore.deleteAllCalls, 1);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);
      expect(nativeKeys.hasKeys, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isNull);
      expect(prefs.getBool(kNativeResetKeyClearPendingKey), isNull);
    },
  );

  test(
    'fresh install guard enters recovery if secure-only cleanup fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-fresh-native-delete-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()
        ..hasKeys = true
        ..throwOnDeleteKnownKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.freshInstallRecoveryRequired);
      expect(secureStore.deleteAllCalls, 0);
      expect(secureStore.values, isNotEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isTrue);
      expect(prefs.getBool(kNativeResetKeyClearPendingKey), isTrue);
    },
  );

  test(
    'fresh install guard enters recovery if classified secure cleanup fails',
    () async {
      SecureStorageFaultInjector.enableForTesting();
      addTearDown(SecureStorageFaultInjector.disableForTesting);
      SecureStorageFaultInjector.queueNext(
        operation: SecureStorageFaultOperation.deleteAll,
        failure: SecureStorageFailure.cipher,
      );

      final tempDir = await Directory.systemTemp.createTemp(
        'prism-fresh-secure-delete-result-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: const PlatformFullResetSecureStore(),
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      final decision = await service.runFreshInstallResidueGuard();

      expect(decision.mode, ResetStartupMode.freshInstallRecoveryRequired);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isTrue);
    },
  );

  test(
    'anomaly continue probe rejects existing database when key is missing',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-anomaly-continue-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await File(p.join(tempDir.path, 'prism.db')).writeAsString('db');
      final service = FullResetService(
        secureStore: _FakeFullResetSecureStore(),
        nativeResetKeys: _FakeNativeResetKeys(),
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      expect(await service.canContinueWithExistingDataAfterAnomaly(), isFalse);
    },
  );

  test(
    'anomaly continue probe allows continue when no app database exists',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-anomaly-empty-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final service = FullResetService(
        secureStore: _FakeFullResetSecureStore(),
        nativeResetKeys: _FakeNativeResetKeys(),
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      expect(await service.canContinueWithExistingDataAfterAnomaly(), isTrue);
    },
  );

  test(
    'anomaly continue probe rejects openable sync database without app database',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-anomaly-sync-residue-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      const syncKey =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'read' &&
                  methodCall.arguments['key'] == kSyncDatabaseKeyStorageKey) {
                return syncKey;
              }
              return null;
            },
          );

      final syncDbPath = p.join(tempDir.path, AppConstants.syncDatabaseName);
      final syncDb = raw.sqlite3.open(syncDbPath);
      syncDb
        ..execute("PRAGMA key = \"x'$syncKey'\";")
        ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY);')
        ..close();
      final service = FullResetService(
        secureStore: _FakeFullResetSecureStore(),
        nativeResetKeys: _FakeNativeResetKeys(),
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      expect(await service.canContinueWithExistingDataAfterAnomaly(), isFalse);
    },
  );

  test(
    'anomaly continue probe rejects orphaned sync database sidecar residue',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-anomaly-sync-sidecar-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await File(
        p.join(tempDir.path, '${AppConstants.syncDatabaseName}-wal'),
      ).writeAsString('sync-wal');
      final service = FullResetService(
        secureStore: _FakeFullResetSecureStore(),
        nativeResetKeys: _FakeNativeResetKeys(),
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      expect(await service.canContinueWithExistingDataAfterAnomaly(), isFalse);
    },
  );

  test('wipeLocalData writes restart-required bookkeeping', () async {
    final tempDir = await Directory.systemTemp.createTemp('prism-reset-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File(p.join(tempDir.path, 'prism.db')).writeAsString('db');
    await File(
      p.join(tempDir.path, 'crypto_boot_log.json'),
    ).writeAsString('log');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('prism.pref.screen_privacy_enabled', true);
    await prefs.setString('prism.cache.theme_style', 'dreamy');
    await prefs.setBool('pk.auto_poll_enabled', true);

    final secureStore = _FakeFullResetSecureStore()
      ..values['prism_sync.database_key'] = 'secret';
    final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
    final service = FullResetService(
      secureStore: secureStore,
      nativeResetKeys: nativeKeys,
      appDataDirectory: () async => tempDir,
      temporaryDirectory: () async => tempDir,
      mediaCacheDirectory: () async => Directory(p.join(tempDir.path, 'none')),
      clearMediaCache: () async {},
    );

    await service.wipeLocalData();

    expect(await File(p.join(tempDir.path, 'prism.db')).exists(), isFalse);
    expect(
      await File(p.join(tempDir.path, 'crypto_boot_log.json')).exists(),
      isFalse,
    );
    expect(secureStore.values, isEmpty);
    expect(nativeKeys.deleteKnownKeysCalls, 1);

    expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
    expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
    expect(prefs.getString(kFullResetCompletedAtKey), isNotNull);
    expect(prefs.getBool('prism.pref.screen_privacy_enabled'), isTrue);
    expect(prefs.getString('prism.cache.theme_style'), 'dreamy');
    expect(prefs.getBool('pk.auto_poll_enabled'), isNull);
  });

  test(
    'wipeLocalData completes when macOS primary keychain delete lacks entitlement',
    () async {
      debugForceMacSecureStorageEntitlementFallback = true;
      final platformSecureStore = _FakePlatformSecureStorage()
        ..store.addAll({
          kDatabaseKeyStorageKey: 'database-key',
          '${kDatabaseKeyStorageKey}_staging': 'database-staging-key',
          kSyncDatabaseKeyStorageKey: 'sync-key',
          '${kSyncDatabaseKeyStorageKey}_staging': 'sync-staging-key',
          'unrelated_secure_key': 'also-cleared',
        })
        ..throwOnPrimarySecureStorage = _macMissingEntitlementException();
      platformSecureStore.install();
      addTearDown(platformSecureStore.uninstall);

      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-mac-entitlement-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await File(p.join(tempDir.path, 'prism.db')).writeAsString('db');
      await File(
        p.join(tempDir.path, AppConstants.syncDatabaseName),
      ).writeAsString('sync-db');
      await File(
        p.join(tempDir.path, 'crypto_boot_log.json'),
      ).writeAsString('log');

      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: const PlatformFullResetSecureStore(),
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
      );

      await service.wipeLocalData();

      expect(platformSecureStore.primaryFailureCalls, greaterThan(0));
      expect(
        platformSecureStore.legacyReadAllCalls,
        greaterThan(0),
        reason: 'deleteAll should sweep legacy keychain entries after -34018',
      );
      expect(platformSecureStore.store, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);
      expect(nativeKeys.hasKeys, isFalse);
      expect(await File(p.join(tempDir.path, 'prism.db')).exists(), isFalse);
      expect(
        await File(
          p.join(tempDir.path, AppConstants.syncDatabaseName),
        ).exists(),
        isFalse,
      );
      expect(
        await File(p.join(tempDir.path, 'crypto_boot_log.json')).exists(),
        isFalse,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
      expect(prefs.getString(kFullResetCompletedAtKey), isNotNull);
    },
  );

  test(
    'wipeLocalData completes when macOS primary keychain delete returns errSecParam',
    () async {
      debugForceMacSecureStorageEntitlementFallback = true;
      final platformSecureStore = _FakePlatformSecureStorage()
        ..store.addAll({
          kDatabaseKeyStorageKey: 'database-key',
          '${kDatabaseKeyStorageKey}_staging': 'database-staging-key',
          kSyncDatabaseKeyStorageKey: 'sync-key',
          '${kSyncDatabaseKeyStorageKey}_staging': 'sync-staging-key',
          'unrelated_secure_key': 'also-cleared',
        })
        ..throwOnPrimarySecureStorage = _macInvalidParameterException();
      platformSecureStore.install();
      addTearDown(platformSecureStore.uninstall);

      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-mac-errsecparam-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await File(p.join(tempDir.path, 'prism.db')).writeAsString('db');
      await File(
        p.join(tempDir.path, AppConstants.syncDatabaseName),
      ).writeAsString('sync-db');

      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: const PlatformFullResetSecureStore(),
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
      );

      await service.wipeLocalData();

      expect(platformSecureStore.primaryFailureCalls, greaterThan(0));
      expect(
        platformSecureStore.legacyReadAllCalls,
        greaterThan(0),
        reason: 'deleteAll should sweep legacy keychain entries after -50',
      );
      expect(platformSecureStore.store, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);
      expect(nativeKeys.hasKeys, isFalse);
      expect(await File(p.join(tempDir.path, 'prism.db')).exists(), isFalse);
      expect(
        await File(
          p.join(tempDir.path, AppConstants.syncDatabaseName),
        ).exists(),
        isFalse,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
      expect(prefs.getString(kFullResetCompletedAtKey), isNotNull);
    },
  );

  test(
    'wipeLocalData preserves sync disconnect marker for pairing handoff',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-marker-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final writtenMarker = await const SyncDisconnectMarkerStore()
          .writeInitial(
            reason: SyncDisconnectReason.replaceByPairing,
            previousSyncId: 'sync-abc',
            previousDeviceId: 'device-abc',
            localAppDataOutcome: LocalAppDataOutcome.wiped,
            nextSetupConstraint: SyncSetupConstraint.joinOnlyReplaceLocalData,
          );
      final service = FullResetService(
        secureStore: _FakeFullResetSecureStore(),
        nativeResetKeys: _FakeNativeResetKeys(),
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
      );

      await service.wipeLocalData(requireRestart: false);

      final marker = await const SyncDisconnectMarkerStore()
          .readForCurrentInstall();
      expect(marker, isNotNull);
      expect(marker!.markerId, writtenMarker.markerId);
      expect(marker.deviceInstallId, writtenMarker.deviceInstallId);
      expect(
        marker.nextSetupConstraint,
        SyncSetupConstraint.joinOnlyReplaceLocalData,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);
    },
  );

  test('fresh install guard ignores sync disconnect marker residue', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'prism-marker-residue-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await const SyncDisconnectMarkerStore().writeInitial(
      reason: SyncDisconnectReason.replaceByPairing,
      previousSyncId: 'sync-abc',
      localAppDataOutcome: LocalAppDataOutcome.wiped,
      nextSetupConstraint: SyncSetupConstraint.joinOnlyReplaceLocalData,
    );
    final service = FullResetService(
      secureStore: _FakeFullResetSecureStore(),
      nativeResetKeys: _FakeNativeResetKeys(),
      appDataDirectory: () async => tempDir,
      temporaryDirectory: () async => tempDir,
      mediaCacheDirectory: () async => Directory(p.join(tempDir.path, 'none')),
      clearMediaCache: () async {},
    );

    final decision = await service.runFreshInstallResidueGuard();

    expect(decision.mode, ResetStartupMode.normal);
    expect(decision.report.preferenceKeys, isEmpty);
    expect(
      await const SyncDisconnectMarkerStore().readForCurrentInstall(),
      isNotNull,
    );
  });

  test(
    'startAndroidClearApplicationData asks Android before clearing native keys',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-android-clear-accepted-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: _FakeFullResetSecureStore(),
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
      );

      final result = await service.startAndroidClearApplicationData();

      expect(result, AndroidApplicationDataClearResult.osAccepted);
      expect(nativeKeys.clearApplicationUserDataCalls, 1);
      expect(nativeKeys.deleteKnownKeysCalls, 0);
      expect(nativeKeys.hasKeys, isTrue);
    },
  );

  test(
    'startAndroidClearApplicationData fallback deletes databases before native keys',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-android-clear-fallback-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final appDb = File(p.join(tempDir.path, 'prism.db'));
      final syncDb = File(p.join(tempDir.path, AppConstants.syncDatabaseName));
      await appDb.writeAsString('db');
      await syncDb.writeAsString('sync-db');

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()
        ..hasKeys = true
        ..clearApplicationUserDataResult = false
        ..onDeleteKnownKeys = () {
          expect(appDb.existsSync(), isFalse);
          expect(syncDb.existsSync(), isFalse);
        };
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
      );

      final result = await service.startAndroidClearApplicationData();

      expect(result, AndroidApplicationDataClearResult.manualFallbackCompleted);
      expect(nativeKeys.clearApplicationUserDataCalls, 1);
      expect(nativeKeys.deleteKnownKeysCalls, 1);
      expect(secureStore.values, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
    },
  );

  test(
    'fresh install guard clears restart-required flag on next launch',
    () async {
      SharedPreferences.setMockInitialValues({
        kFreshInstallSentinelKey: true,
        kFullResetRestartRequiredKey: true,
        kFullResetCompletedAtKey: '2026-05-16T00:00:00.000Z',
      });

      final service = FullResetService(
        appDataDirectory: () async => Directory.systemTemp,
        temporaryDirectory: () async => Directory.systemTemp,
        mediaCacheDirectory: () async => Directory.systemTemp,
        clearMediaCache: () async {},
      );

      final firstDecision = await service.runFreshInstallResidueGuard();
      final secondDecision = await service.runFreshInstallResidueGuard();

      expect(firstDecision.mode, ResetStartupMode.normal);
      expect(secondDecision.mode, ResetStartupMode.normal);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);
      expect(prefs.getString(kFullResetCompletedAtKey), isNull);
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
    },
  );

  test(
    'wipeLocalData preserves secure state when database delete fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-db-delete-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = p.join(tempDir.path, 'prism.db');
      await File(dbPath).writeAsString('db');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('prism.pref.screen_privacy_enabled', true);

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
        fileObserver: (path) {
          if (path == dbPath) {
            throw FileSystemException('simulated delete failure', path);
          }
        },
      );

      await expectLater(
        service.wipeLocalData(),
        throwsA(isA<FullResetFailure>()),
      );

      expect(await File(dbPath).exists(), isTrue);
      expect(secureStore.values, isNotEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 0);

      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);
      expect(prefs.getBool('prism.pref.screen_privacy_enabled'), isTrue);
    },
  );

  test(
    'wipeLocalData keeps clearing keys when a non-database file delete fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-nondb-delete-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = p.join(tempDir.path, 'prism.db');
      final logPath = p.join(tempDir.path, 'crypto_boot_log.json');
      await File(dbPath).writeAsString('db');
      await File(logPath).writeAsString('log');

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
        fileObserver: (path) {
          if (path == logPath) {
            throw FileSystemException('simulated delete failure', path);
          }
        },
      );

      await expectLater(
        service.wipeLocalData(),
        throwsA(isA<FullResetFailure>()),
      );

      expect(await File(dbPath).exists(), isFalse);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);
    },
  );

  test(
    'wipeLocalData does not arm normal startup when secure store clear fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-secure-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = p.join(tempDir.path, 'prism.db');
      await File(dbPath).writeAsString('db');

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret'
        ..throwOnDeleteAll = true;
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
      );

      await expectLater(
        service.wipeLocalData(),
        throwsA(isA<FullResetFailure>()),
      );

      expect(await File(dbPath).exists(), isFalse);
      expect(secureStore.values, isNotEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);

      final decision = await service.runFreshInstallResidueGuard();
      expect(decision.mode, ResetStartupMode.freshInstallRecoveryRequired);
    },
  );

  test(
    'wipeLocalData arms startup and marks native key cleanup pending when native clear fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-native-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = p.join(tempDir.path, 'prism.db');
      await File(dbPath).writeAsString('db');

      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()
        ..hasKeys = true
        ..throwOnDeleteKnownKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
      );

      await service.wipeLocalData();

      expect(await File(dbPath).exists(), isFalse);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isTrue);
      expect(prefs.getBool(kNativeResetKeyClearPendingKey), isTrue);

      nativeKeys.throwOnDeleteKnownKeys = false;
      final decision = await service.runFreshInstallResidueGuard();
      expect(decision.mode, ResetStartupMode.normal);
      expect(nativeKeys.deleteKnownKeysCalls, 2);
      expect(prefs.getBool(kNativeResetKeyClearPendingKey), isNull);
    },
  );

  test(
    'wipeLocalData records temp traversal failures instead of throwing raw',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-reset-temp-list-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dbPath = p.join(tempDir.path, 'prism.db');
      await File(dbPath).writeAsString('db');
      final secureStore = _FakeFullResetSecureStore()
        ..values['prism_sync.database_key'] = 'secret';
      final nativeKeys = _FakeNativeResetKeys()..hasKeys = true;
      final service = FullResetService(
        secureStore: secureStore,
        nativeResetKeys: nativeKeys,
        appDataDirectory: () async => tempDir,
        temporaryDirectory: () async => tempDir,
        mediaCacheDirectory: () async =>
            Directory(p.join(tempDir.path, 'none')),
        clearMediaCache: () async {},
        directoryLister: (_) {
          throw const FileSystemException('simulated temp traversal failure');
        },
      );

      await expectLater(
        service.wipeLocalData(),
        throwsA(
          isA<FullResetFailure>().having(
            (failure) => failure.failures.join('\n'),
            'failures',
            contains('temporary file discovery'),
          ),
        ),
      );

      expect(await File(dbPath).exists(), isFalse);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isNull);
      expect(prefs.getBool(kFullResetRestartRequiredKey), isNull);
    },
  );

  group('ResetStartupDecision', () {
    test('default normal constructor preserves existing semantics', () {
      const decision = ResetStartupDecision.normal();
      expect(decision.mode, ResetStartupMode.normal);
      expect(decision.diagnostic, isNull);
      expect(decision.report.hasResidue, isFalse);
    });

    test('keychainUnreadable mode is reachable and carries the diagnostic', () {
      final diag = SecureStorageDiagnostic(
        recoveredVia: null,
        slotOutcomes: const <String, String>{'primary': 'cipher'},
      );
      final decision = ResetStartupDecision.keychainUnreadable(
        diagnostic: diag,
      );
      expect(decision.mode, ResetStartupMode.keychainUnreadable);
      expect(decision.diagnostic, same(diag));
      expect(decision.report.hasResidue, isFalse);
    });

    test('all ResetStartupMode values can be switched exhaustively', () {
      // Compile-time check that downstream switches are exhaustive over the
      // new enum variant. Failing here means a downstream switch missed it.
      for (final mode in ResetStartupMode.values) {
        switch (mode) {
          case ResetStartupMode.normal:
          case ResetStartupMode.freshInstallRecoveryRequired:
          case ResetStartupMode.keychainUnreadable:
            // Exhaustive — no fallthrough needed.
            break;
        }
      }
      expect(ResetStartupMode.values.length, 3);
    });
  });

  test('fresh install guard reports recovery instead of throwing', () async {
    final service = FullResetService(
      secureStore: _ThrowingFullResetSecureStore(),
      nativeResetKeys: _ThrowingNativeResetKeys(),
      appDataDirectory: () async => throw StateError('app data failed'),
      temporaryDirectory: () async => Directory.systemTemp,
      mediaCacheDirectory: () async => Directory.systemTemp,
      clearMediaCache: () async {},
    );

    final decision = await service.runFreshInstallResidueGuard();

    expect(decision.mode, ResetStartupMode.freshInstallRecoveryRequired);
    expect(decision.report.files, contains('<fresh install guard failed>'));
  });
}

class _FakeFullResetSecureStore implements FullResetSecureStore {
  final values = <String, String>{};
  bool throwOnDeleteAll = false;
  Object? deleteAllError;
  int deleteAllCalls = 0;
  void Function()? onDeleteAll;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCalls += 1;
    onDeleteAll?.call();
    final deleteAllError = this.deleteAllError;
    if (deleteAllError != null) {
      throw deleteAllError;
    }
    if (throwOnDeleteAll) {
      throw StateError('deleteAll failed');
    }
    values.clear();
  }

  @override
  Future<Map<String, String>> readAll() async {
    return Map<String, String>.from(values);
  }
}

class _FakePlatformSecureStorage {
  final Map<String, String> store = <String, String>{};
  PlatformException? throwOnPrimarySecureStorage;
  int primaryFailureCalls = 0;
  int legacyReadAllCalls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            final isPrimary = _usesPrimarySecureStorageOptions(call);
            if (throwOnPrimarySecureStorage != null && isPrimary) {
              primaryFailureCalls += 1;
              throw throwOnPrimarySecureStorage!;
            }

            switch (call.method) {
              case 'write':
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                if (value == null) {
                  store.remove(key);
                } else {
                  store[key] = value;
                }
                return null;
              case 'read':
                return store[call.arguments['key'] as String];
              case 'readAll':
                if (!isPrimary) legacyReadAllCalls += 1;
                return Map<String, String>.from(store);
              case 'delete':
                store.remove(call.arguments['key'] as String);
                return null;
              case 'deleteAll':
                store.clear();
                return null;
              case 'containsKey':
                return store.containsKey(call.arguments['key'] as String);
              default:
                return null;
            }
          },
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    store.clear();
  }

  bool _usesPrimarySecureStorageOptions(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is! Map) return false;
    final options = arguments['options'];
    if (options is! Map) return false;

    final usesDataProtectionKeychain =
        options['usesDataProtectionKeychain'] ??
        options['useDataProtectionKeychain'];
    if (usesDataProtectionKeychain != null) {
      return usesDataProtectionKeychain != false &&
          usesDataProtectionKeychain != 'false';
    }

    return options['resetOnError'] == false ||
        options['resetOnError'] == 'false';
  }
}

PlatformException _macMissingEntitlementException() {
  return PlatformException(
    code: 'Unexpected security result code',
    message: "Code: -34018, Message: A required entitlement isn't present.",
    details: -34018,
  );
}

PlatformException _macInvalidParameterException() {
  return PlatformException(
    code: 'Unexpected security result code',
    message:
        'Code: -50, Message: One or more parameters passed to a function were not valid.',
    details: -50,
  );
}

class _FakeNativeResetKeys implements NativeResetKeys {
  int deleteKnownKeysCalls = 0;
  int clearApplicationUserDataCalls = 0;
  bool hasKeys = false;
  bool throwOnDeleteKnownKeys = false;
  bool clearApplicationUserDataResult = true;
  bool throwOnClearApplicationUserData = false;
  void Function()? onDeleteKnownKeys;
  void Function()? onClearApplicationUserData;

  @override
  Future<void> deleteKnownKeys({bool force = false}) async {
    deleteKnownKeysCalls += 1;
    onDeleteKnownKeys?.call();
    if (throwOnDeleteKnownKeys) {
      throw StateError('native delete failed');
    }
    hasKeys = false;
  }

  @override
  Future<bool> hasKnownNativeKeys() async => hasKeys;

  @override
  Future<bool> clearApplicationUserData() async {
    clearApplicationUserDataCalls += 1;
    onClearApplicationUserData?.call();
    if (throwOnClearApplicationUserData) {
      throw StateError('clear data failed');
    }
    return clearApplicationUserDataResult;
  }
}

class _ThrowingFullResetSecureStore implements FullResetSecureStore {
  @override
  Future<void> delete(String key) async {
    throw StateError('delete failed');
  }

  @override
  Future<void> deleteAll() async {
    throw StateError('deleteAll failed');
  }

  @override
  Future<Map<String, String>> readAll() async {
    throw StateError('readAll failed');
  }
}

class _ThrowingNativeResetKeys implements NativeResetKeys {
  @override
  Future<bool> clearApplicationUserData() async {
    throw StateError('clear data failed');
  }

  @override
  Future<void> deleteKnownKeys({bool force = false}) async {
    throw StateError('native delete failed');
  }

  @override
  Future<bool> hasKnownNativeKeys() async {
    throw StateError('native inspect failed');
  }
}
