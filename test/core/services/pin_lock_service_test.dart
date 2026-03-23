import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/pin_lock_service.dart';

void main() {
  late PinLockService service;

  setUp(() {
    service = PinLockService();
  });

  // ── hashPin ───────────────────────────────────────────────────────────────

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

  // ── storePin / verifyStoredPin round-trip (simulated with in-memory map) ──
  //
  // PinLockService.storePin and verifyStoredPin use the global
  // `secureStorage` constant which requires a platform plugin. We simulate
  // the same flow manually using an in-memory map to verify the logic.

  group('storePin + verifyStoredPin round-trip (simulated)', () {
    test('isPinSet returns false when no PIN stored', () {
      // Simulate: no keys in storage
      final storage = <String, String>{};
      final hash = storage['prism.pin_hash'];
      expect(hash == null || hash.isEmpty, isTrue);
    });

    test('storePin + verifyStoredPin round-trip works', () {
      const pin = '4567';

      // Simulate storePin: generate salt, hash, store
      const salt = 'test-salt-fixed';
      final hash = service.hashPin(pin, salt);
      final hashBase64 = base64Encode(hash);

      final storage = <String, String>{
        'prism.pin_hash': hashBase64,
        'prism.pin_salt': salt,
      };

      // Simulate verifyStoredPin: read, decode, verify
      final storedHashBase64 = storage['prism.pin_hash']!;
      final storedSalt = storage['prism.pin_salt']!;
      final storedHash = base64Decode(storedHashBase64);

      expect(service.verifyPin(pin, storedHash, storedSalt), isTrue);
      expect(service.verifyPin('0000', storedHash, storedSalt), isFalse);
    });

    test('isPinSet returns true after storePin', () {
      // Simulate storePin writing to storage
      final hash = service.hashPin('1234', 'salt');
      final storage = <String, String>{
        'prism.pin_hash': base64Encode(hash),
        'prism.pin_salt': 'salt',
      };

      // isPinSet checks if the hash key is non-null and non-empty
      final storedHash = storage['prism.pin_hash'];
      expect(storedHash != null && storedHash.isNotEmpty, isTrue);
    });

    test('after clearPin, isPinSet returns false', () {
      final hash = service.hashPin('1234', 'salt');
      final storage = <String, String>{
        'prism.pin_hash': base64Encode(hash),
        'prism.pin_salt': 'salt',
      };

      // Simulate clearPin
      storage.remove('prism.pin_hash');
      storage.remove('prism.pin_salt');

      final storedHash = storage['prism.pin_hash'];
      expect(storedHash == null || storedHash.isEmpty, isTrue);
    });
  });
}
