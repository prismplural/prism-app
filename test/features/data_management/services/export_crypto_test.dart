import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:prism_plurality/features/data_management/services/export_crypto.dart';

void main() {
  group('ExportCrypto — PRISM3 format', () {
    const plaintext = '{"hello":"world","unicode":"日本語"}';
    const password = 'correct-horse-battery-staple-2026';

    test('encrypt/decrypt roundtrip returns original JSON (no media)', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final result = ExportCrypto.decrypt(encrypted, password);
      expect(result.json, equals(plaintext));
      expect(result.mediaBlobs, isEmpty);
    });

    test('encrypt/decrypt roundtrip preserves media blobs', () {
      final blob1 = Uint8List.fromList([1, 2, 3, 4, 5]);
      final blob2 = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
      final mediaBlobs = [
        (mediaId: 'media-uuid-1', blob: blob1),
        (mediaId: 'thumb-uuid-2', blob: blob2),
      ];
      final encrypted = ExportCrypto.encrypt(plaintext, mediaBlobs, password);
      final result = ExportCrypto.decrypt(encrypted, password);
      expect(result.json, equals(plaintext));
      expect(result.mediaBlobs.length, equals(2));
      expect(result.mediaBlobs[0].mediaId, equals('media-uuid-1'));
      expect(result.mediaBlobs[0].blob, equals(blob1));
      expect(result.mediaBlobs[1].mediaId, equals('thumb-uuid-2'));
      expect(result.mediaBlobs[1].blob, equals(blob2));
    });

    test('encrypted output starts with PRISM3 magic', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      expect(utf8.decode(encrypted.sublist(0, 6)), equals('PRISM3'));
    });

    test('encrypted output embeds scrypt parameters', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      // N at offset 6, r at 10, p at 14 (big-endian uint32)
      final n = (encrypted[6] << 24) |
          (encrypted[7] << 16) |
          (encrypted[8] << 8) |
          encrypted[9];
      final r = (encrypted[10] << 24) |
          (encrypted[11] << 16) |
          (encrypted[12] << 8) |
          encrypted[13];
      final p = (encrypted[14] << 24) |
          (encrypted[15] << 16) |
          (encrypted[16] << 8) |
          encrypted[17];
      expect(n, greaterThan(0));
      expect(r, greaterThan(0));
      expect(p, greaterThan(0));
    });

    test(
        'two encryptions of same data produce different ciphertexts (random salt/nonce)',
        () {
      final a = ExportCrypto.encrypt(plaintext, const [], password);
      final b = ExportCrypto.encrypt(plaintext, const [], password);
      expect(a, isNot(equals(b)));
    });

    test('wrong password throws InvalidCipherTextException', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      expect(
        () => ExportCrypto.decrypt(encrypted, 'wrong-password'),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });

    test('tampered ciphertext throws InvalidCipherTextException', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final tampered = Uint8List.fromList(encrypted);
      // PRISM3 layout (no media): header(66) + json_ct + media_count(4).
      // Flip a byte in the GCM tag (last 16 bytes of json_ct = bytes [-20..-5]).
      tampered[tampered.length - 5] ^= 0xff;
      expect(
        () => ExportCrypto.decrypt(tampered, password),
        throwsA(isA<InvalidCipherTextException>()),
      );
    });

    test('truncated data throws FormatException', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final truncated = encrypted.sublist(0, 10);
      expect(
        () => ExportCrypto.decrypt(truncated, password),
        throwsA(isA<FormatException>()),
      );
    });

    test('isEncrypted returns true for PRISM3 output', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      expect(ExportCrypto.isEncrypted(encrypted), isTrue);
    });

    test('isEncrypted returns false for plain JSON', () {
      final plain = Uint8List.fromList(utf8.encode(plaintext));
      expect(ExportCrypto.isEncrypted(plain), isFalse);
    });
  });

  group('ExportCrypto — unsupported and legacy formats', () {
    test('unknown magic header throws FormatException', () {
      final garbage =
          Uint8List.fromList(utf8.encode('PRISM9') + List.filled(60, 0));
      expect(
        () => ExportCrypto.decrypt(garbage, 'any'),
        throwsA(isA<FormatException>()),
      );
    });

    test('PRISM2 (legacy scrypt) magic throws FormatException', () {
      final legacyMagic =
          Uint8List.fromList(utf8.encode('PRISM2') + List.filled(60, 0));
      expect(
        () => ExportCrypto.decrypt(legacyMagic, 'any'),
        throwsA(isA<FormatException>()),
      );
    });

    test('PRISM1 (legacy PBKDF2) magic throws FormatException', () {
      // Old format is no longer supported — no migration path needed since
      // there are no production installs.
      final legacyMagic =
          Uint8List.fromList(utf8.encode('PRISM1') + List.filled(60, 0));
      expect(
        () => ExportCrypto.decrypt(legacyMagic, 'any'),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty input throws FormatException', () {
      expect(
        () => ExportCrypto.decrypt(Uint8List(0), 'any'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
