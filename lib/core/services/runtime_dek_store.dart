import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
/// and a non-extractable iOS Keychain EC private key; both avoid per-launch
/// user auth so background sync can restore after the first device unlock.
class DeviceBoundRuntimeDekStore {
  const DeviceBoundRuntimeDekStore();

  static const MethodChannel _channel = MethodChannel(
    'com.prism.prism_plurality/runtime_dek_wrap',
  );

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  Future<String> wrap(Uint8List dek, {required String aad}) async {
    if (!isSupported) {
      throw UnsupportedError(
        'runtime DEK wrapping is only supported on Android/iOS',
      );
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
        'runtime DEK unwrap is only supported on Android/iOS',
      );
    }
    final decoded = jsonDecode(blob);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'runtime DEK wrapper blob must be a JSON object',
      );
    }
    final dek = await _channel.invokeMethod<Uint8List>('unwrapRuntimeDek', {
      ...decoded,
      'aad': aad,
    });
    if (dek == null) {
      throw StateError('runtime DEK wrapper returned no plaintext');
    }
    // Platform channel byte buffers may be backed by an immutable native view.
    // Return a mutable Dart-owned copy so callers can zero the plaintext after
    // restoring runtime keys.
    return Uint8List.fromList(dek);
  }

  Future<void> deleteWrappingKey() async {
    if (!isSupported) return;
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
}
