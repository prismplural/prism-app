import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hashlib/hashlib.dart';
import 'package:local_auth/local_auth.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

/// Keys used in secure storage for PIN lock.
const _pinHashKey = 'prism.pin_hash';
const _pinSaltKey = 'prism.pin_salt';
const _pinHashVersionKey = 'prism.pin_hash_version';

/// Service for PIN lock and biometric authentication.
class PinLockService {
  PinLockService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  // ---------------------------------------------------------------------------
  // PIN hashing
  // ---------------------------------------------------------------------------

  /// Hash a PIN with a salt using SHA-256 (legacy, kept for migration).
  List<int> hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode(salt + pin)).bytes;
  }

  /// Hash a PIN with Argon2id (slow hash, resistant to brute force).
  static List<int> hashPinArgon2id(String pin, String salt) {
    final output = Argon2id(
      hashLength: 32,
      iterations: 3,
      memorySizeKB: 19456, // 19 MB — mobile-friendly
      parallelism: 1,
    ).convert(
      utf8.encode(pin),
      salt: utf8.encode(salt),
    );
    return output.bytes;
  }

  /// Constant-time comparison of two byte lists.
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Verify a PIN against a stored hash and salt.
  bool verifyPin(String pin, List<int> storedHash, String salt) {
    final computed = hashPin(pin, salt);
    return _constantTimeEquals(computed, storedHash);
  }

  // ---------------------------------------------------------------------------
  // Secure storage
  // ---------------------------------------------------------------------------

  /// Generate a random 16-byte salt as hex.
  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Store a new PIN (hashed with Argon2id) in secure storage.
  Future<void> storePin(String pin) async {
    final salt = _generateSalt();
    final hash = hashPinArgon2id(pin, salt);
    final hashBase64 = base64Encode(Uint8List.fromList(hash));
    await secureStorage.write(key: _pinHashKey, value: hashBase64);
    await secureStorage.write(key: _pinSaltKey, value: salt);
    await secureStorage.write(key: _pinHashVersionKey, value: '2');
  }

  /// Clear the stored PIN.
  Future<void> clearPin() async {
    await secureStorage.delete(key: _pinHashKey);
    await secureStorage.delete(key: _pinSaltKey);
    await secureStorage.delete(key: _pinHashVersionKey);
  }

  /// Check whether a PIN is currently set.
  Future<bool> isPinSet() async {
    final hash = await secureStorage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Verify a PIN attempt against the stored hash.
  ///
  /// Supports both legacy SHA-256 (version 1) and Argon2id (version 2).
  /// On successful legacy verification, automatically migrates to Argon2id.
  Future<bool> verifyStoredPin(String pin) async {
    final hashBase64 = await secureStorage.read(key: _pinHashKey);
    final salt = await secureStorage.read(key: _pinSaltKey);
    if (hashBase64 == null || salt == null) return false;

    final storedHash = base64Decode(hashBase64);
    final version = await secureStorage.read(key: _pinHashVersionKey);

    if (version == '2') {
      // Argon2id verification
      try {
        final computed = hashPinArgon2id(pin, salt);
        return _constantTimeEquals(computed, storedHash);
      } catch (_) {
        // Argon2id failed unexpectedly — fall back to legacy
        return verifyPin(pin, storedHash, salt);
      }
    }

    // Legacy SHA-256 verification
    if (!verifyPin(pin, storedHash, salt)) return false;

    // Migration: re-hash with Argon2id on successful legacy verification
    try {
      final newHash = hashPinArgon2id(pin, salt);
      final newHashBase64 = base64Encode(Uint8List.fromList(newHash));
      await secureStorage.write(key: _pinHashKey, value: newHashBase64);
      await secureStorage.write(key: _pinHashVersionKey, value: '2');
    } catch (_) {
      // Migration failed — will retry on next unlock. SHA-256 still works.
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Biometric
  // ---------------------------------------------------------------------------

  /// Check whether the device supports biometric authentication.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Prompt for biometric authentication. Returns true if successful.
  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Prism',
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}
