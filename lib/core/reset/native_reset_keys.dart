import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class NativeResetKeys {
  Future<void> deleteKnownKeys({bool force = false});
  Future<bool> hasKnownNativeKeys();
  Future<bool> clearApplicationUserData();
}

class MethodChannelNativeResetKeys implements NativeResetKeys {
  const MethodChannelNativeResetKeys();

  static const MethodChannel _channel = MethodChannel(
    'com.prism.prism_plurality/runtime_dek_wrap',
  );

  bool get _isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  Future<void> deleteKnownKeys({bool force = false}) async {
    if (!_isSupported) return;
    await _channel.invokeMethod<void>('deleteAllPrismResetKeys', {
      'force': force,
    });
  }

  @override
  Future<bool> hasKnownNativeKeys() async {
    if (!_isSupported) return false;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'hasPrismResetKeys',
    );
    if (result == null) return false;
    return _containsTrue(result);
  }

  @override
  Future<bool> clearApplicationUserData() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('clearApplicationUserData') ??
        false;
  }

  bool _containsTrue(Map<dynamic, dynamic> values) {
    for (final value in values.values) {
      if (value == true) return true;
      if (value is Map && _containsTrue(value)) return true;
      if (value is Iterable && value.any((entry) => entry == true)) {
        return true;
      }
    }
    return false;
  }
}
