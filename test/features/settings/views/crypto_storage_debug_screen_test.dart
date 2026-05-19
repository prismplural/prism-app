import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/features/settings/views/crypto_storage_debug_screen.dart';

void main() {
  group('debugFirstVerifiedHexKeyForDatabase', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prism_crypto_debug_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'skips stale primary candidate and chooses a key that opens sync DB',
      () {
        final realKey = _hexKey(0xaa);
        final stalePrimary = _hexKey(0xbb);
        final dbPath = p.join(tempDir.path, 'prism_sync.db');
        _createEncryptedDb(dbPath, realKey);

        final selected = debugFirstVerifiedHexKeyForDatabase(
          dbPath: dbPath,
          candidates: <String?>[stalePrimary, realKey],
        );

        expect(selected, realKey);
      },
    );

    test('returns null when no candidate opens the sync DB', () {
      final realKey = _hexKey(0xcc);
      final dbPath = p.join(tempDir.path, 'prism_sync.db');
      _createEncryptedDb(dbPath, realKey);

      final selected = debugFirstVerifiedHexKeyForDatabase(
        dbPath: dbPath,
        candidates: <String?>[null, '', _hexKey(0xdd)],
      );

      expect(selected, isNull);
    });
  });
}

String _hexKey(int byte) => byte.toRadixString(16).padLeft(2, '0') * 32;

void _createEncryptedDb(String path, String hexKey) {
  final db = raw.sqlite3.open(path);
  try {
    db.execute("PRAGMA key = \"x'$hexKey'\";");
    db.execute('CREATE TABLE sanity (id INTEGER PRIMARY KEY);');
    db.execute('INSERT INTO sanity DEFAULT VALUES;');
  } finally {
    db.close();
  }
}
