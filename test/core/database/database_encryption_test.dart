import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/database_encryption.dart';

// ---------------------------------------------------------------------------
// In-memory FlutterSecureStorage stub (same pattern as biometric_service_test)
// ---------------------------------------------------------------------------

class _SecureStorageStub {
  final _store = <String, String?>{};

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
            _store[key] = value;
            return null;
          case 'read':
            final key = call.arguments['key'] as String;
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
  }
}

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

    setUp(storageStub.setup);
    tearDown(storageStub.teardown);

    test('readStagingDatabaseKeyHex returns null when no staging key exists',
        () async {
      expect(await readStagingDatabaseKeyHex(), isNull);
    });

    test(
        'readStagingDatabaseKeyHex returns null and ignores invalid (short) key',
        () async {
      storageStub._store['${kDatabaseKeyStorageKey}_staging'] = 'tooshort';
      expect(await readStagingDatabaseKeyHex(), isNull);
    });

    test('promoteStagingDatabaseKey writes to primary slot and removes staging',
        () async {
      final hexKey = 'ab' * 32; // 64 lowercase hex chars
      storageStub._store['${kDatabaseKeyStorageKey}_staging'] = hexKey;
      storageStub._store[kDatabaseKeyStorageKey] = 'oldkey${'0' * 58}';

      await promoteStagingDatabaseKey(hexKey);

      expect(storageStub._store[kDatabaseKeyStorageKey], equals(hexKey));
      expect(storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
          isFalse);
    });

    test('discardStagingDatabaseKey removes staging slot only', () async {
      final primaryKey = 'cd' * 32;
      final stagingKey = 'ef' * 32;
      storageStub._store[kDatabaseKeyStorageKey] = primaryKey;
      storageStub._store['${kDatabaseKeyStorageKey}_staging'] = stagingKey;

      await discardStagingDatabaseKey();

      // Primary slot unchanged
      expect(storageStub._store[kDatabaseKeyStorageKey], equals(primaryKey));
      // Staging slot removed
      expect(storageStub._store.containsKey('${kDatabaseKeyStorageKey}_staging'),
          isFalse);
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
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      storageStub.teardown();
    });

    String makeHexKey(int fill) {
      return fill.toRadixString(16).padLeft(2, '0') * 32;
    }

    test('Scenario A: staging key opens DB → promotes staging to primary',
        () async {
      final dbPath = '${tempDir.path}/prism_sync.db';
      final oldKey = makeHexKey(0xaa); // primary slot — stale after crash
      final newKey = makeHexKey(0xbb); // staging slot — rekey succeeded before crash

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
          storageStub._store
              .containsKey('${kSyncDatabaseKeyStorageKey}_staging'),
          isFalse);
    });

    test('Scenario B: staging key does not open DB → staging discarded',
        () async {
      final dbPath = '${tempDir.path}/prism_sync.db';
      final realKey = makeHexKey(0xcc); // DB actually encrypted with this
      final staleKey = makeHexKey(0xdd); // written to staging, rekey never ran

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
          storageStub._store
              .containsKey('${kSyncDatabaseKeyStorageKey}_staging'),
          isFalse);
    });
  });
}
