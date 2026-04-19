import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:prism_plurality/features/data_management/services/data_import_service.dart';
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

    test('resolveBytes works from the isolate-based UI path', () async {
      const json = '{"formatVersion":"1.0","headmates":[]}';
      final encrypted = ExportCrypto.encrypt(json, const [], password);

      final result = await Isolate.run(
        () => DataImportService.resolveBytes(encrypted, password: password),
      );

      expect(result.json, equals(json));
      expect(result.mediaBlobs, isEmpty);
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

  group('ExportCrypto — KDF parameter allowlist', () {
    const plaintext = '{"test":true}';
    const password = 'test-password-for-kdf-tests';

    test('out-of-allowlist N causes FormatException before scrypt runs', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final tampered = Uint8List.fromList(encrypted);
      // N is at bytes 6-9 (big-endian uint32). Set to 2^30 = 0x40000000.
      tampered[6] = 0x40;
      tampered[7] = 0x00;
      tampered[8] = 0x00;
      tampered[9] = 0x00;
      expect(
        () => ExportCrypto.decrypt(tampered, password),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('KDF'),
          ),
        ),
      );
    });

    test('out-of-allowlist r causes FormatException', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final tampered = Uint8List.fromList(encrypted);
      // r is at bytes 10-13. Set to 99.
      tampered[10] = 0x00;
      tampered[11] = 0x00;
      tampered[12] = 0x00;
      tampered[13] = 0x63;
      expect(
        () => ExportCrypto.decrypt(tampered, password),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ExportCrypto — trailing bytes', () {
    const plaintext = '{"test":true}';
    const password = 'test-password-for-trailing-tests';

    test('trailing bytes after media section cause FormatException', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final withTrailing = Uint8List.fromList([...encrypted, 0xde, 0xad]);
      expect(
        () => ExportCrypto.decrypt(withTrailing, password),
        throwsA(isA<FormatException>()),
      );
    });

    test('single trailing byte causes FormatException', () {
      final encrypted = ExportCrypto.encrypt(plaintext, const [], password);
      final withTrailing = Uint8List.fromList([...encrypted, 0x00]);
      expect(
        () => ExportCrypto.decrypt(withTrailing, password),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
