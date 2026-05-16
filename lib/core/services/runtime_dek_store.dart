import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

import 'package:prism_plurality/core/services/secure_storage.dart';

/// One observed runtime-DEK unwrap failure. Captured by the cache-restore
/// pipeline so the next boot snapshot can include the platform code +
/// message in the diagnostic export.
@immutable
class RuntimeDekUnwrapFailure {
  const RuntimeDekUnwrapFailure({
    required this.classification,
    required this.errorCode,
    required this.errorMessage,
    required this.attempts,
    required this.cachePreserved,
    required this.timestamp,
  });

  final RuntimeDekUnwrapClassification classification;

  /// Platform error code from `PlatformException.code`, or `null` for
  /// non-platform failures (e.g. an unrelated Dart-side throw).
  final String? errorCode;
  final String? errorMessage;

  /// Number of unwrap attempts made for this snapshot's restore flow
  /// (1 = single failure, 2 = transient classification triggered a retry
  /// that also failed).
  final int attempts;

  /// Whether the wrapped cache was kept on disk after this failure (only
  /// terminal codes evict the cache).
  final bool cachePreserved;

  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'classification': classification.name,
    if (errorCode != null) 'error_code': errorCode,
    if (errorMessage != null) 'error_message': errorMessage,
    'attempts': attempts,
    'cache_preserved': cachePreserved,
    'timestamp': timestamp.toIso8601String(),
  };

  factory RuntimeDekUnwrapFailure.fromJson(Map<String, dynamic> json) {
    return RuntimeDekUnwrapFailure(
      classification: RuntimeDekUnwrapClassification.values.firstWhere(
        (c) => c.name == (json['classification'] as String?),
        orElse: () => RuntimeDekUnwrapClassification.unknown,
      ),
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
      attempts: json['attempts'] as int? ?? 1,
      cachePreserved: json['cache_preserved'] as bool? ?? true,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Process-wide registry for the last observed runtime-DEK unwrap
/// failure. Updated by `readCachedRuntimeDekForRestoreCore`; read by the
/// boot-log snapshot path. Cleared on a successful unwrap so the
/// diagnostic accurately reflects the most recent failure.
class RuntimeDekUnwrapFailureRegistry {
  RuntimeDekUnwrapFailureRegistry._();

  static RuntimeDekUnwrapFailure? _last;

  static RuntimeDekUnwrapFailure? get last => _last;

  static void record(RuntimeDekUnwrapFailure failure) {
    _last = failure;
  }

  static void clear() {
    _last = null;
  }
}

/// Classification for a wrapped-DEK unwrap failure. Drives the Dart-side
/// cache eviction policy: `terminal` → discard the wrapped blob (it can
/// never be unwrapped); `transient` → preserve the blob and retry on a
/// later launch (the failure was a device-lock-state race or secure-element
/// flake); `unknown` → preserve conservatively.
///
/// Codes emitted by the platform handlers (see `MainActivity.kt` /
/// `AppDelegate.swift`):
///   Android: `runtime_dek_wrap_terminal`, `runtime_dek_wrap_transient`,
///            `runtime_dek_wrap_failed`.
///   iOS:     `RUNTIME_DEK_WRAP_TERMINAL`, `RUNTIME_DEK_WRAP_TRANSIENT`,
///            `RUNTIME_DEK_WRAP_FAILED`.
enum RuntimeDekUnwrapClassification { terminal, transient, unknown }

RuntimeDekUnwrapClassification classifyRuntimeDekUnwrapError(Object error) {
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    if (code.endsWith('_terminal')) {
      return RuntimeDekUnwrapClassification.terminal;
    }
    if (code.endsWith('_transient')) {
      return RuntimeDekUnwrapClassification.transient;
    }
  }
  return RuntimeDekUnwrapClassification.unknown;
}

/// Device-bound runtime DEK envelope wrapping.
///
/// The returned blob is safe to persist: it is AEAD ciphertext produced with a
/// platform-bound wrapping key. The key is non-exportable on Android Keystore
/// and non-extractable Keychain EC private keys on iOS/macOS; Windows uses
/// DPAPI CurrentUser protection. Linux uses AES-GCM with a wrapping key held
/// in Secret Service through [secureStorage]. All avoid per-launch user auth
/// so sync can restore after the first device unlock / login.
class DeviceBoundRuntimeDekStore {
  const DeviceBoundRuntimeDekStore();

  static const MethodChannel _channel = MethodChannel(
    'com.prism.prism_plurality/runtime_dek_wrap',
  );

  bool get isSupported => isRuntimeDekWrappingPlatformSupported(
    isAndroid: Platform.isAndroid,
    isIOS: Platform.isIOS,
    isMacOS: Platform.isMacOS,
    isWindows: Platform.isWindows,
    isLinux: Platform.isLinux,
  );

  Future<String> wrap(Uint8List dek, {required String aad}) async {
    if (!isSupported) {
      throw UnsupportedError(
        'runtime DEK wrapping is only supported on '
        'Android/iOS/macOS/Windows/Linux',
      );
    }
    if (dek.length != _runtimeDekLength) {
      throw ArgumentError.value(
        dek.length,
        'dek.length',
        'runtime DEK must be $_runtimeDekLength bytes',
      );
    }
    if (Platform.isLinux) {
      return _wrapLinux(dek, aad: aad);
    }
    final wrapped = await _channel.invokeMapMethod<String, dynamic>(
      'wrapRuntimeDek',
      {'dek': dek, 'aad': aad},
    );
    if (wrapped == null) {
      throw StateError('runtime DEK wrapper returned no blob');
    }
    return jsonEncode(wrapped);
  }

  Future<Uint8List> unwrap(String blob, {required String aad}) async {
    if (!isSupported) {
      throw UnsupportedError(
        'runtime DEK unwrap is only supported on '
        'Android/iOS/macOS/Windows/Linux',
      );
    }
    final decoded = jsonDecode(blob);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'runtime DEK wrapper blob must be a JSON object',
      );
    }
    if (Platform.isLinux) {
      return _unwrapLinux(decoded, aad: aad);
    }
    final dek = await _channel.invokeMethod<Uint8List>('unwrapRuntimeDek', {
      ...decoded,
      'aad': aad,
    });
    if (dek == null) {
      throw StateError('runtime DEK wrapper returned no plaintext');
    }
    if (dek.length != _runtimeDekLength) {
      throw PlatformException(
        code: 'runtime_dek_wrap_terminal',
        message: 'runtime DEK wrapper returned invalid plaintext length',
      );
    }
    // Platform channel byte buffers may be backed by an immutable native view.
    // Return a mutable Dart-owned copy so callers can zero the plaintext after
    // restoring runtime keys.
    return Uint8List.fromList(dek);
  }

  Future<void> deleteWrappingKey() async {
    if (!isSupported) return;
    if (Platform.isLinux) {
      await secureStorage.delete(key: _linuxWrappingKeyStorageKey);
      return;
    }
    await _channel.invokeMethod<void>('deleteRuntimeDekWrappingKey');
  }

  /// Returns a platform-defined map of runtime-DEK Keystore/Keychain
  /// state for diagnostic surfacing. Read-only — never mutates platform
  /// state. Returns null when called on an unsupported platform or when
  /// the platform handler is missing (older builds).
  ///
  /// Shape (best-effort, platform-specific):
  ///   - `alias_present`: bool
  ///   - `key_security`: map (security level, StrongBox, accessibility)
  ///   - `device_state`: map (KeyguardManager / UserManager on Android;
  ///     `isProtectedDataAvailable` on iOS)
  ///   - `build`: map (manufacturer, model, OS version)
  Future<Map<String, dynamic>?> getDiagnostics() async {
    if (!isSupported) return null;
    if (Platform.isLinux) {
      var keyPresent = false;
      var secretServiceAccessible = true;
      try {
        keyPresent = await secureStorage.containsKey(
          key: _linuxWrappingKeyStorageKey,
        );
      } catch (_) {
        secretServiceAccessible = false;
      }
      return {
        'alias_present': keyPresent,
        'key_security': {
          'provider': 'Linux Secret Service via flutter_secure_storage',
          'wrapping': 'AES-256-GCM',
          'user_prompt_required': false,
        },
        'device_state': {
          'secret_service_accessible': secretServiceAccessible,
          'secret_service_key_present': keyPresent,
        },
        'build': {'platform': 'linux'},
      };
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getRuntimeDekDiagnostics',
      );
      return raw;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _wrapLinux(Uint8List dek, {required String aad}) async {
    final key = await _readOrCreateLinuxWrappingKey();
    try {
      final nonce = _randomBytes(_linuxNonceLength);
      final combined = aesGcmEncryptForRuntimeDek(
        plaintext: dek,
        key: key,
        nonce: nonce,
        aad: utf8.encode(aad),
      );
      return jsonEncode({
        'version': 1,
        'platform': 'linux_secret_service_aes_gcm',
        'nonce': base64Encode(nonce),
        'combined': base64Encode(combined),
      });
    } finally {
      _zeroBytes(key);
    }
  }

  Future<Uint8List> _unwrapLinux(
    Map<String, dynamic> blob, {
    required String aad,
  }) async {
    if (blob['version'] != 1) {
      throw _runtimeDekTerminal(
        'unsupported Linux runtime DEK wrapper version',
      );
    }
    if (blob['platform'] != 'linux_secret_service_aes_gcm') {
      throw _runtimeDekTerminal('unexpected Linux runtime DEK platform');
    }
    final nonceB64 = blob['nonce'] as String?;
    final combinedB64 = blob['combined'] as String?;
    if (nonceB64 == null || combinedB64 == null) {
      throw _runtimeDekTerminal('missing Linux runtime DEK fields');
    }

    final Uint8List nonce;
    final Uint8List combined;
    try {
      nonce = base64Decode(nonceB64);
      combined = base64Decode(combinedB64);
    } catch (_) {
      throw _runtimeDekTerminal('invalid Linux runtime DEK encoding');
    }

    final key = await _readLinuxWrappingKeyForUnwrap();
    if (key == null) {
      throw _runtimeDekTerminal('Linux runtime DEK wrapping key missing');
    }
    try {
      final dek = aesGcmDecryptForRuntimeDek(
        combined: combined,
        key: key,
        nonce: nonce,
        aad: utf8.encode(aad),
      );
      if (dek.length != _runtimeDekLength) {
        throw const FormatException('invalid runtime DEK length');
      }
      return dek;
    } catch (_) {
      throw _runtimeDekTerminal('Linux runtime DEK authentication failed');
    } finally {
      _zeroBytes(key);
    }
  }

  Future<Uint8List?> _readLinuxWrappingKeyForUnwrap() async {
    try {
      return await _readLinuxWrappingKey();
    } on PlatformException catch (e) {
      throw PlatformException(
        code: 'runtime_dek_wrap_transient',
        message: 'Linux Secret Service unavailable: ${e.code}',
      );
    } catch (_) {
      throw PlatformException(
        code: 'runtime_dek_wrap_transient',
        message: 'Linux Secret Service unavailable',
      );
    }
  }

  Future<Uint8List?> _readLinuxWrappingKey() async {
    final encoded = await secureStorage.read(key: _linuxWrappingKeyStorageKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final key = Uint8List.fromList(base64Decode(encoded));
      if (key.length != _linuxWrappingKeyLength) return null;
      return key;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _readOrCreateLinuxWrappingKey() async {
    final existing = await _readLinuxWrappingKey();
    if (existing != null) return existing;

    final key = _randomBytes(_linuxWrappingKeyLength);
    await secureStorage.write(
      key: _linuxWrappingKeyStorageKey,
      value: base64Encode(key),
    );
    return key;
  }
}

@visibleForTesting
bool isRuntimeDekWrappingPlatformSupported({
  required bool isAndroid,
  required bool isIOS,
  required bool isMacOS,
  required bool isWindows,
  required bool isLinux,
}) {
  return isAndroid || isIOS || isMacOS || isWindows || isLinux;
}

const _linuxWrappingKeyStorageKey = 'prism_sync.runtime_dek_linux_wrap_key_v1';
const _runtimeDekLength = 32;
const _linuxWrappingKeyLength = 32;
const _linuxNonceLength = 12;
const _linuxGcmTagBits = 128;

@visibleForTesting
Uint8List aesGcmEncryptForRuntimeDek({
  required List<int> plaintext,
  required List<int> key,
  required List<int> nonce,
  required List<int> aad,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        _linuxGcmTagBits,
        Uint8List.fromList(nonce),
        Uint8List.fromList(aad),
      ),
    );
  return Uint8List.fromList(cipher.process(Uint8List.fromList(plaintext)));
}

@visibleForTesting
Uint8List aesGcmDecryptForRuntimeDek({
  required List<int> combined,
  required List<int> key,
  required List<int> nonce,
  required List<int> aad,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(Uint8List.fromList(key)),
        _linuxGcmTagBits,
        Uint8List.fromList(nonce),
        Uint8List.fromList(aad),
      ),
    );
  return Uint8List.fromList(cipher.process(Uint8List.fromList(combined)));
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

PlatformException _runtimeDekTerminal(String message) {
  return PlatformException(code: 'runtime_dek_wrap_terminal', message: message);
}

void _zeroBytes(List<int>? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Best-effort cleanup only.
  }
}
