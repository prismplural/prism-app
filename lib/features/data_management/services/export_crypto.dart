import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Password-based encryption for Prism data exports.
///
/// ## File format
/// ```
/// PRISM2  (6 bytes magic)
/// N       (4 bytes, big-endian uint32 — scrypt cost factor, e.g. 32768)
/// r       (4 bytes, big-endian uint32 — scrypt block size, e.g. 8)
/// p       (4 bytes, big-endian uint32 — scrypt parallelization, e.g. 1)
/// salt    (32 bytes, random)
/// nonce   (12 bytes, random — GCM standard)
/// ciphertext + 16-byte GCM auth tag
/// ```
///
/// Key derivation: scrypt (memory-hard; N=32768, r=8, p=1 ≈ 32 MB RAM).
/// Cipher: AES-256-GCM (authenticated encryption).
///
/// KDF parameters are embedded in the header so future upgrades can read
/// older exports without hardcoding version-specific constants.
class ExportCrypto {
  static const _magic = 'PRISM2';
  static const _saltLength = 32;
  static const _nonceLength = 12; // GCM standard
  static const _keyLength = 32; // AES-256

  // Scrypt parameters — tuned for mobile (~32 MB RAM, ~200 ms)
  static const _scryptN = 32768; // cost factor (2^15)
  static const _scryptR = 8; // block size
  static const _scryptP = 1; // parallelization

  /// Encrypt a JSON string with [password].
  ///
  /// Returns the encrypted bytes in the Prism export format.
  static Uint8List encrypt(String json, String password) {
    final salt = _secureRandom(_saltLength);
    final nonce = _secureRandom(_nonceLength);
    final key = _deriveKey(password, salt);

    final plaintext = utf8.encode(json);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          nonce,
          Uint8List(0), // no additional authenticated data
        ),
      );

    final ciphertext = Uint8List(cipher.getOutputSize(plaintext.length));
    var len = cipher.processBytes(
      Uint8List.fromList(plaintext),
      0,
      plaintext.length,
      ciphertext,
      0,
    );
    len += cipher.doFinal(ciphertext, len);

    // Build output: magic + N + r + p + salt + nonce + ciphertext (with GCM tag)
    final output = BytesBuilder(copy: false);
    output.add(utf8.encode(_magic));
    output.add(_uint32BE(_scryptN));
    output.add(_uint32BE(_scryptR));
    output.add(_uint32BE(_scryptP));
    output.add(salt);
    output.add(nonce);
    output.add(ciphertext.sublist(0, len));
    return output.toBytes();
  }

  /// Decrypt bytes produced by [encrypt] using [password].
  ///
  /// Throws [FormatException] if the magic header is missing or unknown.
  /// Throws [InvalidCipherTextException] if the password is wrong or data is
  /// tampered with (GCM authentication failure).
  static String decrypt(Uint8List data, String password) {
    if (data.length < _magic.length) {
      throw const FormatException('Not a Prism encrypted export');
    }
    final magic = utf8.decode(data.sublist(0, _magic.length));
    if (magic != _magic) {
      throw const FormatException('Not a Prism encrypted export');
    }

    // Header: magic(6) + N(4) + r(4) + p(4) + salt(32) + nonce(12) + ct+tag
    const minLength = 6 + 4 + 4 + 4 + _saltLength + _nonceLength + 16;
    if (data.length < minLength) {
      throw const FormatException('Encrypted export is too short');
    }

    var offset = _magic.length;
    final n = _readUint32BE(data, offset);
    offset += 4;
    final r = _readUint32BE(data, offset);
    offset += 4;
    final p = _readUint32BE(data, offset);
    offset += 4;
    final salt = data.sublist(offset, offset + _saltLength);
    offset += _saltLength;
    final nonce = data.sublist(offset, offset + _nonceLength);
    offset += _nonceLength;
    final ciphertext = data.sublist(offset);

    final key = _deriveKey(password, salt, n: n, r: r, p: p);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );

    final plaintext = Uint8List(cipher.getOutputSize(ciphertext.length));
    var len = cipher.processBytes(
      Uint8List.fromList(ciphertext),
      0,
      ciphertext.length,
      plaintext,
      0,
    );
    len += cipher.doFinal(plaintext, len);

    return utf8.decode(plaintext.sublist(0, len));
  }

  /// Returns `true` when [data] starts with the Prism encrypted export header.
  static bool isEncrypted(Uint8List data) {
    if (data.length < _magic.length) return false;
    try {
      return utf8.decode(data.sublist(0, _magic.length)) == _magic;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// scrypt key derivation. Parameters are read from the file header on
  /// decrypt, so future cost increases don't break existing exports.
  static Uint8List _deriveKey(
    String password,
    Uint8List salt, {
    int n = _scryptN,
    int r = _scryptR,
    int p = _scryptP,
  }) {
    final scrypt = Scrypt()
      ..init(ScryptParameters(n, r, p, _keyLength, salt));
    return scrypt.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _uint32BE(int value) {
    return Uint8List(4)
      ..[0] = (value >> 24) & 0xff
      ..[1] = (value >> 16) & 0xff
      ..[2] = (value >> 8) & 0xff
      ..[3] = value & 0xff;
  }

  static int _readUint32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Generate [length] cryptographically-secure random bytes.
  static Uint8List _secureRandom(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }
}
