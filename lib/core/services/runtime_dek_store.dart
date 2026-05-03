import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

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
}
