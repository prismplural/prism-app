import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService({
    LocalAuthentication? localAuth,
    FlutterSecureStorage? storage,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _storage = storage ??
            const FlutterSecureStorage(
              // iOS: AccessControlFlag.biometryCurrentSet stores the item in
              // the Secure Enclave with a biometric access control — the
              // platform requires Face ID/Touch ID to READ the item. This is
              // true hardware-enforced biometric binding, not merely an app-
              // level prompt before a normal keychain write. The item is
              // invalidated if biometric enrollment changes (correct security
              // behaviour).
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
                accessControlFlags: [AccessControlFlag.biometryCurrentSet],
              ),
              // Android: use default Keystore-backed storage (same as the
              // centralized secureStorage instance).
              aOptions: AndroidOptions(),
            );

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _storage;

  static const _bioKey = 'prism_sync.biometric_dek';

  Future<bool> isAvailable() async {
    return _localAuth.canCheckBiometrics;
  }

  /// Enroll: write DEK to biometric-protected keychain item.
  /// iOS: writing does NOT require biometric — only reading does.
  Future<void> enroll(Uint8List dekBytes) async {
    await _storage.write(key: _bioKey, value: base64Encode(dekBytes));
  }

  /// Authenticate: reading the biometric keychain item triggers Face ID/Touch ID.
  /// iOS: platform enforces biometric at read time.
  /// Returns null on cancellation or failure.
  Future<Uint8List?> authenticate() async {
    try {
      final b64 = await _storage.read(key: _bioKey);
      if (b64 == null) return null;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _bioKey);
  }

  Future<bool> isEnrolled() async {
    final b64 = await _storage.read(key: _bioKey);
    return b64 != null;
  }
}
