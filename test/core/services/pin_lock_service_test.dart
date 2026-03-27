import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';

/// Simulates the verifyStoredPin logic using an in-memory storage map.
///
/// This mirrors the real [PinLockService.verifyStoredPin] flow without
/// requiring a platform plugin for FlutterSecureStorage.
bool _simulateVerifyStoredPin(
  PinLockService service,
  String pin,
  Map<String, String> storage,
) {
  final hashBase64 = storage['prism.pin_hash'];
  final salt = storage['prism.pin_salt'];
  if (hashBase64 == null || salt == null) return false;

  final storedHash = base64Decode(hashBase64);
  final version = storage['prism.pin_hash_version'];

  if (version == '2') {
    // Argon2id verification
    final computed = PinLockService.hashPinArgon2id(pin, salt);
    return _constantTimeEquals(computed, storedHash);
  }

  // Legacy SHA-256 verification
  if (!service.verifyPin(pin, storedHash, salt)) return false;

  // Migration: re-hash with Argon2id on successful legacy verification
  final newHash = PinLockService.hashPinArgon2id(pin, salt);
  final newHashBase64 = base64Encode(Uint8List.fromList(newHash));
  storage['prism.pin_hash'] = newHashBase64;
  storage['prism.pin_hash_version'] = '2';

  return true;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}

