import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/media_encryption_service.dart';

void main() {
  late MediaEncryptionService service;

  setUp(() {
    service = MediaEncryptionService();
  });

  // ── EncryptedMedia constructor ─────────────────────────────────────────

  group('EncryptedMedia', () {
    test('stores all fields correctly', () {
      final em = EncryptedMedia(
        ciphertext: Uint8List.fromList([1, 2, 3]),
        key: Uint8List.fromList([4, 5, 6]),
        plaintextHash: 'pt-hash',
        ciphertextHash: 'ct-hash',
      );
      expect(em.ciphertext, Uint8List.fromList([1, 2, 3]));
      expect(em.key, Uint8List.fromList([4, 5, 6]));
      expect(em.plaintextHash, 'pt-hash');
      expect(em.ciphertextHash, 'ct-hash');
    });
  });

  // ── decryptMedia: ciphertext hash verification ─────────────────────────
  //
  // The SHA-256 hash check in decryptMedia happens BEFORE the FFI call to
  // ffi.decryptXchacha. We can exercise this pure-Dart logic without FFI.

  group('decryptMedia ciphertext hash verification', () {
    test('throws StateError when ciphertext hash does not match', () async {
      final ciphertext = Uint8List.fromList([10, 20, 30, 40, 50]);
      const wrongHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

      expect(
        () => service.decryptMedia(
          ciphertext: ciphertext,
          key: Uint8List(32),
          expectedCiphertextHash: wrongHash,
          expectedPlaintextHash: 'does-not-matter',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Ciphertext hash mismatch'),
          ),
        ),
      );
    });

    test('error message includes expected and actual hashes', () async {
      final ciphertext = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final actualHash = sha256.convert(ciphertext).toString();
      const expectedHash = '0000000000000000000000000000000000000000000000000000000000000000';

      try {
        await service.decryptMedia(
          ciphertext: ciphertext,
          key: Uint8List(32),
          expectedCiphertextHash: expectedHash,
          expectedPlaintextHash: 'irrelevant',
        );
        fail('Should have thrown');
      } on StateError catch (e) {
        expect(e.message, contains(expectedHash));
        expect(e.message, contains(actualHash));
      }
    });

    test('correct ciphertext hash passes check and reaches FFI call', () async {
      final ciphertext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final correctHash = sha256.convert(ciphertext).toString();

      // With the correct hash the code proceeds past the hash check and
      // calls ffi.decryptXchacha, which will fail in a unit test context
      // with a MissingPluginException (or similar FFI error).
      // The important thing: it does NOT throw a StateError about hash mismatch.
      try {
        await service.decryptMedia(
          ciphertext: ciphertext,
          key: Uint8List(32),
          expectedCiphertextHash: correctHash,
          expectedPlaintextHash: 'any',
        );
        fail('Expected an error from FFI call');
      } on StateError catch (e) {
        // If we get a StateError, it must NOT be the hash mismatch one.
        expect(e.message, isNot(contains('Ciphertext hash mismatch')));
      } catch (e) {
        // Any non-StateError exception is fine — it means we got past the
        // hash check and the FFI call failed as expected in a test env.
        expect(e, isNotNull);
      }
    });

    test('empty ciphertext has a valid SHA-256 hash', () async {
      final empty = Uint8List(0);
      final emptyHash = sha256.convert(empty).toString();

      // SHA-256 of empty input is well-known:
      // e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      expect(emptyHash, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');

      // With the correct hash for empty data, should pass the hash check.
      try {
        await service.decryptMedia(
          ciphertext: empty,
          key: Uint8List(32),
          expectedCiphertextHash: emptyHash,
          expectedPlaintextHash: 'any',
        );
        fail('Expected an error from FFI call');
      } on StateError catch (e) {
        expect(e.message, isNot(contains('Ciphertext hash mismatch')));
      } catch (_) {
        // FFI error expected
      }
    });
  });

  // ── SHA-256 consistency (used by the service) ──────────────────────────

  group('SHA-256 hashing (used by service internals)', () {
    test('produces deterministic output', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash1 = sha256.convert(data).toString();
      final hash2 = sha256.convert(data).toString();
      expect(hash1, equals(hash2));
    });

    test('produces different output for different data', () {
      final hash1 = sha256.convert(Uint8List.fromList([1, 2, 3])).toString();
      final hash2 = sha256.convert(Uint8List.fromList([4, 5, 6])).toString();
      expect(hash1, isNot(equals(hash2)));
    });

    test('produces 64-character lowercase hex string', () {
      final hash = sha256.convert(Uint8List.fromList([42])).toString();
      expect(hash.length, 64);
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  // ── encryptMedia requires FFI (smoke-test that it fails gracefully) ───

  group('encryptMedia', () {
    test('fails without FFI runtime (expected in unit tests)', () async {
      // encryptMedia immediately calls ffi.randomBytes which needs the Rust
      // runtime. We just verify it throws rather than hanging.
      expect(
        () => service.encryptMedia(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
    });
  });
}
