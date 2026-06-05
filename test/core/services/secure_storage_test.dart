import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

// ---------------------------------------------------------------------------
// Method-channel-level fake secure storage.
//
// Mirrors the pattern used by biometric_service_test.dart and
// database_encryption_test.dart. The fss Dart side calls into a method
// channel, so the simplest faithful fake is a method-call handler that can
// either return values or throw PlatformException with realistic shapes
// (matching what FlutterSecureStoragePlugin.java#handleException emits in
// fss 10.0.0).
// ---------------------------------------------------------------------------

class _FakeSecureStorage {
  _FakeSecureStorage();

  final Map<String, String> store = <String, String>{};
  final Map<String, String> legacyStore = <String, String>{};

  bool isolateLegacyStore = false;

  /// Optional override: when set, every operation throws this exception.
  PlatformException? throwOnEvery;

  /// Optional override: when set, every read throws this exception (after
  /// [throwOnEvery] is checked).
  PlatformException? throwOnRead;

  /// Per-key read value override. Useful for write-verify tests where the
  /// platform write reports success but read-back observes different state.
  final Map<String, String?> readOverrideKey = <String, String?>{};

  /// Optional override: when set, readAll throws this exception (after
  /// [throwOnEvery] is checked).
  PlatformException? throwOnReadAll;

  /// Optional override: when set, write throws this exception (after
  /// [throwOnEvery] is checked).
  PlatformException? throwOnWrite;

  /// Optional override: when set, delete throws this exception (after
  /// [throwOnEvery] is checked).
  PlatformException? throwOnDelete;

  /// Optional override: when set, deleteAll throws this exception (after
  /// [throwOnEvery] is checked).
  PlatformException? throwOnDeleteAll;

  /// Throws for calls using Prism's primary secure-storage options.
  PlatformException? throwOnPrimarySecureStorage;

  /// Throws for reads using Prism's primary secure-storage options.
  PlatformException? throwOnPrimarySecureStorageRead;