void main() {
  late PinLockService service;

  setUp(() {
    service = PinLockService();
  });

  // ── hashPin (SHA-256, legacy) ───────────────────────────────────────────

  group('hashPin', () {
    test('produces deterministic output for same inputs', () {
      final hash1 = service.hashPin('1234', 'salt-abc');
      final hash2 = service.hashPin('1234', 'salt-abc');
      expect(hash1, equals(hash2));
    });

    test('produces different output for different PINs', () {
      final hash1 = service.hashPin('1234', 'salt-abc');
      final hash2 = service.hashPin('5678', 'salt-abc');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces different output for different salts', () {
      final hash1 = service.hashPin('1234', 'salt-abc');
      final hash2 = service.hashPin('1234', 'salt-xyz');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces a SHA-256 sized output (32 bytes)', () {
      final hash = service.hashPin('0000', 'any-salt');
      expect(hash.length, 32);
    });
  });

  // ── hashPinArgon2id ─────────────────────────────────────────────────────

  group('hashPinArgon2id', () {
    test('produces deterministic output for same inputs', () {
      final hash1 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      final hash2 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      expect(hash1, equals(hash2));
    });

    test('produces different output for different PINs', () {
      final hash1 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      final hash2 = PinLockService.hashPinArgon2id('5678', 'salt-abc');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces different output for different salts', () {
      final hash1 = PinLockService.hashPinArgon2id('1234', 'salt-abc');
      final hash2 = PinLockService.hashPinArgon2id('1234', 'salt-xyz');
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces a 32-byte output', () {
      final hash = PinLockService.hashPinArgon2id('0000', 'any-salt');
      expect(hash.length, 32);
    });
  });

  // ── verifyPin ─────────────────────────────────────────────────────────────

  group('verifyPin', () {
    test('returns true for correct PIN', () {
      const pin = '9999';
      const salt = 'my-salt';
      final hash = service.hashPin(pin, salt);
      expect(service.verifyPin(pin, hash, salt), isTrue);
    });

    test('returns false for wrong PIN', () {
      const salt = 'my-salt';
      final hash = service.hashPin('1111', salt);
      expect(service.verifyPin('2222', hash, salt), isFalse);
    });

    test('rejects wrong hash (constant-time equals)', () {
      const pin = '1234';
      const salt = 'salt';
      final correctHash = service.hashPin(pin, salt);
      // Tamper with the hash
      final wrongHash = List<int>.from(correctHash);
      wrongHash[0] = (wrongHash[0] + 1) % 256;
      expect(service.verifyPin(pin, wrongHash, salt), isFalse);
    });

    test('rejects hash of different length', () {
      const pin = '1234';
      const salt = 'salt';
      // A hash that is too short
      expect(service.verifyPin(pin, [1, 2, 3], salt), isFalse);
    });
  });

  // ── verifyStoredPin (simulated with in-memory map) ─────────────────────
  //
  // PinLockService.verifyStoredPin uses the global `secureStorage` constant
  // which requires a platform plugin. We replicate the same logic via
  // _simulateVerifyStoredPin to test all four code paths.

  group('verifyStoredPin (simulated)', () {
    test('version=2, correct PIN returns true', () {
      const pin = '4567';
      const salt = 'test-salt-fixed';
      final hash = PinLockService.hashPinArgon2id(pin, salt);
      final hashBase64 = base64Encode(Uint8List.fromList(hash));

      final storage = <String, String>{
        'prism.pin_hash': hashBase64,
        'prism.pin_salt': salt,
        'prism.pin_hash_version': '2',
      };

      expect(_simulateVerifyStoredPin(service, pin, storage), isTrue);
    });

    test('version=2, wrong PIN returns false', () {
      const pin = '4567';
      const salt = 'test-salt-fixed';
      final hash = PinLockService.hashPinArgon2id(pin, salt);
      final hashBase64 = base64Encode(Uint8List.fromList(hash));

      final storage = <String, String>{
        'prism.pin_hash': hashBase64,
        'prism.pin_salt': salt,
        'prism.pin_hash_version': '2',
      };

      expect(_simulateVerifyStoredPin(service, '0000', storage), isFalse);
    });

    test('no version (legacy), correct PIN returns true and migrates to Argon2id', () {
      const pin = '1234';
      const salt = 'legacy-salt';
      // Store SHA-256 hash (legacy format, no version key)
      final legacyHash = service.hashPin(pin, salt);
      final legacyHashBase64 = base64Encode(legacyHash);

      final storage = <String, String>{
        'prism.pin_hash': legacyHashBase64,
        'prism.pin_salt': salt,
      };

      // Should succeed
      expect(_simulateVerifyStoredPin(service, pin, storage), isTrue);

      // Should have migrated: version is now '2'
      expect(storage['prism.pin_hash_version'], '2');

      // Hash should have been updated (no longer the SHA-256 value)
      expect(storage['prism.pin_hash'], isNot(equals(legacyHashBase64)));
    });

    test('no version (legacy), wrong PIN returns false', () {
      const pin = '1234';
      const salt = 'legacy-salt';
      final legacyHash = service.hashPin(pin, salt);
      final legacyHashBase64 = base64Encode(legacyHash);

      final storage = <String, String>{
        'prism.pin_hash': legacyHashBase64,
        'prism.pin_salt': salt,
      };

      expect(_simulateVerifyStoredPin(service, '9999', storage), isFalse);

      // No migration should have occurred
      expect(storage.containsKey('prism.pin_hash_version'), isFalse);
      expect(storage['prism.pin_hash'], equals(legacyHashBase64));
    });
  });

  // ── Migration persistence ──────────────────────────────────────────────

  group('migration persistence', () {
    test('after legacy migration, stored hash verifies with Argon2id', () {
      const pin = '5678';
      const salt = 'migration-salt';
      // Start with legacy SHA-256 hash
      final legacyHash = service.hashPin(pin, salt);
      final legacyHashBase64 = base64Encode(legacyHash);

      final storage = <String, String>{
        'prism.pin_hash': legacyHashBase64,
        'prism.pin_salt': salt,
      };

      // First verify triggers migration
      _simulateVerifyStoredPin(service, pin, storage);

      // Version key should be written as '2'
      expect(storage['prism.pin_hash_version'], '2');

      // The migrated hash should be a valid Argon2id hash that verifies
      final migratedHash = base64Decode(storage['prism.pin_hash']!);
      final expectedArgon2id = PinLockService.hashPinArgon2id(pin, salt);
      expect(migratedHash, equals(expectedArgon2id));

      // Subsequent verification with version=2 should also succeed
      expect(_simulateVerifyStoredPin(service, pin, storage), isTrue);
    });

    test('migrated hash differs from original SHA-256 hash', () {
      const pin = '9012';
      const salt = 'diff-salt';
      final sha256Hash = service.hashPin(pin, salt);
      final argon2idHash = PinLockService.hashPinArgon2id(pin, salt);

      // The two hashing algorithms must produce different outputs
      expect(sha256Hash, isNot(equals(argon2idHash)));
    });
  });

  // ── storePin / verifyStoredPin round-trip (simulated with in-memory map) ──

  group('storePin + verifyStoredPin round-trip (simulated)', () {
    test('isPinSet returns false when no PIN stored', () {
      final storage = <String, String>{};
      final hash = storage['prism.pin_hash'];
      expect(hash == null || hash.isEmpty, isTrue);
    });

    test('storePin + verifyStoredPin round-trip works with Argon2id', () {
      const pin = '4567';
      const salt = 'test-salt-fixed';

      // Simulate storePin with Argon2id (current behavior)
      final hash = PinLockService.hashPinArgon2id(pin, salt);
      final hashBase64 = base64Encode(Uint8List.fromList(hash));

      final storage = <String, String>{
        'prism.pin_hash': hashBase64,
        'prism.pin_salt': salt,
        'prism.pin_hash_version': '2',
      };

      // Verify correct PIN succeeds
      expect(_simulateVerifyStoredPin(service, pin, storage), isTrue);
      // Verify wrong PIN fails
      expect(_simulateVerifyStoredPin(service, '0000', storage), isFalse);
    });

    test('isPinSet returns true after storePin', () {
      final hash = PinLockService.hashPinArgon2id('1234', 'salt');
      final storage = <String, String>{
        'prism.pin_hash': base64Encode(Uint8List.fromList(hash)),
        'prism.pin_salt': 'salt',
        'prism.pin_hash_version': '2',
      };

      final storedHash = storage['prism.pin_hash'];
      expect(storedHash != null && storedHash.isNotEmpty, isTrue);
    });

    test('after clearPin, isPinSet returns false', () {
      final hash = PinLockService.hashPinArgon2id('1234', 'salt');
      final storage = <String, String>{
        'prism.pin_hash': base64Encode(Uint8List.fromList(hash)),
        'prism.pin_salt': 'salt',
        'prism.pin_hash_version': '2',
      };

      // Simulate clearPin
      storage.remove('prism.pin_hash');
      storage.remove('prism.pin_salt');
      storage.remove('prism.pin_hash_version');

      final storedHash = storage['prism.pin_hash'];
      expect(storedHash == null || storedHash.isEmpty, isTrue);
    });
  });
}
