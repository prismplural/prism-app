import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

PkSyncEvent _evt(String label) => PkLiveFronterSkipped(reason: label);

void main() {
  group('PkSyncEventBus', () {
    setUp(resetPkBusMainIsolateForTest);
    tearDown(resetPkBusMainIsolateForTest);

    test('emit after markPkBusMainIsolate() delivers to stream listeners',
        () async {
      markPkBusMainIsolate();
      final bus = PkSyncEventBus();
      addTearDown(bus.dispose);

      final event = _evt('A');
      final completer = Completer<PkSyncEvent>();
      final sub = bus.stream.listen(completer.complete);
      addTearDown(sub.cancel);

      bus.emit(event);

      final received = await completer.future
          .timeout(const Duration(seconds: 1));
      expect(received, same(event));
    });

    test('emit is a silent no-op when not marked as main isolate', () async {
      final bus = PkSyncEventBus();
      addTearDown(bus.dispose);

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);
      addTearDown(sub.cancel);

      bus.emit(_evt('A'));
      bus.emit(_evt('B'));

      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });

    test('toggling the flag flips delivery on and off', () async {
      final bus = PkSyncEventBus();
      addTearDown(bus.dispose);

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);
      addTearDown(sub.cancel);

      markPkBusMainIsolate();
      bus.emit(_evt('on-1'));
      bus.emit(_evt('on-2'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);

      resetPkBusMainIsolateForTest();
      bus.emit(_evt('off-1'));
      bus.emit(_evt('off-2'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);

      markPkBusMainIsolate();
      bus.emit(_evt('on-3'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 3);
    });

    test('dispose() closes the controller; subsequent emits no-op', () async {
      markPkBusMainIsolate();
      final bus = PkSyncEventBus();

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);

      bus.emit(_evt('before-dispose'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);

      await sub.cancel();
      bus.dispose();

      expect(() => bus.emit(_evt('after-dispose')), returnsNormally);
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
    });

    test('PkSyncEventBusCapture accumulates emissions into .events', () async {
      markPkBusMainIsolate();
      final capture = PkSyncEventBusCapture();
      addTearDown(capture.bus.dispose);

      capture.bus.emit(_evt('1'));
      capture.bus.emit(_evt('2'));
      capture.bus.emit(_evt('3'));

      await Future<void>.delayed(Duration.zero);
      expect(capture.events.length, 3);
      expect(
        capture.events
            .whereType<PkLiveFronterSkipped>()
            .map((e) => e.reason)
            .toList(),
        ['1', '2', '3'],
      );
    });

    test('pkSyncEventBusProvider returns a working bus and disposes it',
        () async {
      markPkBusMainIsolate();
      final container = ProviderContainer();
      final bus = container.read(pkSyncEventBusProvider);

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);
      addTearDown(sub.cancel);

      bus.emit(_evt('via-provider'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);

      container.dispose();
      expect(() => bus.emit(_evt('after-container-dispose')), returnsNormally);
    });
  });
}
