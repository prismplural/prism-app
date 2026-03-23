import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:prism_sync_flutter/prism_sync_flutter.dart';

import 'package:prism_plurality/core/services/secure_storage.dart';

/// Bridges prism-sync's SecureStore interface to Flutter's platform keychain.
class PrismSecureStore implements SecureStore {
  final FlutterSecureStorage _storage;

  PrismSecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? secureStorage;

  @override
  Future<Uint8List?> get(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) return null;
    return base64Decode(value);
  }

  @override
  Future<void> set(String key, Uint8List value) async {
    await _storage.write(key: key, value: base64Encode(value));
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> clear() => _storage.deleteAll();
}
