import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;

/// Parsed sync event from the Rust FFI layer.
///
/// Event types (from prism-sync-core/src/events.rs): RemoteChanges,
/// SyncCompleted, SyncStarted, Error, DeviceRevoked, EpochRotated,
/// WebSocketStateChanged. Use the boolean getters (isRemoteChanges, etc.)
/// to discriminate before accessing type-specific fields.
class SyncEvent {
  final String type;
  final Map<String, dynamic> data;

  SyncEvent(this.type, this.data);

  factory SyncEvent.fromJson(Map<String, dynamic> json) {
    return SyncEvent(json['type'] as String, json);
  }

  List<Map<String, dynamic>> get changes =>
      (data['changes'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  bool get isRemoteChanges => type == 'RemoteChanges';
  bool get isSyncCompleted => type == 'SyncCompleted';
  bool get isSyncStarted => type == 'SyncStarted';
  bool get isError => type == 'Error';
  bool get isDeviceRevoked => type == 'DeviceRevoked';
  bool get isEpochRotated => type == 'EpochRotated';
  bool get remoteWipe => data['remote_wipe'] as bool? ?? false;
  bool get isWebSocketStateChanged => type == 'WebSocketStateChanged';

  /// Structured error-kind string as emitted by the Rust FFI (pascal-case).
  ///
  /// Populated on `SyncCompleted` events whose `result.error` is set, and
  /// on `Error` events via `event.data['kind']`. Values correspond to the
  /// Rust `SyncErrorKind` Debug format: `'Network'`, `'Auth'`, `'Server'`,
  /// `'Timeout'`, `'KeyChanged'`, `'DeviceIdentityMismatch'`,
  /// `'EpochRotation'`, `'Protocol'`, `'ClockSkew'`.
  ///
  /// Returns `null` when no structured kind is available (older events,
  /// genuine success, or events that don't carry an error).
  String? get errorKind {
    if (isSyncCompleted) {
      final result = data['result'];
      if (result is Map<String, dynamic>) {
        final kind = result['error_kind'];
        if (kind is String) return kind;
      }
      return null;
    }
    if (isError) {
      final kind = data['kind'];
      if (kind is String) return kind;
    }
    return null;
  }
}

/// Creates an event stream using native flutter_rust_bridge StreamSink.
/// Rust pushes events directly — no polling needed.
Stream<SyncEvent> createSyncEventStream(ffi.PrismSyncHandle handle) {
  return ffi.syncEventStream(handle: handle).map((jsonStr) {
    return SyncEvent.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  });
}
