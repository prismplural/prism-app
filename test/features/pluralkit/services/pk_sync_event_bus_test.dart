import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

/// Minimal concrete `PkSyncEvent` so this test file does not have to depend
/// on Task 1's full event surface. The bus's `emit` accepts any subclass.
class _TestPkSyncEvent extends PkSyncEvent {
  const _TestPkSyncEvent(this.label);
  final String label;
  @override
  String get summary => 'test event $label';
  @override
  Map<String, dynamic> toJson() => {'kind': 'test', 'label': label};
}

void main() {
  group('PkSyncEventBus', () {
    // Default each test to "not on main isolate" — individual tests opt in
    // via markPkBusMainIsolate() when they want emits to be delivered.
    setUp(resetPkBusMainIsolateForTest);

    // Belt-and-braces: never leak the flag to a sibling test file.
    tearDown(resetPkBusMainIsolateForTest);

    test('emit after markPkBusMainIsolate() delivers to stream listeners',
        () async {
      markPkBusMainIsolate();
      final bus = PkSyncEventBus();
      addTearDown(bus.dispose);

      const event = _TestPkSyncEvent('A');
      final completer = Completer<PkSyncEvent>();
      final sub = bus.stream.listen(completer.complete);
      addTearDown(sub.cancel);

      bus.emit(event);

      final received = await completer.future
          .timeout(const Duration(seconds: 1));
      expect(received, same(event));
    });

    test('emit is a silent no-op when not marked as main isolate', () async {
      // resetPkBusMainIsolateForTest() already called in setUp; do not mark.
      final bus = PkSyncEventBus();
      addTearDown(bus.dispose);

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);
      addTearDown(sub.cancel);

      bus.emit(const _TestPkSyncEvent('A'));
      bus.emit(const _TestPkSyncEvent('B'));

      // Give the event loop a chance to deliver anything that was added.
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
    });

    test('toggling the flag flips delivery on and off', () async {
      final bus = PkSyncEventBus();
      addTearDown(bus.dispose);

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);
      addTearDown(sub.cancel);

      // Marked: events delivered.
      markPkBusMainIsolate();
      bus.emit(const _TestPkSyncEvent('on-1'));
      bus.emit(const _TestPkSyncEvent('on-2'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);

      // Reset: events no-op.
      resetPkBusMainIsolateForTest();
      bus.emit(const _TestPkSyncEvent('off-1'));
      bus.emit(const _TestPkSyncEvent('off-2'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 2);

      // Marked again: events delivered again.
      markPkBusMainIsolate();
      bus.emit(const _TestPkSyncEvent('on-3'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 3);
    });

    test('dispose() closes the controller; subsequent emits no-op', () async {
      markPkBusMainIsolate();
      final bus = PkSyncEventBus();

      final received = <PkSyncEvent>[];
      final sub = bus.stream.listen(received.add);

      bus.emit(const _TestPkSyncEvent('before-dispose'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);

      await sub.cancel();
      bus.dispose();

      // Subsequent emits must not throw even though the controller is closed.
      expect(() => bus.emit(const _TestPkSyncEvent('after-dispose')),
          returnsNormally);
      // And nothing else should have been delivered.
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
    });

    test('PkSyncEventBusCapture accumulates emissions into .events', () async {
      markPkBusMainIsolate();
      final capture = PkSyncEventBusCapture();
      addTearDown(capture.bus.dispose);

      capture.bus.emit(const _TestPkSyncEvent('1'));
      capture.bus.emit(const _TestPkSyncEvent('2'));
      capture.bus.emit(const _TestPkSyncEvent('3'));

      // Allow one microtask hop for broadcast delivery.
      await Future<void>.delayed(Duration.zero);
      expect(capture.events.length, 3);
      expect(
        capture.events
            .whereType<_TestPkSyncEvent>()
            .map((e) => e.label)
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

      bus.emit(const _TestPkSyncEvent('via-provider'));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);

      container.dispose();
      // After container dispose, the bus's controller should be closed —
      // emitting again must be a silent no-op, not a StateError.
      expect(() => bus.emit(const _TestPkSyncEvent('after-container-dispose')),
          returnsNormally);
    });
  });
}
