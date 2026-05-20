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
    final read = await safeSecureRead(key, storage: _storage);
    if (!read.ok) return null;
    final value = read.value;
    if (value == null) return null;
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> set(String key, Uint8List value) async {
    final write = await safeSecureWriteVerified(
      key,
      base64Encode(value),
      storage: _storage,
    );
    if (!write.ok) {
      throw StateError(
        _secureStoreFailure(
          'write',
          key,
          failure: write.failure,
          code: write.code,
          message: write.message,
        ),
      );
    }
  }

  @override
  Future<void> delete(String key) async {
    final delete = await safeSecureDelete(key, storage: _storage);
    if (!delete.ok) {
      throw StateError(
        _secureStoreFailure(
          'delete',
          key,
          failure: delete.failure,
          code: delete.code,
          message: delete.message,
        ),
      );
    }
  }

  @override
  Future<void> clear() async {
    final delete = await safeSecureDeleteAll(storage: _storage);
    if (!delete.ok) {
      throw StateError(
        _secureStoreFailure(
          'clear',
          null,
          failure: delete.failure,
          code: delete.code,
          message: delete.message,
        ),
      );
    }
  }

  String _secureStoreFailure(
    String operation,
    String? key, {
    required SecureStorageFailure? failure,
    required String? code,
    required String? message,
  }) {
    final keySuffix = key == null ? '' : ' for $key';
    return 'Prism secure-store $operation failed$keySuffix '
        '(failure=${failure?.name}, code=$code, message=$message)';
  }
}
