import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

/// A decoded ephemeral signal-lane message (ephemeral media signaling) drained from
/// the relay's device-message mailbox during a sync cycle.
///
/// The relay is blind to these contents — `kind` and `mediaId` are sealed under
/// the group epoch key and only surface here, after the Rust drain decrypts
/// them. The demand-driven heal (media heal) consumes this typed stream to drive its
/// requester/responder state machine.
class EphemeralMessage {
  const EphemeralMessage({
    required this.senderDeviceId,
    required this.kind,
    required this.mediaId,
    required this.epochId,
  });

  /// The authenticated device that sent the message.
  final String senderDeviceId;

  /// App-level kind, e.g. `'media_request'` or `'media_uploaded'`.
  final String kind;

  /// The media id the message concerns.
  final String mediaId;

  /// The epoch the message was sealed under.
  final int epochId;

  factory EphemeralMessage.fromEvent(SyncEvent event) => EphemeralMessage(
    senderDeviceId: event.ephemeralSenderDeviceId,
    kind: event.ephemeralKind,
    mediaId: event.ephemeralMediaId,
    epochId: event.ephemeralEpochId,
  );
}

/// Typed stream of ephemeral messages drained from the mailbox, decoded from
/// the raw [syncEventStreamProvider]. This is the reactor seam: the media heal's
/// requester/responder subscribes here. Malformed events (missing kind or
/// media id) are dropped — the lane is advisory and the sender re-issues.
final ephemeralMessageStreamProvider = StreamProvider<EphemeralMessage>((ref) {
  final controller = StreamController<EphemeralMessage>();
  ref.onDispose(controller.close);
  ref.listen<AsyncValue<SyncEvent>>(syncEventStreamProvider, (_, next) {
    final event = next.value;
    if (event != null &&
        event.isEphemeralMessage &&
        event.ephemeralKind.isNotEmpty &&
        event.ephemeralMediaId.isNotEmpty) {
      controller.add(EphemeralMessage.fromEvent(event));
    }
  });
  return controller.stream;
});

/// The FFI call shape, factored out so the sender is testable without a native
/// handle.
typedef SendEphemeralFn =
    Future<void> Function({
      required String kind,
      required String mediaId,
      String? recipientDeviceId,
    });

/// Posts ephemeral signal-lane messages (ephemeral media signaling) to the relay
/// mailbox. Best-effort: against an old relay without the endpoint the
/// underlying call throws, which the caller (media heal) treats as a feature-absent
/// no-op rather than an error to surface.
class EphemeralSignalSender {
  EphemeralSignalSender(this._send);

  final SendEphemeralFn _send;

  /// Send one message. `recipientDeviceId` targets a single device, or `null`
  /// broadcasts to the group.
  Future<void> send({
    required String kind,
    required String mediaId,
    String? recipientDeviceId,
  }) => _send(
    kind: kind,
    mediaId: mediaId,
    recipientDeviceId: recipientDeviceId,
  );
}

final ephemeralSignalSenderProvider = Provider<EphemeralSignalSender>((ref) {
  return EphemeralSignalSender((
    {required String kind,
    required String mediaId,
    String? recipientDeviceId}) async {
    // Resolve the handle lazily from the current value — never await it. A
    // null/loading handle throws so the caller can back off; a fresh handle is
    // re-read on the next send.
    final handle = ref.read(prismSyncHandleProvider).value;
    if (handle == null) {
      throw StateError('sync handle unavailable; cannot send ephemeral message');
    }
    await ffi.sendEphemeral(
      handle: handle,
      kind: kind,
      mediaId: mediaId,
      recipientDeviceId: recipientDeviceId,
    );
  });
});
