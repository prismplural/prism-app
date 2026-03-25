import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/database_encryption.dart';

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

    String _generateHexKey() {
      final rng = Random.secure();
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = rng.nextInt(256);
      }
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }

    test('fresh encrypted DB can round-trip data', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = _generateHexKey();

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
      final hexKey = _generateHexKey();

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
      final hexKey = _generateHexKey();
      final wrongKey = _generateHexKey();

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

    test('plaintext DB can be migrated to encrypted', () async {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = _generateHexKey();
      final dbFile = File(dbPath);

      // Create plaintext DB with data
      final db = raw.sqlite3.open(dbPath);
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);');
      db.execute("INSERT INTO test (id, value) VALUES (1, 'migrated');");
      db.close();

      // Migrate to encrypted
      final result = await migratePlaintextToEncrypted(
        dbFile: dbFile,
        hexKey: hexKey,
      );
      expect(result, isTrue);

      // Verify data survived migration
      final db2 = raw.sqlite3.open(dbPath);
      db2.execute("PRAGMA key = \"x'$hexKey'\";");
      final rows = db2.select('SELECT value FROM test WHERE id = 1;');
      expect(rows.first['value'], 'migrated');
      db2.close();

      // Verify it's not readable without key
      final db3 = raw.sqlite3.open(dbPath);
      expect(
        () => db3.select('SELECT count(*) FROM sqlite_master;'),
        throwsA(anything),
      );
      db3.close();
    });

    test('migration of nonexistent file returns true', () async {
      final dbFile = File('${tempDir.path}/nonexistent.db');
      final hexKey = _generateHexKey();

      final result = await migratePlaintextToEncrypted(
        dbFile: dbFile,
        hexKey: hexKey,
      );
      expect(result, isTrue);
    });

    test('_tryOpenEncrypted-style probe succeeds with correct key', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = _generateHexKey();

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

    test('_tryOpenPlaintext-style probe succeeds on plaintext DB', () {
      final dbPath = '${tempDir.path}/test.db';

      // Create plaintext DB
      final db = raw.sqlite3.open(dbPath);
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY);');
      db.close();

      // Probe as plaintext
      bool readable = false;
      try {
        final probe = raw.sqlite3.open(dbPath);
        try {
          probe.select('SELECT count(*) FROM sqlite_master;');
          readable = true;
        } finally {
          probe.close();
        }
      } catch (_) {}
      expect(readable, isTrue);
    });

    test('_tryOpenPlaintext-style probe fails on encrypted DB', () {
      final dbPath = '${tempDir.path}/test.db';
      final hexKey = _generateHexKey();

      // Create encrypted DB
      final db = raw.sqlite3.open(dbPath);
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.execute('CREATE TABLE test (id INTEGER PRIMARY KEY);');
      db.close();

      // Probe as plaintext — should fail
      bool readable = false;
      try {
        final probe = raw.sqlite3.open(dbPath);
        try {
          probe.select('SELECT count(*) FROM sqlite_master;');
          readable = true;
        } finally {
          probe.close();
        }
      } catch (_) {}
      expect(readable, isFalse);
    });
  });
}
