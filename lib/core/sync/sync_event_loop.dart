import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;

/// Parsed sync event from the Rust FFI layer.
///
/// Event types (from prism-sync-core/src/events.rs): RemoteChanges,
/// SyncCompleted, SyncStarted, Error, DeviceRevoked, EpochRotated,
/// WebSocketStateChanged, QuarantinedBatch. Use the boolean getters
/// (isRemoteChanges, etc.) to discriminate before accessing type-specific
/// fields.
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

  /// The relay minted a fresh device-session token via the signed
  /// `/session/refresh` recovery path. The app re-persists
  /// [rotatedSessionToken] to the keychain so the next launch starts with a
  /// valid credential; refresh-on-401 at launch is the fallback if missed.
  bool get isSessionTokenRotated => type == 'SessionTokenRotated';

  /// The new session token carried by a `SessionTokenRotated` event, or `null`
  /// for any other event type / a malformed payload.
  String? get rotatedSessionToken =>
      isSessionTokenRotated ? data['token'] as String? : null;

  /// A local push batch was quarantined because its serialized envelope
  /// exceeded the relay's 1 MB body cap. Listeners refresh the
  /// quarantined-batch count so the sync troubleshooting screen can
  /// surface a repair banner.
  bool get isQuarantinedBatch => type == 'QuarantinedBatch';

  /// An ephemeral signal-lane message (ephemeral media signaling) drained from the
  /// relay's device-message mailbox during a sync cycle. The demand-driven
  /// heal (media heal) reacts to these; the relay never sees the decrypted
  /// `ephemeralKind` / `ephemeralMediaId`.
  bool get isEphemeralMessage => type == 'EphemeralMessage';

  /// The authenticated device that sent an [isEphemeralMessage].
  String get ephemeralSenderDeviceId =>
      data['sender_device_id'] as String? ?? '';

  /// App-level kind of an [isEphemeralMessage] (e.g. `'media_request'`).
  String get ephemeralKind => data['kind'] as String? ?? '';

  /// The media id an [isEphemeralMessage] concerns.
  String get ephemeralMediaId => data['media_id'] as String? ?? '';

  /// The epoch an [isEphemeralMessage] was sealed under.
  int get ephemeralEpochId => (data['epoch_id'] as num?)?.toInt() ?? 0;

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
