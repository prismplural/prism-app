import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_provider.dart';

// ---------------------------------------------------------------------------
// In-memory FlutterSecureStorage stub (same pattern as biometric_service_test)
//
// Extended to support per-key/per-method PlatformException throws so we can
// exercise the classified-read paths in database_encryption.dart.
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};

  /// Per-key call counter for reads (used to assert "cipher does not retry").
  final Map<String, int> readCalls = <String, int>{};

  /// Per-key queued read exceptions. If the queue is non-empty, the next read
  /// for that key throws the first entry and removes it. After the queue
  /// drains the read returns the stored value.
  final Map<String, List<PlatformException>> throwOnReadKeyQueue =
      <String, List<PlatformException>>{};

  /// Per-key queued write exceptions. If the queue is non-empty, the next
  /// write for that key throws the first entry and removes it. The store is
  /// left unchanged, matching a platform write failure.
  final Map<String, List<PlatformException>> throwOnWriteKeyQueue =
      <String, List<PlatformException>>{};

  void setup() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            switch (call.method) {
              case 'write':
                final key = call.arguments['key'] as String;
                final value = call.arguments['value'] as String?;
                final queue = throwOnWriteKeyQueue[key];
                if (queue != null && queue.isNotEmpty) {
                  throw queue.removeAt(0);
                }
                _store[key] = value;
                return null;
              case 'read':
                final key = call.arguments['key'] as String;
                readCalls[key] = (readCalls[key] ?? 0) + 1;
                final queue = throwOnReadKeyQueue[key];
                if (queue != null && queue.isNotEmpty) {
                  throw queue.removeAt(0);
                }
                return _store[key];
              case 'delete':
                final key = call.arguments['key'] as String;
                _store.remove(key);
                return null;
              case 'containsKey':
                final key = call.arguments['key'] as String;
                return _store.containsKey(key);
              default:
                return null;
            }
          },
        );
  }

  void teardown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    _store.clear();
    readCalls.clear();
    throwOnReadKeyQueue.clear();
    throwOnWriteKeyQueue.clear();
  }
}

PlatformException _cipherException() => PlatformException(
  code: 'Exception encountered',
  message: 'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
  details:
      'javax.crypto.AEADBadTagException: Error while decrypting\n\tat '
      'com.it_nomads.fluttersecurestorage.FlutterSecureStorage.read(FlutterSecureStorage.java:200)',
);

PlatformException _transientException() => PlatformException(
  code: 'Exception encountered',
  message: 'UserNotAuthenticated',
  details:
      'android.security.keystore.UserNotAuthenticatedException: '
      'User not authenticated',
);

