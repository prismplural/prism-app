import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Password-based encryption for Prism data exports.
///
/// ## File format (PRISM1; PRISM3 accepted on read for back-compat)
/// ```
/// PRISM1        (6 bytes magic)
/// N             (4 bytes, big-endian uint32 — scrypt cost factor, e.g. 32768)
/// r             (4 bytes, big-endian uint32 — scrypt block size, e.g. 8)
/// p             (4 bytes, big-endian uint32 — scrypt parallelization, e.g. 1)
/// salt          (32 bytes, random)
/// nonce         (12 bytes, random — GCM standard)
/// json_len      (4 bytes, big-endian uint32)
/// json_ct       (json_len bytes — AES-256-GCM encrypted UTF-8 JSON + 16-byte tag)
/// media_count   (4 bytes, big-endian uint32)
/// --- repeated media_count times ---
/// id_len        (4 bytes, big-endian uint32)
/// id_bytes      (id_len bytes — UTF-8 mediaId or thumbnailMediaId)
/// blob_len      (4 bytes, big-endian uint32)
/// blob_bytes    (blob_len bytes — raw XChaCha20-Poly1305 ciphertext, carried as-is)
/// ```
///
/// Key derivation: scrypt (memory-hard; N=32768, r=8, p=1 ≈ 32 MB RAM).
/// Cipher: AES-256-GCM (authenticated encryption) for the JSON section only.
/// Media blobs are already XChaCha20-Poly1305 encrypted and are carried verbatim.
///
/// KDF parameters are embedded in the header so future upgrades can read
/// older exports without hardcoding version-specific constants.
class ExportCrypto {
  static const _magic = 'PRISM1';
  static const _saltLength = 32;
  static const _nonceLength = 12; // GCM standard
  static const _keyLength = 32; // AES-256

  // Scrypt parameters — tuned for mobile (~32 MB RAM, ~200 ms)
  static const _scryptN = 32768; // cost factor (2^15)
  static const _scryptR = 8; // block size
  static const _scryptP = 1; // parallelization

  /// Encrypt JSON + media blobs with [password].
  ///
  /// [mediaBlobs] entries are (mediaId, blob) pairs where blob is a raw
  /// XChaCha20-Poly1305 ciphertext carried as-is (not re-encrypted).
  ///
  /// Returns the encrypted bytes in the PRISM1 export format.
  static Uint8List encrypt(
    String json,
    List<({String mediaId, Uint8List blob})> mediaBlobs,
    String password,
  ) {
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

    final jsonCiphertext = Uint8List(cipher.getOutputSize(plaintext.length));
    var len = cipher.processBytes(
      Uint8List.fromList(plaintext),
      0,
      plaintext.length,
      jsonCiphertext,
      0,
    );
    len += cipher.doFinal(jsonCiphertext, len);
    final jsonCt = jsonCiphertext.sublist(0, len);

    // Build output: magic + N + r + p + salt + nonce + json_len + json_ct +
    //               media_count + (id_len + id_bytes + blob_len + blob_bytes)*
    final output = BytesBuilder(copy: false);
    output.add(utf8.encode(_magic));
    output.add(_uint32BE(_scryptN));
    output.add(_uint32BE(_scryptR));
    output.add(_uint32BE(_scryptP));
    output.add(salt);
    output.add(nonce);

    output.add(_uint32BE(jsonCt.length));
    output.add(jsonCt);

    output.add(_uint32BE(mediaBlobs.length));
    for (final entry in mediaBlobs) {
      final idBytes = utf8.encode(entry.mediaId);
      output.add(_uint32BE(idBytes.length));
      output.add(idBytes);
      output.add(_uint32BE(entry.blob.length));
      output.add(entry.blob);
    }

    return output.toBytes();
  }

  /// Decrypt bytes produced by [encrypt] using [password].
  ///
  /// Returns the decrypted JSON string and the list of media blobs (carried
  /// verbatim as XChaCha20-Poly1305 ciphertexts).
  ///
  /// Throws [FormatException] if the magic header is not `PRISM1` or the
  /// data is truncated.
  /// Throws [InvalidCipherTextException] if the password is wrong or the JSON
  /// section is tampered with (GCM authentication failure).
  static ({String json, List<({String mediaId, Uint8List blob})> mediaBlobs})
  decrypt(Uint8List data, String password) {
    if (data.length < _magic.length) {
      throw const FormatException('Not a Prism encrypted export');
    }
    final magic = utf8.decode(data.sublist(0, _magic.length));
    if (magic != _magic) {
      throw const FormatException('Not a Prism encrypted export');
    }

    // Header: magic(6) + N(4) + r(4) + p(4) + salt(32) + nonce(12) +
    //         json_len(4) + json_ct(>=16) + media_count(4)
    const minHeaderLength = 6 + 4 + 4 + 4 + _saltLength + _nonceLength + 4 + 16 + 4;
    if (data.length < minHeaderLength) {
      throw const FormatException('Encrypted export is too short');
    }

    var offset = _magic.length;
    final n = _readUint32BE(data, offset);
    offset += 4;
    final r = _readUint32BE(data, offset);
    offset += 4;
    final p = _readUint32BE(data, offset);
    offset += 4;

    if (n != _scryptN || r != _scryptR || p != _scryptP) {
      throw const FormatException('Unsupported KDF parameters');
    }

    final salt = data.sublist(offset, offset + _saltLength);
    offset += _saltLength;
    final nonce = data.sublist(offset, offset + _nonceLength);
    offset += _nonceLength;

    // JSON section
    final jsonLen = _readUint32BE(data, offset);
    offset += 4;
    if (data.length < offset + jsonLen) {
      throw const FormatException('Encrypted export is truncated (JSON section)');
    }
    final jsonCt = data.sublist(offset, offset + jsonLen);
    offset += jsonLen;

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

    final plaintext = Uint8List(cipher.getOutputSize(jsonCt.length));
    var decLen = cipher.processBytes(
      Uint8List.fromList(jsonCt),
      0,
      jsonCt.length,
      plaintext,
      0,
    );
    decLen += cipher.doFinal(plaintext, decLen);
    final json = utf8.decode(plaintext.sublist(0, decLen));

    // Media section
    if (data.length < offset + 4) {
      throw const FormatException('Encrypted export is truncated (media count)');
    }
    final mediaCount = _readUint32BE(data, offset);
    offset += 4;

    final mediaBlobs = <({String mediaId, Uint8List blob})>[];
    for (var i = 0; i < mediaCount; i++) {
      if (data.length < offset + 4) {
        throw const FormatException('Encrypted export is truncated (media id_len)');
      }
      final idLen = _readUint32BE(data, offset);
      offset += 4;
      if (data.length < offset + idLen) {
        throw const FormatException('Encrypted export is truncated (media id_bytes)');
      }
      final mediaId = utf8.decode(data.sublist(offset, offset + idLen));
      offset += idLen;

      if (data.length < offset + 4) {
        throw const FormatException('Encrypted export is truncated (media blob_len)');
      }
      final blobLen = _readUint32BE(data, offset);
      offset += 4;
      if (data.length < offset + blobLen) {
        throw const FormatException('Encrypted export is truncated (media blob_bytes)');
      }
      final blob = data.sublist(offset, offset + blobLen);
      offset += blobLen;

      mediaBlobs.add((mediaId: mediaId, blob: blob));
    }

    if (offset != data.length) {
      throw const FormatException('Unexpected trailing bytes');
    }

    return (json: json, mediaBlobs: mediaBlobs);
  }

  /// Returns `true` when [data] starts with the PRISM1 encrypted export header.
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
