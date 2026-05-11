import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_sync_event_log_provider.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';

void main() {
  group('PkSyncEventLogNotifier', () {
    setUp(markPkBusMainIsolate);
    tearDown(resetPkBusMainIsolateForTest);

    test('receives events while the notifier is alive', () async {
      final capture = PkSyncEventBusCapture();
      final container = ProviderContainer(overrides: [
        pkSyncEventBusProvider.overrideWithValue(capture.bus),
      ]);
      addTearDown(container.dispose);

      // Simulate app.dart's ref.listen keeping the notifier alive.
      container.listen(pkSyncEventLogProvider, (_, _) {});

      const event = PkLiveFronterSkipped(reason: 'test');
      capture.bus.emit(event);

      await Future<void>.delayed(Duration.zero);

      final entries = container.read(pkSyncEventLogProvider);
      expect(entries, hasLength(1));
      expect(entries.single.summary, event.summary);
      expect(entries.single.data['reason'], 'test');
    });

    test('retains every event when the notifier is kept alive', () async {
      final capture = PkSyncEventBusCapture();
      final container = ProviderContainer(overrides: [
        pkSyncEventBusProvider.overrideWithValue(capture.bus),
      ]);
      addTearDown(container.dispose);

      // Keep the notifier alive from before any event is emitted, mirroring
      // the `ref.listen` in app.dart.
      container.listen(pkSyncEventLogProvider, (_, _) {});

      for (var i = 0; i < 5; i++) {
        capture.bus.emit(PkMembersImported(count: i));
      }

      await Future<void>.delayed(Duration.zero);

      final entries = container.read(pkSyncEventLogProvider);
      expect(entries, hasLength(5));
    });

    test('drops the oldest entries once the 200-entry cap is exceeded',
        () async {
      final capture = PkSyncEventBusCapture();
      final container = ProviderContainer(overrides: [
        pkSyncEventBusProvider.overrideWithValue(capture.bus),
      ]);
      addTearDown(container.dispose);

      container.listen(pkSyncEventLogProvider, (_, _) {});

      for (var i = 0; i < 250; i++) {
        capture.bus.emit(PkMembersImported(count: i));
      }

      await Future<void>.delayed(Duration.zero);

      final entries = container.read(pkSyncEventLogProvider);
      expect(entries, hasLength(kPkSyncEventLogMax));
      // We emitted counts 0..249; the ring keeps the last 200, so the first
      // surviving entry should correspond to count == 50.
      final firstEvent = entries.first.event as PkMembersImported;
      expect(firstEvent.count, 50);
      final lastEvent = entries.last.event as PkMembersImported;
      expect(lastEvent.count, 249);
    });

    test('clear() empties the log and the notifier keeps recording',
        () async {
      final capture = PkSyncEventBusCapture();
      final container = ProviderContainer(overrides: [
        pkSyncEventBusProvider.overrideWithValue(capture.bus),
      ]);
      addTearDown(container.dispose);

      container.listen(pkSyncEventLogProvider, (_, _) {});

      for (var i = 0; i < 3; i++) {
        capture.bus.emit(PkMembersImported(count: i));
      }
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pkSyncEventLogProvider), hasLength(3));

      container.read(pkSyncEventLogProvider.notifier).clear();
      expect(container.read(pkSyncEventLogProvider), isEmpty);

      capture.bus.emit(const PkMembersImported(count: 99));
      await Future<void>.delayed(Duration.zero);

      final entries = container.read(pkSyncEventLogProvider);
      expect(entries, hasLength(1));
      expect((entries.single.event as PkMembersImported).count, 99);
    });

    test('isError on the entry mirrors the underlying event', () async {
      final capture = PkSyncEventBusCapture();
      final container = ProviderContainer(overrides: [
        pkSyncEventBusProvider.overrideWithValue(capture.bus),
      ]);
      addTearDown(container.dispose);

      container.listen(pkSyncEventLogProvider, (_, _) {});

      capture.bus.emit(const PkTokenAuthFailed());
      capture.bus.emit(const PkTokenCleared());

      await Future<void>.delayed(Duration.zero);

      final entries = container.read(pkSyncEventLogProvider);
      expect(entries, hasLength(2));
      expect(entries[0].isError, isTrue);
      expect(entries[1].isError, isFalse);
    });

    test('disposing the container detaches the bus subscription cleanly',
        () async {
      final capture = PkSyncEventBusCapture();
      final container = ProviderContainer(overrides: [
        pkSyncEventBusProvider.overrideWithValue(capture.bus),
      ]);

      container.listen(pkSyncEventLogProvider, (_, _) {});

      capture.bus.emit(const PkMembersImported(count: 1));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(pkSyncEventLogProvider), hasLength(1));

      container.dispose();

      // Emitting after dispose must not throw or trip a StateError, even
      // though the notifier's subscription has been cancelled.
      expect(
        () => capture.bus.emit(const PkMembersImported(count: 2)),
        returnsNormally,
      );
    });
  });
}
