import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;

/// Parsed sync event from the Rust FFI layer.
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
  bool get remoteWipe => data['remote_wipe'] as bool? ?? false;
  bool get isWebSocketStateChanged => type == 'WebSocketStateChanged';
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