void main() {
  // ---------------------------------------------------------------------------
  // validateHexKey
  // ---------------------------------------------------------------------------

  group('validateHexKey', () {
    test('accepts valid 64-char lowercase hex', () {
      final hex = List.generate(64, (_) => 'a').join();
      expect(validateHexKey(hex), isTrue);
    });

    test('accepts mixed hex chars', () {
      final hex = '0123456789abcdef' * 4; // 64 chars
      expect(validateHexKey(hex), isTrue);
    });

    test('rejects null', () {
      expect(validateHexKey(null), isFalse);
    });

    test('rejects empty string', () {
      expect(validateHexKey(''), isFalse);
    });

    test('rejects too short', () {
      expect(validateHexKey('abcdef'), isFalse);
    });

    test('rejects too long', () {
      final hex = List.generate(65, (_) => 'a').join();
      expect(validateHexKey(hex), isFalse);
    });

    test('rejects uppercase hex', () {
      final hex = List.generate(64, (_) => 'A').join();
      expect(validateHexKey(hex), isFalse);
    });

    test('rejects non-hex characters', () {
      final hex = List.generate(64, (_) => 'g').join();
      expect(validateHexKey(hex), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // restoreDatabaseKeyHexForRecovery
  // ---------------------------------------------------------------------------

  group('restoreDatabaseKeyHexForRecovery', () {
    late _SecureStorageStub storageStub;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      // Guarded writers consult shared_preferences; default to "not pending".
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      storageStub.teardown();
    });

    test('writes a verified recovery key to the primary Drift slot', () async {
      final hexKey = '0123456789abcdef' * 4;
      storageStub._store['${kDatabaseKeyStorageKey}_staging'] = hexKey;

      await restoreDatabaseKeyHexForRecovery(hexKey);

      expect(storageStub._store[kDatabaseKeyStorageKey], hexKey);
      expect(
        storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
        isFalse,
      );
    });

    test('rejects invalid recovery keys', () async {
      expect(
        () => restoreDatabaseKeyHexForRecovery('not-a-key'),
        throwsArgumentError,
      );
      expect(storageStub._store[kDatabaseKeyStorageKey], isNull);
    });
  });

  group('verified sync recovery key', () {
    late Directory tempDir;
    late _SecureStorageStub storageStub;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'prism_db_recovery_candidate_',
      );
      storageStub = _SecureStorageStub()..setup();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    test('tries sync staging when sync primary does not open app DB', () async {
      final dbPath = '${tempDir.path}/prism.db';
      final oldKey = 'aa' * 32;
      final newKey = 'bb' * 32;

      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$newKey'\";");
      db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
      db.close();

      storageStub._store[kSyncDatabaseKeyStorageKey] = oldKey;
      storageStub._store['${kSyncDatabaseKeyStorageKey}_staging'] = newKey;

      expect(await verifiedSyncRecoveryKeyForTest(dbPath), newKey);
    });
  });

  // ---------------------------------------------------------------------------
  // makeCipherSetup
  // ---------------------------------------------------------------------------

  group('makeCipherSetup', () {
    test('returns a setup callback for valid hex key', () {
      final hex = '0123456789abcdef' * 4;
      final setup = makeCipherSetup(hex);
      expect(setup, isA<Function>());
    });

    test('asserts on invalid hex key', () {
      expect(() => makeCipherSetup('bad'), throwsA(isA<AssertionError>()));
    });
  });

  // ---------------------------------------------------------------------------
  // On-disk encryption integration tests
  // ---------------------------------------------------------------------------

  group('on-disk encryption', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_db_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    String generateHexKey() {
      final rng = Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = rng.nextInt(256);
      }
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    test('fresh encrypted DB can round-trip data', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = generateHexKey();

      // Create encrypted DB and write data
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);');
      db.execute("INSERT INTO test (id, value) VALUES (1, 'hello');");
      db.close();

      // Reopen and verify data
      final db2 = raw.sqlite3.open(dbPath);
      db2.execute("PRAGMA key = \"x'$hexKey'\";");
      final rows = db2.select('SELECT value FROM test WHERE id = 1;');
      expect(rows.first['value'], 'hello');
      db2.close();
    });

    test('encrypted DB is not readable without key', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = generateHexKey();

      // Create encrypted DB
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);');
      db.execute("INSERT INTO test (id, value) VALUES (1, 'secret');");
      db.close();

      // Try to open without key — should fail
      final db2 = raw.sqlite3.open(dbPath);
      expect(
        () => db2.select('SELECT count(*) FROM sqlite_master;'),
        throwsA(anything),
      );
      db2.close();
    });

    test('encrypted DB is not readable with wrong key', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = generateHexKey();
      final wrongKey = generateHexKey();

      // Create encrypted DB with key A
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);');
      db.close();

      // Try to open with key B — should fail
      final db2 = raw.sqlite3.open(dbPath);
      db2.execute("PRAGMA key = \"x'$wrongKey'\";");
      expect(
        () => db2.select('SELECT count(*) FROM sqlite_master;'),
        throwsA(anything),
      );
      db2.close();
    });

    test('_tryOpenEncrypted-style probe succeeds with correct key', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = generateHexKey();

      // Create encrypted DB
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY);');
      db.close();

      // Probe with correct key
      bool readable = false;
      try {
        final probe = raw.sqlite3.open(dbPath);
        try {
          probe.execute("PRAGMA key = \"x'$hexKey'\";");
          probe.select('SELECT count(*) FROM sqlite_master;');
          readable = true;
        } finally {
          probe.close();
        }
      } catch (_) {}
      expect(readable, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // tryOpenEncryptedDb (public probe utility)
  // ---------------------------------------------------------------------------

  group('tryOpenEncryptedDb', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_db_probe_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    String generateHexKey() {
      final rng = Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = rng.nextInt(256);
      }
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    test('returns true for correct key on encrypted database', () {
      final dbPath = '${tempDir.path}/probe.db';
      final hexKey = generateHexKey();

      // Create an encrypted database
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
      db.close();

      expect(tryOpenEncryptedDb(dbPath, hexKey), isTrue);
    });

    test('returns false for wrong key on encrypted database', () {
      final dbPath = '${tempDir.path}/probe.db';
      final keyA = generateHexKey();
      final keyB = generateHexKey();

      // Create with key A
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$keyA'\";");
      db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
      db.close();

      // Probe with key B — should fail
      expect(tryOpenEncryptedDb(dbPath, keyB), isFalse);
    });

    test('returns false for non-existent file', () {
      final hexKey = generateHexKey();
      expect(tryOpenEncryptedDb('${tempDir.path}/nope.db', hexKey), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Staging key helper functions (with mock SecureStorage)
  // ---------------------------------------------------------------------------

  group('staging key helpers', () {
    final storageStub = _SecureStorageStub();

    setUp(() {
      storageStub.setup();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(storageStub.teardown);

    test(
      'readStagingDatabaseKeyHex returns null when no staging key exists',
      () async {
        expect(await readStagingDatabaseKeyHex(), isNull);
      },
    );

    test(
      'readStagingDatabaseKeyHex returns null and ignores invalid (short) key',
      () async {
        storageStub._store['${kDatabaseKeyStorageKey}_staging'] = 'tooshort';
        expect(await readStagingDatabaseKeyHex(), isNull);
      },
    );

    test(
      'promoteStagingDatabaseKey writes to primary slot and removes staging',
      () async {
        final hexKey = 'ab' * 32; // 64 lowercase hex chars
        storageStub._store['${kDatabaseKeyStorageKey}_staging'] = hexKey;
        storageStub._store[kDatabaseKeyStorageKey] = 'oldkey${'0' * 58}';

        await promoteStagingDatabaseKey(hexKey);

        expect(storageStub._store[kDatabaseKeyStorageKey], equals(hexKey));
        expect(
          storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
          isFalse,
        );
      },
    );

    test('discardStagingDatabaseKey removes staging slot only', () async {
      final primaryKey = 'cd' * 32;
      final stagingKey = 'ef' * 32;
      storageStub._store[kDatabaseKeyStorageKey] = primaryKey;
      storageStub._store['${kDatabaseKeyStorageKey}_staging'] = stagingKey;

      await discardStagingDatabaseKey();

      // Primary slot unchanged
      expect(storageStub._store[kDatabaseKeyStorageKey], equals(primaryKey));
      // Staging slot removed
      expect(
        storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Staging crash recovery scenarios
  // ---------------------------------------------------------------------------
  //
  // Scenario A: crash AFTER PRAGMA rekey, BEFORE writing primary keychain slot.
  //   State: DB encrypted with new key (stagingKey), primary slot still has old key.
  //   Recovery: staging key opens DB → promote staging to primary.
  //
  // Scenario B: crash BEFORE PRAGMA rekey.
  //   State: DB still encrypted with old key (primary slot), staging slot has wrong key.
  //   Recovery: staging key does NOT open DB → discard staging.

  group('staging crash recovery scenarios', () {
    late Directory tempDir;
    final storageStub = _SecureStorageStub();

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_crash_recovery_');
      storageStub.setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    String makeHexKey(int fill) {
      return fill.toRadixString(16).padLeft(2, '0') * 32;
    }

    test(
      'Scenario A: staging key opens DB → promotes staging to primary',
      () async {
        final dbPath = '${tempDir.path}/prism_sync.db';
        final oldKey = makeHexKey(0xaa); // primary slot — stale after crash
        final newKey = makeHexKey(
          0xbb,
        ); // staging slot — rekey succeeded before crash

        // DB was re-keyed to newKey before the crash
        final db = raw.sqlite3.open(dbPath);
        db.execute("PRAGMA key = \"x'$newKey'\";");
        db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
        db.close();

        // Simulate keychain state after crash
        storageStub._store[kSyncDatabaseKeyStorageKey] = oldKey;
        storageStub._store['${kSyncDatabaseKeyStorageKey}_staging'] = newKey;

        // Recovery logic (mirrors prism_sync_providers.dart createHandle)
        final stagingKey = await readStagingSyncDatabaseKeyHex();
        expect(stagingKey, equals(newKey));

        if (stagingKey != null &&
            File(dbPath).existsSync() &&
            tryOpenEncryptedDb(dbPath, stagingKey)) {
          await promoteStagingSyncDatabaseKey(stagingKey);
        } else {
          await discardStagingSyncDatabaseKey();
        }

        // Primary slot updated to new key
        expect(storageStub._store[kSyncDatabaseKeyStorageKey], equals(newKey));
        // Staging slot cleared
        expect(
          storageStub._store.containsKey(
            '${kSyncDatabaseKeyStorageKey}_staging',
          ),
          isFalse,
        );
      },
    );

    test(
      'Scenario B: staging key does not open DB → staging discarded',
      () async {
        final dbPath = '${tempDir.path}/prism_sync.db';
        final realKey = makeHexKey(0xcc); // DB actually encrypted with this
        final staleKey = makeHexKey(
          0xdd,
        ); // written to staging, rekey never ran

        // DB is still encrypted with realKey (rekey never happened)
        final db = raw.sqlite3.open(dbPath);
        db.execute("PRAGMA key = \"x'$realKey'\";");
        db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY);');
        db.close();

        // Simulate keychain state: primary=realKey, staging=staleKey
        storageStub._store[kSyncDatabaseKeyStorageKey] = realKey;
        storageStub._store['${kSyncDatabaseKeyStorageKey}_staging'] = staleKey;

        // Recovery logic
        final stagingKey = await readStagingSyncDatabaseKeyHex();
        expect(stagingKey, equals(staleKey));

        if (stagingKey != null &&
            File(dbPath).existsSync() &&
            tryOpenEncryptedDb(dbPath, stagingKey)) {
          await promoteStagingSyncDatabaseKey(stagingKey);
        } else {
          await discardStagingSyncDatabaseKey();
        }

        // Primary slot unchanged
        expect(storageStub._store[kSyncDatabaseKeyStorageKey], equals(realKey));
        // Staging slot cleared
        expect(
          storageStub._store.containsKey(
            '${kSyncDatabaseKeyStorageKey}_staging',
          ),
          isFalse,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Classified reads — cipher / transient / unknown handling (§3)
  // ---------------------------------------------------------------------------

  group('readDatabaseKeyHex classified failures', () {
    late _SecureStorageStub storageStub;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test('returns the value on successful read with valid hex', () async {
      final hexKey = 'ab' * 32;
      storageStub._store[kDatabaseKeyStorageKey] = hexKey;
      expect(await readDatabaseKeyHex(), equals(hexKey));
    });

    test('returns null when storage returns null (key missing)', () async {
      expect(await readDatabaseKeyHex(), isNull);
    });

    test('returns null on successful read with invalid hex', () async {
      storageStub._store[kDatabaseKeyStorageKey] = 'definitely-not-hex';
      expect(await readDatabaseKeyHex(), isNull);
    });

    test('returns null on cipher failure (no throw, no retry)', () async {
      storageStub.throwOnReadKeyQueue[kDatabaseKeyStorageKey] = [
        _cipherException(),
      ];
      expect(await readDatabaseKeyHex(), isNull);
      // Cipher MUST NOT retry — exactly one read attempt.
      expect(storageStub.readCalls[kDatabaseKeyStorageKey], 1);
    });

    test('returns null on unknown failure (no throw, no retry)', () async {
      storageStub.throwOnReadKeyQueue[kDatabaseKeyStorageKey] = [
        PlatformException(
          code: 'Exception encountered',
          message: 'random IO problem',
        ),
      ];
      expect(await readDatabaseKeyHex(), isNull);
      expect(storageStub.readCalls[kDatabaseKeyStorageKey], 1);
    });

    test(
      'transient failure retries and returns the value on recovery',
      () async {
        final hexKey = 'cd' * 32;
        storageStub._store[kDatabaseKeyStorageKey] = hexKey;
        storageStub.throwOnReadKeyQueue[kDatabaseKeyStorageKey] = [
          _transientException(),
        ];
        expect(await readDatabaseKeyHex(), equals(hexKey));
        // Initial attempt + one retry = 2 calls.
        expect(storageStub.readCalls[kDatabaseKeyStorageKey], 2);
      },
    );

    test(
      'transient failure exhausts retries → null after 3 attempts',
      () async {
        storageStub.throwOnReadKeyQueue[kDatabaseKeyStorageKey] = [
          _transientException(),
          _transientException(),
          _transientException(),
        ];
        expect(await readDatabaseKeyHex(), isNull);
        // Initial + 2 retries.
        expect(storageStub.readCalls[kDatabaseKeyStorageKey], 3);
      },
    );
  });

  group('readSyncDatabaseKeyHex classified failures', () {
    late _SecureStorageStub storageStub;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test('returns the value on success', () async {
      final hex = 'ef' * 32;
      storageStub._store[kSyncDatabaseKeyStorageKey] = hex;
      expect(await readSyncDatabaseKeyHex(), equals(hex));
    });

    test('returns null on null (missing)', () async {
      expect(await readSyncDatabaseKeyHex(), isNull);
    });

    test('returns null on invalid hex', () async {
      storageStub._store[kSyncDatabaseKeyStorageKey] = 'short';
      expect(await readSyncDatabaseKeyHex(), isNull);
    });

    test('returns null on cipher failure (no retry)', () async {
      storageStub.throwOnReadKeyQueue[kSyncDatabaseKeyStorageKey] = [
        _cipherException(),
      ];
      expect(await readSyncDatabaseKeyHex(), isNull);
      expect(storageStub.readCalls[kSyncDatabaseKeyStorageKey], 1);
    });

    test('transient retry recovers the value', () async {
      final hex = '12' * 32;
      storageStub._store[kSyncDatabaseKeyStorageKey] = hex;
      storageStub.throwOnReadKeyQueue[kSyncDatabaseKeyStorageKey] = [
        _transientException(),
      ];
      expect(await readSyncDatabaseKeyHex(), equals(hex));
      expect(storageStub.readCalls[kSyncDatabaseKeyStorageKey], 2);
    });
  });

  group('readStagingDatabaseKeyHex classified failures', () {
    late _SecureStorageStub storageStub;
    const stagingKey = '${kDatabaseKeyStorageKey}_staging';

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test('returns null on cipher failure (no retry)', () async {
      storageStub.throwOnReadKeyQueue[stagingKey] = [_cipherException()];
      expect(await readStagingDatabaseKeyHex(), isNull);
      expect(storageStub.readCalls[stagingKey], 1);
    });

    test('returns value on success with valid hex', () async {
      final hex = '34' * 32;
      storageStub._store[stagingKey] = hex;
      expect(await readStagingDatabaseKeyHex(), equals(hex));
    });

    test('returns null on success with invalid hex', () async {
      storageStub._store[stagingKey] = 'not-hex';
      expect(await readStagingDatabaseKeyHex(), isNull);
    });
  });

  group('readStagingSyncDatabaseKeyHex classified failures', () {
    late _SecureStorageStub storageStub;
    const stagingKey = '${kSyncDatabaseKeyStorageKey}_staging';

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test('returns null on cipher failure (no retry)', () async {
      storageStub.throwOnReadKeyQueue[stagingKey] = [_cipherException()];
      expect(await readStagingSyncDatabaseKeyHex(), isNull);
      expect(storageStub.readCalls[stagingKey], 1);
    });

    test('transient retry recovers the value', () async {
      final hex = '56' * 32;
      storageStub._store[stagingKey] = hex;
      storageStub.throwOnReadKeyQueue[stagingKey] = [_transientException()];
      expect(await readStagingSyncDatabaseKeyHex(), equals(hex));
      expect(storageStub.readCalls[stagingKey], 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Keychain repair flag round-trip (§3)
  // ---------------------------------------------------------------------------

  group('keychain repair pending flag', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to false when unset', () async {
      expect(await isKeychainRepairPending(), isFalse);
    });

    test('round-trips true', () async {
      await setKeychainRepairPending(true);
      expect(await isKeychainRepairPending(), isTrue);
    });

    test('round-trips back to false', () async {
      await setKeychainRepairPending(true);
      await setKeychainRepairPending(false);
      expect(await isKeychainRepairPending(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Guarded primary writers (§3)
  // ---------------------------------------------------------------------------

  group('writeDatabaseKeyHex guard', () {
    late _SecureStorageStub storageStub;
    final hex = '78' * 32;
    final otherHex = '9a' * 32;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test('passes through when repair-pending is false', () async {
      final result = await writeDatabaseKeyHex(hex);
      expect(result.ok, isTrue);
      expect(storageStub._store[kDatabaseKeyStorageKey], equals(hex));
    });

    test('matching verifiedStartupKey allowed during repair-pending', () async {
      await setKeychainRepairPending(true);
      final result = await writeDatabaseKeyHex(hex, verifiedStartupKey: hex);
      expect(result.ok, isTrue);
      expect(storageStub._store[kDatabaseKeyStorageKey], equals(hex));
    });

    test('divergent value refused during repair-pending', () async {
      await setKeychainRepairPending(true);
      expect(
        () => writeDatabaseKeyHex(otherHex, verifiedStartupKey: hex),
        throwsStateError,
      );
      // Should NOT have written.
      expect(storageStub._store.containsKey(kDatabaseKeyStorageKey), isFalse);
    });

    test('null verifiedStartupKey refused during repair-pending', () async {
      await setKeychainRepairPending(true);
      expect(() => writeDatabaseKeyHex(hex), throwsStateError);
      expect(storageStub._store.containsKey(kDatabaseKeyStorageKey), isFalse);
    });
  });

  group('writeSyncDatabaseKeyHex guard', () {
    late _SecureStorageStub storageStub;
    final hex = 'bc' * 32;
    final otherHex = 'de' * 32;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test('passes through when not pending', () async {
      final result = await writeSyncDatabaseKeyHex(hex);
      expect(result.ok, isTrue);
      expect(storageStub._store[kSyncDatabaseKeyStorageKey], equals(hex));
    });

    test('matching verifiedStartupKey allowed during repair-pending', () async {
      await setKeychainRepairPending(true);
      final result = await writeSyncDatabaseKeyHex(
        hex,
        verifiedStartupKey: hex,
      );
      expect(result.ok, isTrue);
      expect(storageStub._store[kSyncDatabaseKeyStorageKey], equals(hex));
    });

    test('divergent value refused during repair-pending', () async {
      await setKeychainRepairPending(true);
      expect(
        () => writeSyncDatabaseKeyHex(otherHex, verifiedStartupKey: hex),
        throwsStateError,
      );
      expect(
        storageStub._store.containsKey(kSyncDatabaseKeyStorageKey),
        isFalse,
      );
    });

    test('null verifiedStartupKey refused during repair-pending', () async {
      await setKeychainRepairPending(true);
      expect(() => writeSyncDatabaseKeyHex(hex), throwsStateError);
      expect(
        storageStub._store.containsKey(kSyncDatabaseKeyStorageKey),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Guarded staging writers (§3)
  // ---------------------------------------------------------------------------

  group('staging writers refuse all writes during repair-pending', () {
    late _SecureStorageStub storageStub;
    final hex = '01' * 32;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test(
      'writeStagingDatabaseKeyHex passes through when not pending',
      () async {
        final result = await writeStagingDatabaseKeyHex(hex);
        expect(result.ok, isTrue);
        expect(
          storageStub._store['${kDatabaseKeyStorageKey}_staging'],
          equals(hex),
        );
      },
    );

    test(
      'writeStagingDatabaseKeyHex refused entirely during pending',
      () async {
        await setKeychainRepairPending(true);
        expect(() => writeStagingDatabaseKeyHex(hex), throwsStateError);
        expect(
          storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
          isFalse,
        );
      },
    );

    test(
      'writeStagingSyncDatabaseKeyHex passes through when not pending',
      () async {
        final result = await writeStagingSyncDatabaseKeyHex(hex);
        expect(result.ok, isTrue);
        expect(
          storageStub._store['${kSyncDatabaseKeyStorageKey}_staging'],
          equals(hex),
        );
      },
    );

    test(
      'writeStagingSyncDatabaseKeyHex refused entirely during pending',
      () async {
        await setKeychainRepairPending(true);
        expect(() => writeStagingSyncDatabaseKeyHex(hex), throwsStateError);
        expect(
          storageStub._store.containsKey(
            '${kSyncDatabaseKeyStorageKey}_staging',
          ),
          isFalse,
        );
      },
    );
  });

  group('high-level DB key writers require durable primary writes', () {
    late _SecureStorageStub storageStub;
    final hex = '23' * 32;

    setUp(() {
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() => storageStub.teardown());

    test(
      'promoteStagingDatabaseKey keeps staging when primary write fails',
      () async {
        const stagingSlot = '${kDatabaseKeyStorageKey}_staging';
        storageStub._store[kDatabaseKeyStorageKey] = '11' * 32;
        storageStub._store[stagingSlot] = hex;
        storageStub.throwOnWriteKeyQueue[kDatabaseKeyStorageKey] = [
          _cipherException(),
        ];

        await expectLater(
          () => promoteStagingDatabaseKey(hex),
          throwsStateError,
        );

        expect(storageStub._store[kDatabaseKeyStorageKey], '11' * 32);
        expect(
          storageStub._store[stagingSlot],
          hex,
          reason: 'staging must remain available for next-boot recovery',
        );
      },
    );

    test(
      'promoteStagingSyncDatabaseKey keeps staging when primary write fails',
      () async {
        const stagingSlot = '${kSyncDatabaseKeyStorageKey}_staging';
        storageStub._store[kSyncDatabaseKeyStorageKey] = '12' * 32;
        storageStub._store[stagingSlot] = hex;
        storageStub.throwOnWriteKeyQueue[kSyncDatabaseKeyStorageKey] = [
          _cipherException(),
        ];

        await expectLater(
          () => promoteStagingSyncDatabaseKey(hex),
          throwsStateError,
        );

        expect(storageStub._store[kSyncDatabaseKeyStorageKey], '12' * 32);
        expect(storageStub._store[stagingSlot], hex);
      },
    );

    test('ensureLocalSyncDatabaseKey does not report success when migration '
        'write fails', () async {
      final driftKey = '42' * 32;
      storageStub._store[kDatabaseKeyStorageKey] = driftKey;
      storageStub.throwOnWriteKeyQueue[kSyncDatabaseKeyStorageKey] = [
        _cipherException(),
      ];

      await expectLater(ensureLocalSyncDatabaseKey, throwsStateError);

      expect(
        storageStub._store.containsKey(kSyncDatabaseKeyStorageKey),
        isFalse,
      );
    });
  });

  group('rotateDatabaseToKey requires durable staging and primary writes', () {
    late Directory tempDir;
    late _SecureStorageStub storageStub;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_rotate_guard_');
      storageStub = _SecureStorageStub()..setup();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    String hexFor(int fill) => fill.toRadixString(16).padLeft(2, '0') * 32;
    Uint8List bytesFor(int fill) => Uint8List.fromList(List.filled(32, fill));

    Future<AppDatabase> openAppDb(String path, String hexKey) async {
      final db = AppDatabase(
        NativeDatabase(File(path), setup: makeCipherSetup(hexKey)),
      );
      await db.customSelect('SELECT 1').get();
      return db;
    }

    test('staging write failure aborts before PRAGMA rekey', () async {
      final dbPath = '${tempDir.path}/prism.db';
      final oldHex = hexFor(0x31);
      final newBytes = bytesFor(0x32);
      storageStub._store[kDatabaseKeyStorageKey] = oldHex;
      storageStub.throwOnWriteKeyQueue['${kDatabaseKeyStorageKey}_staging'] = [
        _cipherException(),
      ];
      final db = await openAppDb(dbPath, oldHex);

      await expectLater(
        () => rotateDatabaseToKey(db: db, newKey: newBytes),
        throwsStateError,
      );
      await db.close();

      expect(tryOpenEncryptedDb(dbPath, oldHex), isTrue);
      expect(tryOpenEncryptedDb(dbPath, hexFor(0x32)), isFalse);
      expect(
        storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
        isFalse,
      );
    });

    test('primary write failure keeps staging after PRAGMA rekey', () async {
      final dbPath = '${tempDir.path}/prism.db';
      final oldHex = hexFor(0x41);
      final newHex = hexFor(0x42);
      final newBytes = bytesFor(0x42);
      storageStub._store[kDatabaseKeyStorageKey] = oldHex;
      storageStub.throwOnWriteKeyQueue[kDatabaseKeyStorageKey] = [
        _cipherException(),
      ];
      final db = await openAppDb(dbPath, oldHex);

      await expectLater(
        () => rotateDatabaseToKey(db: db, newKey: newBytes),
        throwsStateError,
      );
      await db.close();

      expect(tryOpenEncryptedDb(dbPath, newHex), isTrue);
      expect(tryOpenEncryptedDb(dbPath, oldHex), isFalse);
      expect(storageStub._store[kDatabaseKeyStorageKey], oldHex);
      expect(
        storageStub._store['${kDatabaseKeyStorageKey}_staging'],
        newHex,
        reason: 'next boot needs staging to recover the rekeyed DB',
      );
    });
  });
}
