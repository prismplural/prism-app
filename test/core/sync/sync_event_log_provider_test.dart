import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';

void main() {
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'sync event log retains events emitted before the screen opens',
    () async {
      final controller = StreamController<SyncEvent>.broadcast();
      addTearDown(controller.close);

      final container = ProviderContainer(
        overrides: [
          syncEventStreamProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        syncEventLogProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);

      controller.add(
        SyncEvent('Error', {'type': 'Error', 'message': 'pull failed'}),
      );
      controller.add(
        SyncEvent('WebSocketStateChanged', {
          'type': 'WebSocketStateChanged',
          'connected': false,
        }),
      );
      await settle();

      final entries = container.read(syncEventLogProvider);
      expect(entries, hasLength(2));
      expect(entries.first.summary, 'Error: pull failed');
      expect(entries.last.summary, 'WebSocket disconnected');
    },
  );

  test('sync event log can be cleared', () async {
    final controller = StreamController<SyncEvent>.broadcast();
    addTearDown(controller.close);

    final container = ProviderContainer(
      overrides: [
        syncEventStreamProvider.overrideWith((ref) => controller.stream),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      syncEventLogProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);

    controller.add(SyncEvent('SyncStarted', {'type': 'SyncStarted'}));
    await settle();

    expect(container.read(syncEventLogProvider), hasLength(1));

    container.read(syncEventLogProvider.notifier).clear();

    expect(container.read(syncEventLogProvider), isEmpty);
  });

  test('ephemeral message event summarises kind and media id', () async {
    final controller = StreamController<SyncEvent>.broadcast();
    addTearDown(controller.close);

    final container = ProviderContainer(
      overrides: [
        syncEventStreamProvider.overrideWith((ref) => controller.stream),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(syncEventLogProvider, (_, _) {});
    addTearDown(subscription.close);

    controller.add(SyncEvent('EphemeralMessage', {
      'type': 'EphemeralMessage',
      'sender_device_id': 'dev-2',
      'kind': 'media_request',
      'media_id': 'blob-7',
      'epoch_id': 3,
    }));
    await settle();

    final entries = container.read(syncEventLogProvider);
    expect(entries, hasLength(1));
    expect(entries.single.summary, 'Ephemeral media_request for blob-7');
  });
}