  /// Per-key throw override for single reads. Useful for slot-probe tests.
  final Map<String, PlatformException> throwOnReadKey =
      <String, PlatformException>{};

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            if (throwOnEvery != null) throw throwOnEvery!;
            final usesPrimarySecureStorage = _usesPrimarySecureStorageOptions(
              call,
            );
            if (throwOnPrimarySecureStorage != null &&
                usesPrimarySecureStorage) {
              throw throwOnPrimarySecureStorage!;
            }
            final backingStore = isolateLegacyStore && !usesPrimarySecureStorage
                ? legacyStore
                : store;
            switch (call.method) {
              case 'write':
                if (throwOnWrite != null) throw throwOnWrite!;
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                if (value == null) {
                  backingStore.remove(key);
                } else {
                  backingStore[key] = value;
                }
                return null;
              case 'read':
                if (usesPrimarySecureStorage &&
                    throwOnPrimarySecureStorageRead != null) {
                  throw throwOnPrimarySecureStorageRead!;
                }
                final key = call.arguments['key'] as String;
                final perKey = throwOnReadKey[key];
                if (perKey != null) throw perKey;
                if (throwOnRead != null) throw throwOnRead!;
                if (readOverrideKey.containsKey(key)) {
                  return readOverrideKey[key];
                }
                return backingStore[key];
              case 'readAll':
                if (throwOnReadAll != null) throw throwOnReadAll!;
                return Map<String, String>.from(backingStore);
              case 'delete':
                if (throwOnDelete != null) throw throwOnDelete!;
                final key = call.arguments['key'] as String;
                backingStore.remove(key);
                return null;
              case 'deleteAll':
                if (throwOnDeleteAll != null) throw throwOnDeleteAll!;
                backingStore.clear();
                return null;
              case 'containsKey':
                final key = call.arguments['key'] as String;
                return backingStore.containsKey(key);
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
    legacyStore.clear();
    readOverrideKey.clear();
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

// ---------------------------------------------------------------------------
// Realistic PlatformException factories.
//
// fss 10.0.0 plugin (FlutterSecureStoragePlugin.java#handleException) always
// returns:
//   code     = 'Exception encountered'
//   message  = the underlying Java exception's getMessage()
//   details  = full stack trace string (includes the FQCN of the exception)
//
// So real Prism-on-Android failures look like:
//   code    : 'Exception encountered'
//   message : 'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT'
//   details : stack trace containing 'javax.crypto.AEADBadTagException'
// ---------------------------------------------------------------------------

PlatformException _fssCipherException({
  required String message,
  required String stackTraceFqcn,
}) {
  return PlatformException(
    code: 'Exception encountered',
    message: message,
    details:
        'at $stackTraceFqcn(SomeFile.java:123)\n'
        '\tat com.it_nomads.fluttersecurestorage.FlutterSecureStorage.read(FlutterSecureStorage.java:200)',
  );
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

void main() {
  test('Android secure-storage options fail closed on migration errors', () {
    final options = secureStorage.aOptions.toMap();
    expect(options['resetOnError'], 'false');
    expect(options['migrateOnAlgorithmChange'], 'true');
    expect(options['migrateWithBackup'], 'false');
    expect(
      options['keyCipherAlgorithm'],
      'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
    );
    expect(options['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
  });

  // ---------------------------------------------------------------------------
  // classifySecureStorageError
  // ---------------------------------------------------------------------------

  group('classifySecureStorageError', () {
    group('cipher fragments', () {
      test('AEADBadTagException in message → cipher', () {
        final ex = _fssCipherException(
          message:
              'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT, '
              'javax.crypto.AEADBadTagException: Error while decrypting',
          stackTraceFqcn: 'javax.crypto.AEADBadTagException',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('BadPaddingException in details → cipher', () {
        // Message empty/generic; classification must fall through to details.
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Unknown error',
          details:
              'javax.crypto.BadPaddingException: pad block corrupted\n\tat '
              'com.it_nomads.fluttersecurestorage.FlutterSecureStorage.read(FlutterSecureStorage.java:200)',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('BAD_DECRYPT in code with empty message → cipher', () {
        // Hypothetical future plugin shape where the code carries the hint.
        // Tests that code is checked BEFORE message.
        final ex = PlatformException(
          code: 'BAD_DECRYPT',
          message: null,
          details: null,
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('InvalidKeyException in message → cipher', () {
        final ex = _fssCipherException(
          message: 'Invalid key, key type incompatible with cipher',
          stackTraceFqcn: 'java.security.InvalidKeyException',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('Failed to unwrap key in message → cipher', () {
        final ex = _fssCipherException(
          message:
              'Migration failed after algorithm change. '
              'Caused by: java.security.InvalidKeyException: '
              'Failed to unwrap key',
          stackTraceFqcn:
              'android.security.keystore2.AndroidKeyStoreCipherSpiBase',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('IllegalBlockSizeException in details → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Failed to unwrap key',
          details:
              'javax.crypto.IllegalBlockSizeException\n\tat '
              'android.security.keystore2.AndroidKeyStoreCipherSpiBase.engineUnwrap',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('migration failure message → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message:
              'Migration failed after algorithm change (Bad padding, wrong key for cipher algorithm). '
              'Enable resetOnError=true or call deleteAll().',
          details: 'java.lang.Exception',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('unsupported algorithm message → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Required cryptographic algorithm not supported by device.',
          details: 'java.security.NoSuchAlgorithmException',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('null StorageCipher after failed initialization → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message:
              'Attempt to invoke virtual method '
              "'java.lang.String "
              'com.it_nomads.fluttersecurestorage.ciphers.StorageCipher.decrypt(String)\' '
              'on a null object reference',
          details:
              'java.lang.NullPointerException\n\tat '
              'com.it_nomads.fluttersecurestorage.FlutterSecureStorage.read(FlutterSecureStorage.java:216)',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('UnrecoverableKeyException in details → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Failed to get key',
          details:
              'java.security.UnrecoverableKeyException: '
              'Failed to obtain information about key',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('KeyPermanentlyInvalidatedException in details → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Key permanently invalidated',
          details:
              'android.security.keystore.KeyPermanentlyInvalidatedException: '
              'Key permanently invalidated',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });
    });

    group('transient fragments', () {
      test('UserNotAuthenticatedException → transient', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'User not authenticated',
          details:
              'android.security.keystore.UserNotAuthenticatedException: '
              'User not authenticated',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.transient);
      });

      test('BackendBusyException → transient', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Backend busy',
          details: 'android.security.KeyStoreException: -38 (BackendBusy)',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.transient);
      });
    });

    group('unknown', () {
      test('generic IOException → unknown', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'I/O error',
          details: 'java.io.IOException: Disk full',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.unknown);
      });

      test('totally empty exception → unknown', () {
        final ex = PlatformException(code: '');
        expect(classifySecureStorageError(ex), SecureStorageFailure.unknown);
      });

      test('null message and non-string details → unknown', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: null,
          details: <String, dynamic>{'some': 'map'},
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.unknown);
      });
    });

    group('case-insensitivity', () {
      test('uppercase AEADBADTAG in message → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'AEADBADTAGEXCEPTION',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('mixed-case BadPadding in details → cipher', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'Decryption failed',
          details: 'javax.crypto.BaDpAdDiNgException: pad block corrupted',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('uppercase USERNOTAUTHENTICATED → transient', () {
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'USERNOTAUTHENTICATED',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.transient);
      });
    });

    group('priority order', () {
      test('code is checked before details and message', () {
        // Code matches cipher; details + message match transient. Cipher wins
        // because code is checked first.
        final ex = PlatformException(
          code: 'BAD_DECRYPT',
          message: 'UserNotAuthenticated: please re-auth',
          details: 'UserNotAuthenticatedException stack...',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });

      test('details is checked before message', () {
        // Code is generic; details matches cipher; message matches transient.
        // Cipher wins because details is checked before message.
        final ex = PlatformException(
          code: 'Exception encountered',
          message: 'UserNotAuthenticated',
          details: 'javax.crypto.AEADBadTagException',
        );
        expect(classifySecureStorageError(ex), SecureStorageFailure.cipher);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // safeSecureRead
  // ---------------------------------------------------------------------------

  group('safeSecureRead', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
      debugForceMacSecureStorageEntitlementFallback = false;
    });

    tearDown(() {
      debugForceMacSecureStorageEntitlementFallback = false;
      fake.uninstall();
    });

    test('returns value on success', () async {
      fake.store['db_key'] = 'deadbeef';
      final result = await safeSecureRead(
        'db_key',
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isTrue);
      expect(result.value, 'deadbeef');
      expect(result.failure, isNull);
    });

    test('returns null value when key absent (still ok)', () async {
      final result = await safeSecureRead(
        'missing',
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isTrue);
      expect(result.value, isNull);
    });

    test(
      'reads legacy macOS keychain when primary keychain reports missing',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.isolateLegacyStore = true;
        fake.legacyStore['db_key'] = 'abc123';

        final result = await safeSecureRead('db_key', storage: secureStorage);

        expect(result.ok, isTrue);
        expect(result.value, 'abc123');
      },
    );

    test('classifies cipher PlatformException', () async {
      fake.throwOnRead = _fssCipherException(
        message: 'AEADBadTagException: bad tag',
        stackTraceFqcn: 'javax.crypto.AEADBadTagException',
      );
      final result = await safeSecureRead(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isFalse);
      expect(result.failure, SecureStorageFailure.cipher);
      expect(result.value, isNull);
      expect(result.message, contains('AEADBadTag'));
    });

    test('classifies transient PlatformException', () async {
      fake.throwOnRead = PlatformException(
        code: 'Exception encountered',
        message: 'UserNotAuthenticated',
      );
      final result = await safeSecureRead(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.transient);
    });

    test('classifies unknown PlatformException', () async {
      fake.throwOnRead = PlatformException(
        code: 'Exception encountered',
        message: 'random IO problem',
      );
      final result = await safeSecureRead(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.unknown);
    });
  });

  // ---------------------------------------------------------------------------
  // safeSecureWrite
  // ---------------------------------------------------------------------------

  group('safeSecureWrite', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
    });

    tearDown(() => fake.uninstall());

    test('writes successfully', () async {
      final result = await safeSecureWrite(
        'k',
        'v',
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isTrue);
      expect(fake.store['k'], 'v');
    });

    test('classifies cipher failure on write', () async {
      fake.throwOnWrite = _fssCipherException(
        message: 'Bad padding, wrong key for cipher algorithm',
        stackTraceFqcn: 'javax.crypto.BadPaddingException',
      );
      final result = await safeSecureWrite(
        'k',
        'v',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.cipher);
      expect(result.message, contains('Bad padding'));
    });

    test('classifies transient failure on write', () async {
      fake.throwOnWrite = PlatformException(
        code: 'Exception encountered',
        message: 'UserNotAuthenticated',
      );
      final result = await safeSecureWrite(
        'k',
        'v',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.transient);
    });

    test('classifies unknown failure on write', () async {
      fake.throwOnWrite = PlatformException(
        code: 'Exception encountered',
        message: 'disk full',
      );
      final result = await safeSecureWrite(
        'k',
        'v',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.unknown);
    });
  });

  // ---------------------------------------------------------------------------
  // safeSecureWriteVerified
  // ---------------------------------------------------------------------------

  group('safeSecureWriteVerified', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
    });

    tearDown(() => fake.uninstall());

    test('returns ok when write read-back matches', () async {
      final result = await safeSecureWriteVerified(
        'db_key',
        'abc123',
        storage: const FlutterSecureStorage(),
      );

      expect(result.ok, isTrue);
      expect(fake.store['db_key'], 'abc123');
    });

    test('returns unknown when write read-back mismatches', () async {
      fake.readOverrideKey['db_key'] = 'old-value';

      final result = await safeSecureWriteVerified(
        'db_key',
        'new-value',
        storage: const FlutterSecureStorage(),
      );

      expect(result.ok, isFalse);
      expect(result.failure, SecureStorageFailure.unknown);
      expect(result.code, 'PrismSecureStorageVerifyMismatch');
    });

    test(
      'returns classified read failure when verification read throws',
      () async {
        fake.throwOnReadKey['db_key'] = _fssCipherException(
          message:
              'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
          stackTraceFqcn: 'javax.crypto.AEADBadTagException',
        );

        final result = await safeSecureWriteVerified(
          'db_key',
          'abc123',
          storage: const FlutterSecureStorage(),
        );

        expect(result.ok, isFalse);
        expect(result.failure, SecureStorageFailure.cipher);
      },
    );

    test(
      'falls back to the macOS legacy keychain when DP keychain lacks entitlement',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.throwOnPrimarySecureStorage = _macMissingEntitlementException();

        final result = await safeSecureWriteVerified(
          'db_key',
          'abc123',
          storage: secureStorage,
        );

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
        expect(fake.store['db_key'], 'abc123');
      },
    );

    test(
      'falls back to the macOS legacy keychain when DP keychain returns errSecParam',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.throwOnPrimarySecureStorage = _macInvalidParameterException();

        final result = await safeSecureWriteVerified(
          'db_key',
          'abc123',
          storage: secureStorage,
        );

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
        expect(fake.store['db_key'], 'abc123');
      },
    );

    test(
      'rewrites legacy keychain when primary write verifies against empty fallback',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.isolateLegacyStore = true;
        fake.throwOnPrimarySecureStorageRead = _macInvalidParameterException();

        final result = await safeSecureWriteVerified(
          'db_key',
          'abc123',
          storage: secureStorage,
        );

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
        expect(fake.store['db_key'], 'abc123');
        expect(fake.legacyStore['db_key'], 'abc123');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // safeSecureDelete / safeSecureDeleteAll
  // ---------------------------------------------------------------------------

  group('safeSecureDelete', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
      debugForceMacSecureStorageEntitlementFallback = false;
    });

    tearDown(() {
      debugForceMacSecureStorageEntitlementFallback = false;
      fake.uninstall();
    });

    test('deletes successfully', () async {
      fake.store['k'] = 'v';
      final result = await safeSecureDelete(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isTrue);
      expect(fake.store.containsKey('k'), isFalse);
    });

    test('classifies cipher failure on delete', () async {
      fake.throwOnDelete = _fssCipherException(
        message: 'AEADBadTagException',
        stackTraceFqcn: 'javax.crypto.AEADBadTagException',
      );
      final result = await safeSecureDelete(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.cipher);
    });

    test('classifies transient failure on delete', () async {
      fake.throwOnDelete = PlatformException(
        code: 'Exception encountered',
        message: 'BackendBusy',
      );
      final result = await safeSecureDelete(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.transient);
    });

    test('classifies unknown failure on delete', () async {
      fake.throwOnDelete = PlatformException(
        code: 'Exception encountered',
        message: 'some IO thing',
      );
      final result = await safeSecureDelete(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.unknown);
    });

    test('safeSecureDeleteAll deletes everything', () async {
      fake.store['a'] = '1';
      fake.store['b'] = '2';
      final result = await safeSecureDeleteAll(
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isTrue);
      expect(fake.store, isEmpty);
    });

    test('safeSecureDeleteAll also clears legacy macOS entries', () async {
      debugForceMacSecureStorageEntitlementFallback = true;
      fake.isolateLegacyStore = true;
      fake.store['a'] = '1';
      fake.legacyStore['b'] = '2';

      final result = await safeSecureDeleteAll(storage: secureStorage);

      expect(
        result.ok,
        isTrue,
        reason:
            'failure=${result.failure} code=${result.code} '
            'message=${result.message}',
      );
      expect(fake.store, isEmpty);
      expect(fake.legacyStore, isEmpty);
    });

    test('safeSecureDeleteAll classifies cipher failure', () async {
      fake.throwOnDeleteAll = _fssCipherException(
        message: 'AEADBadTagException',
        stackTraceFqcn: 'javax.crypto.AEADBadTagException',
      );
      final result = await safeSecureDeleteAll(
        storage: const FlutterSecureStorage(),
      );
      expect(result.failure, SecureStorageFailure.cipher);
    });

    test(
      'safeSecureDelete treats macOS missing entitlement plus absent legacy key as success',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.throwOnPrimarySecureStorage = _macMissingEntitlementException();

        final result = await safeSecureDelete(
          'missing',
          storage: secureStorage,
        );

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
      },
    );

    test(
      'safeSecureDeleteAll sweeps legacy macOS entries after DP keychain entitlement failure',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.store['a'] = '1';
        fake.store['b'] = '2';
        fake.throwOnPrimarySecureStorage = _macMissingEntitlementException();

        final result = await safeSecureDeleteAll(storage: secureStorage);

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
        expect(fake.store, isEmpty);
      },
    );

    test(
      'safeSecureDeleteAll sweeps legacy macOS entries after DP keychain errSecParam',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.store['a'] = '1';
        fake.store['b'] = '2';
        fake.throwOnPrimarySecureStorage = _macInvalidParameterException();

        final result = await safeSecureDeleteAll(storage: secureStorage);

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
        expect(fake.store, isEmpty);
      },
    );

    test(
      'safeSecureDeleteAll uses legacy deleteAll when legacy readAll is rejected',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake
          ..isolateLegacyStore = true
          ..throwOnPrimarySecureStorage = _macInvalidParameterException()
          ..throwOnReadAll = _macInvalidParameterException();
        fake.legacyStore['db_key'] = 'abc123';

        final result = await safeSecureDeleteAll(storage: secureStorage);

        expect(
          result.ok,
          isTrue,
          reason:
              'failure=${result.failure} code=${result.code} '
              'message=${result.message}',
        );
        expect(fake.legacyStore, isEmpty);
      },
    );
  });

  group('SecureStorageFaultInjector', () {
    late _FakeSecureStorage fake;

    setUp(() {
      SecureStorageFaultInjector.enableForTesting();
      SecureStorageFaultInjector.clear();
      fake = _FakeSecureStorage();
      fake.install();
    });

    tearDown(() {
      SecureStorageFaultInjector.disableForTesting();
      fake.uninstall();
    });

    test('injects one read failure and then consumes it', () async {
      fake.store['k'] = 'v';
      SecureStorageFaultInjector.queueNext(
        operation: SecureStorageFaultOperation.read,
        key: 'k',
      );

      final first = await safeSecureRead(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(first.failure, SecureStorageFailure.cipher);

      final second = await safeSecureRead(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(second.ok, isTrue);
      expect(second.value, 'v');
    });

    test('injected delete failure leaves the stored value intact', () async {
      fake.store['k'] = 'v';
      SecureStorageFaultInjector.queueNext(
        operation: SecureStorageFaultOperation.delete,
        key: 'k',
      );

      final first = await safeSecureDelete(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(first.failure, SecureStorageFailure.cipher);
      expect(fake.store['k'], 'v');

      final second = await safeSecureDelete(
        'k',
        storage: const FlutterSecureStorage(),
      );
      expect(second.ok, isTrue);
      expect(fake.store.containsKey('k'), isFalse);
    });

    test(
      'injects readAll failure without consuming key-specific faults',
      () async {
        fake.store['k'] = 'v';
        SecureStorageFaultInjector.queueNext(
          operation: SecureStorageFaultOperation.readAll,
        );
        SecureStorageFaultInjector.queueNext(
          operation: SecureStorageFaultOperation.read,
          key: 'k',
        );

        final readAll = await safeSecureReadAll(
          storage: const FlutterSecureStorage(),
        );
        expect(readAll.failure, SecureStorageFailure.cipher);
        expect(SecureStorageFaultInjector.pending, hasLength(1));

        final read = await safeSecureRead(
          'k',
          storage: const FlutterSecureStorage(),
        );
        expect(read.failure, SecureStorageFailure.cipher);
        expect(SecureStorageFaultInjector.pending, isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // safeSecureReadAll
  // ---------------------------------------------------------------------------

  group('safeSecureReadAll', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
      debugForceMacSecureStorageEntitlementFallback = false;
    });

    tearDown(() {
      debugForceMacSecureStorageEntitlementFallback = false;
      fake.uninstall();
    });

    test('returns every entry on success', () async {
      fake.store['a'] = '1';
      fake.store['b'] = '2';
      final result = await safeSecureReadAll(
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isTrue);
      expect(result.entries, {'a': '1', 'b': '2'});
    });

    test(
      'includes legacy macOS entries when primary readAll succeeds',
      () async {
        debugForceMacSecureStorageEntitlementFallback = true;
        fake.isolateLegacyStore = true;
        fake.store['primary'] = 'one';
        fake.legacyStore['legacy'] = 'two';

        final result = await safeSecureReadAll(storage: secureStorage);

        expect(result.ok, isTrue);
        expect(result.entries, {'primary': 'one', 'legacy': 'two'});
      },
    );

    test('classifies cipher failure', () async {
      fake.throwOnReadAll = _fssCipherException(
        message: 'AEADBadTagException',
        stackTraceFqcn: 'javax.crypto.AEADBadTagException',
      );
      final result = await safeSecureReadAll(
        storage: const FlutterSecureStorage(),
      );
      expect(result.ok, isFalse);
      expect(result.failure, SecureStorageFailure.cipher);
      expect(result.entries, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // safeSecureReadAllWithSlotProbe
  // ---------------------------------------------------------------------------

  group('safeSecureReadAllWithSlotProbe', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
    });

    tearDown(() => fake.uninstall());

    test('returns readAll result directly on success', () async {
      fake.store['a'] = '1';
      fake.store['b'] = '2';
      final result = await safeSecureReadAllWithSlotProbe(const [
        'a',
        'b',
      ], storage: const FlutterSecureStorage());
      expect(result.ok, isTrue);
      expect(result.entries, {'a': '1', 'b': '2'});
    });

    test('falls back to per-key probes when readAll cipher-fails', () async {
      // readAll throws cipher; per-key reads for 'a' succeed, 'b' also cipher
      // fails, 'c' absent. We should get only 'a' back, with the original
      // readAll failure preserved.
      fake.store['a'] = 'apple';
      fake.store['b'] = 'banana';
      fake.throwOnReadAll = _fssCipherException(
        message: 'AEADBadTagException',
        stackTraceFqcn: 'javax.crypto.AEADBadTagException',
      );
      fake.throwOnReadKey['b'] = _fssCipherException(
        message: 'BadPadding',
        stackTraceFqcn: 'javax.crypto.BadPaddingException',
      );

      final result = await safeSecureReadAllWithSlotProbe(const [
        'a',
        'b',
        'c',
      ], storage: const FlutterSecureStorage());

      expect(result.ok, isFalse);
      expect(result.failure, SecureStorageFailure.cipher);
      // 'a' read succeeded, salvaged. 'b' cipher-failed, omitted. 'c' absent.
      expect(result.entries, {'a': 'apple'});
    });

    test('does not fall back when readAll transient-fails', () async {
      // Transient failures don't trigger slot probing — they're retryable
      // by the caller, not a sign the whole store is corrupt.
      fake.throwOnReadAll = PlatformException(
        code: 'Exception encountered',
        message: 'UserNotAuthenticated',
      );

      final result = await safeSecureReadAllWithSlotProbe(const [
        'a',
        'b',
      ], storage: const FlutterSecureStorage());

      expect(result.failure, SecureStorageFailure.transient);
      expect(result.entries, isEmpty);
    });
  });

  group('readPrefixed', () {
    late _FakeSecureStorage fake;

    setUp(() {
      fake = _FakeSecureStorage();
      fake.install();
    });

    tearDown(() => fake.uninstall());

    test('returns only entries with the requested prefix', () async {
      fake.store['prism_sync.device_id'] = 'device';
      fake.store['prism_sync.sync_id'] = 'sync';
      fake.store['other.key'] = 'other';

      final result = await readPrefixed('prism_sync.');

      expect(result, {
        'prism_sync.device_id': 'device',
        'prism_sync.sync_id': 'sync',
      });
    });

    test(
      'classifies readAll failure instead of leaking PlatformException',
      () async {
        fake.throwOnReadAll = _fssCipherException(
          message: 'AEADBadTagException',
          stackTraceFqcn: 'javax.crypto.AEADBadTagException',
        );

        await expectLater(
          readPrefixed('prism_sync.'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('failure=cipher'),
            ),
          ),
        );
      },
    );
  });
}
