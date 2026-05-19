import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:local_auth/local_auth.dart';
import 'package:prism_plurality/core/services/keychain_degraded_state.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

/// Keys used in secure storage for PIN lock.
const _pinHashKey = 'prism.pin_hash';
const _pinSaltKey = 'prism.pin_salt';
const _pinHashVersionKey = 'prism.pin_hash_version';

/// Service for PIN lock and biometric authentication.
class PinLockService {
  PinLockService({
    LocalAuthentication? localAuth,
    KeychainDegradedStateService? degradedState,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _degradedState = degradedState ?? KeychainDegradedStateService();

  final LocalAuthentication _localAuth;
  final KeychainDegradedStateService _degradedState;

  /// Inspect a [SecureReadResult] / [SecureWriteResult] / [SecureDeleteResult]
  /// for a cipher failure and mark the PIN slot as `unreadable` so the
  /// degraded-state banner (§7/§8) can surface a "set a new PIN" prompt on
  /// the next UI traversal. Cipher failures on the PIN slot are terminal —
  /// the blob cannot be decrypted, so the saved PIN is effectively gone.
  Future<void> _markPinUnreadableIfCipher(
    SecureStorageFailure? failure,
    String op,
  ) async {
    if (failure == SecureStorageFailure.cipher) {
      debugPrint(
        '[PIN_LOCK] Cipher failure during $op — marking PIN slot unreadable',
      );
      await _degradedState.updateSlot('pin', SlotState.unreadable);
    }
  }

  // ---------------------------------------------------------------------------
  // PIN hashing
  // ---------------------------------------------------------------------------

  /// Hash a PIN with a salt using SHA-256 (legacy, kept for migration).
  List<int> hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode(salt + pin)).bytes;
  }

  /// Hash a PIN with Argon2id (slow hash, resistant to brute force).
  static List<int> hashPinArgon2id(String pin, String salt) {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    try {
      return hashPinArgon2idBytes(pinBytes, salt);
    } finally {
      pinBytes.fillRange(0, pinBytes.length, 0);
    }
  }

  /// Hash PIN bytes with Argon2id (slow hash, resistant to brute force).
  static List<int> hashPinArgon2idBytes(List<int> pinBytes, String salt) {
    final argon2 = hashlib.Argon2(
      hashLength: 32,
      iterations: 3,
      memorySizeKB: 19456, // 19 MB — mobile-friendly
      parallelism: 1,
      type: hashlib.Argon2Type.argon2id,
      salt: utf8.encode(salt),
    );
    final output = argon2.convert(pinBytes);
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
  ///
  /// Writes version key first so that if a partial write occurs (e.g., app
  /// crash after hash but before salt), verifyStoredPin won't misinterpret
  /// an Argon2id hash as legacy SHA-256.
  Future<void> storePin(String pin) async {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    try {
      await storePinBytes(pinBytes);
    } finally {
      pinBytes.fillRange(0, pinBytes.length, 0);
    }
  }

  /// Store new PIN bytes (hashed with Argon2id) in secure storage.
  ///
  /// Each write is wrapped via [safeSecureWrite] so a platform exception
  /// surfaces as a `SecureWriteResult` rather than escaping; on cipher
  /// failure the PIN slot is marked unreadable so the next launch prompts
  /// the user to set a new PIN (per §8). On successful write the slot is
  /// implicitly recovered — clearing the `unreadable` flag is the caller's
  /// responsibility once they've validated the new PIN end-to-end.
  Future<void> storePinBytes(List<int> pinBytes) async {
    final salt = _generateSalt();
    final hash = hashPinArgon2idBytes(pinBytes, salt);
    final hashBase64 = base64Encode(Uint8List.fromList(hash));
    final v = await safeSecureWrite(_pinHashVersionKey, '2');
    await _markPinUnreadableIfCipher(v.failure, 'storePinBytes:version');
    final h = await safeSecureWrite(_pinHashKey, hashBase64);
    await _markPinUnreadableIfCipher(h.failure, 'storePinBytes:hash');
    final s = await safeSecureWrite(_pinSaltKey, salt);
    await _markPinUnreadableIfCipher(s.failure, 'storePinBytes:salt');
    if (v.ok && h.ok && s.ok) {
      // Restore the slot to healthy — caller's new PIN landed cleanly.
      await _degradedState.updateSlot('pin', SlotState.ok);
    }
  }

  /// Clear the stored PIN.
  ///
  /// Cleanup-style deletes — failures here are non-fatal; the slot is either
  /// already gone or will be overwritten on the next setPin.
  Future<void> clearPin() async {
    await safeSecureDelete(_pinHashKey);
    await safeSecureDelete(_pinSaltKey);
    await safeSecureDelete(_pinHashVersionKey);
  }

  /// Check whether a PIN is currently set.
  ///
  /// Treats a cipher failure as "no PIN" (the slot is effectively gone) and
  /// flags the slot unreadable so the UI can surface the recovery prompt.
  Future<bool> isPinSet() async {
    final read = await safeSecureRead(_pinHashKey);
    await _markPinUnreadableIfCipher(read.failure, 'isPinSet');
    final hash = read.value;
    return hash != null && hash.isNotEmpty;
  }

  /// Verify a PIN attempt against the stored hash.
  ///
  /// Supports both legacy SHA-256 (version 1) and Argon2id (version 2).
  /// On successful legacy verification, automatically migrates to Argon2id.
  ///
  /// A cipher failure reading either slot is reported via the degraded-state
  /// service and treated as "no stored PIN" — the call returns false rather
  /// than propagating the platform exception. The user lands in the
  /// set-new-PIN recovery path on the next launch.
  Future<bool> verifyStoredPin(String pin) async {
    final hashRead = await safeSecureRead(_pinHashKey);
    await _markPinUnreadableIfCipher(hashRead.failure, 'verifyStoredPin:hash');
    final saltRead = await safeSecureRead(_pinSaltKey);
    await _markPinUnreadableIfCipher(saltRead.failure, 'verifyStoredPin:salt');
    final hashBase64 = hashRead.value;
    final salt = saltRead.value;
    if (hashBase64 == null || salt == null) return false;

    final storedHash = base64Decode(hashBase64);
    final versionRead = await safeSecureRead(_pinHashVersionKey);
    await _markPinUnreadableIfCipher(
      versionRead.failure,
      'verifyStoredPin:version',
    );
    final version = versionRead.value;

    if (version == '2') {
      // Argon2id verification — no fallback to SHA-256 since the stored
      // hash is Argon2id format and SHA-256 comparison would always fail.
      try {
        final computed = hashPinArgon2id(pin, salt);
        return _constantTimeEquals(computed, storedHash);
      } catch (_) {
        return false;
      }
    }

    // Legacy SHA-256 verification
    if (!verifyPin(pin, storedHash, salt)) return false;

    // Migration: re-hash with Argon2id on successful legacy verification.
    // Best-effort — retry on next unlock if anything fails.
    try {
      final newHash = hashPinArgon2id(pin, salt);
      final newHashBase64 = base64Encode(Uint8List.fromList(newHash));
      await safeSecureWrite(_pinHashKey, newHashBase64);
      await safeSecureWrite(_pinHashVersionKey, '2');
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
