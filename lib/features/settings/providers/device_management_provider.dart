import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';

/// A device registered in the sync group.
class Device {
  const Device({
    required this.deviceId,
    required this.epoch,
    required this.status,
    this.permission,
    this.mlDsaKeyGeneration = 0,
  });

  final String deviceId;
  final int epoch;
  final String status;
  final String? permission;
  final int mlDsaKeyGeneration;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      deviceId: json['device_id'] as String,
      epoch: json['epoch'] as int,
      status: json['status'] as String,
      permission: json['permission'] as String?,
      mlDsaKeyGeneration: (json['ml_dsa_key_generation'] as int?) ?? 0,
    );
  }

  /// First 6 characters of the device ID for display.
  String get shortId => deviceId.length >= 6 ? deviceId.substring(0, 6) : deviceId;

  bool get isActive => status == 'active';
  bool get isStale => status == 'stale';
  bool get isRevoked => status == 'revoked';
}

/// Fetches and manages the list of devices in the sync group.
class DeviceListNotifier extends AsyncNotifier<List<Device>> {
  @override
  Future<List<Device>> build() async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) {
      throw Exception('Sync not configured');
    }

    final syncId = await _readCredential('sync_id');
    final deviceId = await _readCredential('device_id');
    final sessionToken = await _readCredential('session_token');

    if (syncId == null || deviceId == null || sessionToken == null) {
      throw Exception('Missing sync credentials');
    }

    final jsonStr = await ffi.listDevices(
      handle: handle,
      syncId: syncId,
      deviceId: deviceId,
      sessionToken: sessionToken,
    );

    final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
    return jsonList
        .map((e) => Device.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Revoke a device from the sync group, then refresh the list.
  ///
  /// When [remoteWipe] is true, the relay records a wipe flag so the revoked
  /// device will erase its local sync data on its next connection.
  Future<void> revoke(String targetDeviceId, {bool remoteWipe = false}) async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) throw Exception('Sync not configured');

    final syncId = await _readCredential('sync_id');
    final deviceId = await _readCredential('device_id');
    final sessionToken = await _readCredential('session_token');

    if (syncId == null || deviceId == null || sessionToken == null) {
      throw Exception('Missing sync credentials');
    }

    await ffi.revokeAndRekey(
      handle: handle,
      syncId: syncId,
      deviceId: deviceId,
      sessionToken: sessionToken,
      targetDeviceId: targetDeviceId,
      remoteWipe: remoteWipe,
    );

    ref.invalidateSelf();
  }

  /// Rotate this device's ML-DSA signing key.
  ///
  /// Creates a new key at the next generation with a cross-signed continuity
  /// proof, submits it to the relay, and updates the local registry.
  /// Returns the new generation number.
  Future<int> rotateMlDsaKey() async {
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) throw Exception('Sync not configured');

    final resultJson = await ffi.rotateMlDsaKey(handle: handle);
    final result = json.decode(resultJson) as Map<String, dynamic>;

    ref.invalidateSelf();
    return result['ml_dsa_key_generation'] as int;
  }

  /// Read a base64-encoded credential from secure storage.
  Future<String?> _readCredential(String key) async {
    final value = await secureStorage.read(key: 'prism_sync.$key');
    if (value == null || value.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(value));
    } catch (_) {
      return value; // Fallback: already plain text
    }
  }
}

final deviceListProvider =
    AsyncNotifierProvider<DeviceListNotifier, List<Device>>(
  DeviceListNotifier.new,
);
