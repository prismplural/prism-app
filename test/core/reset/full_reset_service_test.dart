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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall methodCall) async => null,
        );
  });

  tearDown(() {
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
    'fresh install guard clears secure residue when no app files exist',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'prism-fresh-secure-test-',
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
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kFreshInstallAnomalyKey), isNull);
    },
  );

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

      expect(decision.mode, ResetStartupMode.normal);
      expect(decision.report.files, isEmpty);
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
    'fresh install guard allows startup and retries when native cleanup fails',
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

      expect(decision.mode, ResetStartupMode.normal);
      expect(secureStore.values, isEmpty);
      expect(nativeKeys.deleteKnownKeysCalls, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kFreshInstallSentinelKey), isTrue);
      expect(prefs.getBool(kNativeResetKeyClearPendingKey), isTrue);

      nativeKeys.throwOnDeleteKnownKeys = false;
      final retryDecision = await service.runFreshInstallResidueGuard();

      expect(retryDecision.mode, ResetStartupMode.normal);
      expect(nativeKeys.deleteKnownKeysCalls, 2);
      expect(prefs.getBool(kNativeResetKeyClearPendingKey), isNull);
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
      expect(nativeKeys.deleteKnownKeysCalls, 1);

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

    test('keychainUnreadable mode is reachable and carries the diagnostic',
        () {
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

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
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

class _FakeNativeResetKeys implements NativeResetKeys {
  int deleteKnownKeysCalls = 0;
  bool hasKeys = false;
  bool throwOnDeleteKnownKeys = false;

  @override
  Future<void> deleteKnownKeys() async {
    deleteKnownKeysCalls += 1;
    if (throwOnDeleteKnownKeys) {
      throw StateError('native delete failed');
    }
    hasKeys = false;
  }

  @override
  Future<bool> hasKnownNativeKeys() async => hasKeys;

  @override
  Future<bool> clearApplicationUserData() async => true;
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
  Future<void> deleteKnownKeys() async {
    throw StateError('native delete failed');
  }

  @override
  Future<bool> hasKnownNativeKeys() async {
    throw StateError('native inspect failed');
  }
}
