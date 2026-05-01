import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:prism_sync/generated/api.dart' as ffi;

class FirstDeviceAdmissionService {
  static const _httpTimeout = Duration(seconds: 15);
  static const _channel = MethodChannel(
    'com.prism.prism_plurality/first_device_admission',
  );

  Future<void> preparePendingRegistration({
    required ffi.PrismSyncHandle handle,
    required String relayUrl,
    String? registrationToken,
  }) async {
    final deviceId = await ffi.preparePendingDeviceIdentity(handle: handle);
    final syncId = _generateSyncId();

    final nonceUri = Uri.parse('$relayUrl/v1/sync/$syncId/register-nonce');
    final nonceHeaders = <String, String>{};
    if (registrationToken != null && registrationToken.isNotEmpty) {
      nonceHeaders['X-Registration-Token'] = registrationToken;
    }
    final nonceResp = await http
        .get(nonceUri, headers: nonceHeaders)
        .timeout(_httpTimeout);
    if (nonceResp.statusCode < 200 || nonceResp.statusCode >= 300) {
      throw Exception(
        'Failed to prepare registration challenge: HTTP ${nonceResp.statusCode}',
      );
    }

    final nonceJson = jsonDecode(nonceResp.body) as Map<String, dynamic>;
    final nonce = nonceJson['nonce'] as String?;
    if (nonce == null || nonce.isEmpty) {
      throw const FormatException('Relay nonce response was missing nonce');
    }

    final proof = await _collectPlatformProof(
      syncId: syncId,
      deviceId: deviceId,
      nonce: nonce,
    );

    final pendingEntries = <String, Uint8List>{
      'pending_sync_id': _encodeUtf8(syncId),
      'pending_registration_nonce_response': _encodeJson(nonceJson),
    };
    if (proof != null) {
      pendingEntries['pending_first_device_admission_proof'] = _encodeJson(
        proof,
      );
    }
    if (registrationToken != null && registrationToken.isNotEmpty) {
      pendingEntries['pending_registration_token'] = _encodeUtf8(
        registrationToken,
      );
    }

    await ffi.seedSecureStore(handle: handle, entries: pendingEntries);
  }

  Future<Map<String, dynamic>?> _collectPlatformProof({
    required String syncId,
    required String deviceId,
    required String nonce,
  }) async {
    try {
      final arguments = <String, dynamic>{
        'sync_id': syncId,
        'device_id': deviceId,
        'nonce': nonce,
      };
      final result = await _channel.invokeMethod<Object?>(
        'collectFirstDeviceAdmissionProof',
        arguments,
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  String _generateSyncId() {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Uint8List _encodeJson(Object value) => _encodeUtf8(jsonEncode(value));

  Uint8List _encodeUtf8(String value) => Uint8List.fromList(utf8.encode(value));
}
