import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:prism_plurality/core/services/media/hashing_helper.dart';
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
  MediaEncryptionService({HashBytesFn hashBytes = productionHasher})
    : _hashBytes = hashBytes;

  /// Hashing strategy for media integrity digests.
  ///
  /// Defaults to [productionHasher], which runs large payloads off the UI
  /// isolate. Tests inject a recording fake to assert which payloads are routed
  /// through the production hasher.
  final HashBytesFn _hashBytes;

  /// The production hasher and the constructor default, exposed so tests can
  /// assert the default wiring routes large payloads off the UI isolate.
  @visibleForTesting
  static const HashBytesFn productionHasher = hashBytesForIntegrity;

  Future<EncryptedMedia> encryptMedia(Uint8List plaintext) async {
    final key = await ffi.randomBytes(len: 32);
    final plaintextHash = await _hashBytes(plaintext);
    final ciphertext = await ffi.encryptXchacha(key: key, plaintext: plaintext);
    final ciphertextHash = await _hashBytes(ciphertext);

    return EncryptedMedia(
      ciphertext: ciphertext,
      key: key,
      plaintextHash: plaintextHash,
      ciphertextHash: ciphertextHash,
    );
  }

  Future<EncryptedMedia> encryptMediaWithKey(
    Uint8List plaintext,
    Uint8List key,
  ) async {
    final plaintextHash = await _hashBytes(plaintext);
    final ciphertext = await ffi.encryptXchacha(key: key, plaintext: plaintext);
    final ciphertextHash = await _hashBytes(ciphertext);

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
    final actualCiphertextHash = await _hashBytes(ciphertext);
    if (actualCiphertextHash != expectedCiphertextHash) {
      throw StateError(
        'Ciphertext hash mismatch: expected $expectedCiphertextHash, '
        'got $actualCiphertextHash',
      );
    }

    // NOTE: this flutter_rust_bridge call must stay on the caller's isolate.
    // FRB manages its own Dart isolate and fails when invoked from an isolate it
    // did not spawn ("Cannot use native extensions from an isolate not spawned
    // by the VM"), so encrypt/decrypt are never moved to a compute isolate. Only
    // the pure-Dart SHA-256 work above and below is safe to move, and it is
    // moved inside [hashBytesForIntegrity].
    final plaintext = await ffi.decryptXchacha(
      key: key,
      ciphertext: ciphertext,
    );

    final actualPlaintextHash = await _hashBytes(plaintext);
    if (actualPlaintextHash != expectedPlaintextHash) {
      throw StateError(
        'Plaintext hash mismatch: expected $expectedPlaintextHash, '
        'got $actualPlaintextHash',
      );
    }

    return plaintext;
  }
}
