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
              // Android: AES-GCM key in Android Keystore with
              // setUserAuthenticationRequired(true) — reading (and writing)
              // the item requires a biometric/PIN prompt. This is the closest
              // Android analog to iOS biometryCurrentSet. Requires API 28+.
              //
              // resetOnError: true — if the key is permanently invalidated
              // (user enrolled a new fingerprint or removed all biometrics),
              // the stored DEK is cleared and authenticate() returns null.
              // The caller should fall back to PIN entry; the user can
              // re-enroll biometrics in settings after unlocking with PIN.
              //
              // Note: enforceBiometrics: true throws if no biometric or device
              // credential is enrolled. isAvailable() must be checked before
              // calling enroll() or the write will fail.
              aOptions: AndroidOptions.biometric(
                enforceBiometrics: true,
                resetOnError: true,
                biometricPromptTitle: 'Unlock Prism',
                biometricPromptSubtitle:
                    'Use your fingerprint or face to continue',
              ),
            );

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _storage;

  static const _bioKey = 'prism_sync.biometric_dek';

  Future<bool> isAvailable() async {
    // Both checks required: canCheckBiometrics is true even on devices where
    // biometric hardware exists but nothing is enrolled. isDeviceSupported()
    // confirms the device can actually perform biometric auth.
    final canCheck = await _localAuth.canCheckBiometrics;
    final supported = await _localAuth.isDeviceSupported();
    return canCheck && supported;
  }

  /// Enroll: write DEK to biometric-protected storage.
  /// iOS: writing does NOT require biometric — only reading does (Secure Enclave).
  /// Android: writing DOES trigger a biometric/PIN prompt (enforceBiometrics).
  /// Call isAvailable() before this to avoid a throw on devices with no
  /// enrolled biometric or device credential.
  Future<void> enroll(Uint8List dekBytes) async {
    await _storage.write(key: _bioKey, value: base64Encode(dekBytes));
  }

  /// Authenticate: reading the stored DEK triggers Face ID/Touch ID (iOS) or
  /// fingerprint/face prompt (Android). Returns null on cancellation, failure,
  /// or if the key was permanently invalidated by a biometric enrollment change
  /// (resetOnError cleared the stored value). Callers must fall back to PIN.
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

  /// Whether a biometric-protected DEK is stored.
  /// WARNING: On Android, this triggers a biometric/PIN prompt because the
  /// read path is protected by enforceBiometrics. Do not use this for
  /// UI enrollment-state checks — use a separate SharedPreferences flag.
  Future<bool> isEnrolled() async {
    final b64 = await _storage.read(key: _bioKey);
    return b64 != null;
  }
}
