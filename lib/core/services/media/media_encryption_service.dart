import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

class EncryptedMedia {
  final Uint8List ciphertext;
  final Uint8List key;
  final String plaintextHash;
  final String ciphertextHash;

  const EncryptedMedia({
    required this.ciphertext,
    required this.key,
    required this.plaintextHash,
    required this.ciphertextHash,
  });
}

class MediaEncryptionService {
  Future<EncryptedMedia> encryptMedia(Uint8List plaintext) async {
    final key = await ffi.randomBytes(len: 32);
    final plaintextHash = sha256.convert(plaintext).toString();
    final ciphertext = await ffi.encryptXchacha(
      key: key,
      plaintext: plaintext,
    );
    final ciphertextHash = sha256.convert(ciphertext).toString();

    return EncryptedMedia(
      ciphertext: ciphertext,
      key: key,
      plaintextHash: plaintextHash,
      ciphertextHash: ciphertextHash,
    );
  }

  Future<Uint8List> decryptMedia({
    required Uint8List ciphertext,
    required Uint8List key,
    required String expectedCiphertextHash,
    required String expectedPlaintextHash,
  }) async {
    final actualCiphertextHash = sha256.convert(ciphertext).toString();
    if (actualCiphertextHash != expectedCiphertextHash) {
      throw StateError(
        'Ciphertext hash mismatch: expected $expectedCiphertextHash, '
        'got $actualCiphertextHash',
      );
    }

    final plaintext = await ffi.decryptXchacha(
      key: key,
      ciphertext: ciphertext,
    );

    final actualPlaintextHash = sha256.convert(plaintext).toString();
    if (actualPlaintextHash != expectedPlaintextHash) {
      throw StateError(
        'Plaintext hash mismatch: expected $expectedPlaintextHash, '
        'got $actualPlaintextHash',
      );
    }

    return plaintext;
  }
}
