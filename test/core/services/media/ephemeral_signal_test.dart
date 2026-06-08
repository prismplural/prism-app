import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/media/ephemeral_signal.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('SyncEvent ephemeral accessors', () {
    test('decodes an EphemeralMessage event', () {
      final event = SyncEvent('EphemeralMessage', {
        'type': 'EphemeralMessage',
        'sender_device_id': 'dev-2',
        'kind': 'media_request',
        'media_id': 'blob-7',
        'epoch_id': 3,
      });
      expect(event.isEphemeralMessage, isTrue);
      expect(event.ephemeralSenderDeviceId, 'dev-2');
      expect(event.ephemeralKind, 'media_request');
      expect(event.ephemeralMediaId, 'blob-7');
      expect(event.ephemeralEpochId, 3);
    });

    test('non-ephemeral event reads blank accessors', () {
      final event = SyncEvent('SyncStarted', {'type': 'SyncStarted'});
      expect(event.isEphemeralMessage, isFalse);
      expect(event.ephemeralKind, '');
      expect(event.ephemeralMediaId, '');
      expect(event.ephemeralEpochId, 0);
    });
  });

  group('EphemeralSignalSender', () {
    test('forwards kind, mediaId and recipient to the send fn', () async {
      String? gotKind;
      String? gotMedia;
      String? gotRecipient;
      final sender = EphemeralSignalSender((
          {required String kind,
          required String mediaId,
          String? recipientDeviceId}) async {
        gotKind = kind;
        gotMedia = mediaId;
        gotRecipient = recipientDeviceId;
      });

      await sender.send(
        kind: 'media_uploaded',
        mediaId: 'blob-9',
        recipientDeviceId: 'dev-3',
      );

      expect(gotKind, 'media_uploaded');
      expect(gotMedia, 'blob-9');
      expect(gotRecipient, 'dev-3');
    });

    test('broadcast send passes a null recipient', () async {
      String? gotRecipient = 'unset';
      final sender = EphemeralSignalSender((
          {required String kind,
          required String mediaId,
          String? recipientDeviceId}) async {
        gotRecipient = recipientDeviceId;
      });
      await sender.send(kind: 'media_request', mediaId: 'b');
      expect(gotRecipient, isNull);
    });
  });

  group('ephemeralMessageStreamProvider', () {
    test('decodes EphemeralMessage events and drops other types', () async {
      final controller = StreamController<SyncEvent>.broadcast();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [
          syncEventStreamProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);

      final received = <EphemeralMessage>[];
      final sub = container.listen<AsyncValue<EphemeralMessage>>(
        ephemeralMessageStreamProvider,
        (_, next) {
          final m = next.value;
          if (m != null) received.add(m);
        },
      );
      addTearDown(sub.close);
      await settle();

      controller.add(SyncEvent('SyncStarted', {'type': 'SyncStarted'}));
      controller.add(SyncEvent('EphemeralMessage', {
        'type': 'EphemeralMessage',
        'sender_device_id': 'dev-1',
        'kind': 'media_request',
        'media_id': 'blob-1',
        'epoch_id': 2,
      }));
      // Malformed (missing media_id) — dropped.
      controller.add(SyncEvent('EphemeralMessage', {
        'type': 'EphemeralMessage',
        'sender_device_id': 'dev-1',
        'kind': 'media_request',
        'epoch_id': 2,
      }));
      await settle();

      expect(received, hasLength(1));
      expect(received.single.kind, 'media_request');
      expect(received.single.mediaId, 'blob-1');
      expect(received.single.senderDeviceId, 'dev-1');
      expect(received.single.epochId, 2);
    });
  });
}
