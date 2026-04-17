import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';

SyncEvent _remoteChanges(List<String> tables) {
  return SyncEvent('RemoteChanges', {
    'type': 'RemoteChanges',
    'changes': tables.map((t) => {'table': t}).toList(),
  });
}

SyncEvent _wsChanged({required bool connected}) {
  return SyncEvent('WebSocketStateChanged', {
    'type': 'WebSocketStateChanged',
    'connected': connected,
  });
}

void main() {
  late StreamController<SyncEvent> controller;

  setUp(() {
    controller = StreamController<SyncEvent>.broadcast();
  });
  tearDown(() => controller.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        syncEventStreamProvider.overrideWith((ref) => controller.stream),
      ],
    );
    // Keep the notifier alive by opening a listener.
    container.listen<SyncSetupProgressState>(
      syncSetupProgressProvider,
      (prev, next) {},
    );
    return container;
  }

  // Pump microtasks so stream events propagate through Riverpod.
  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('initial state is connecting with empty counts', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final s = container.read(syncSetupProgressProvider);
    expect(s.phase, PairingProgressPhase.connecting);
    expect(s.liveCounts, isEmpty);
    expect(s.timedOut, isFalse);
    expect(s.wsConnected, isFalse);
  });

  test('setPhase(downloading) advances and updates phaseStartedAt', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final before = container.read(syncSetupProgressProvider).phaseStartedAt;
    await Future<void>.delayed(const Duration(milliseconds: 1));

    container.read(syncSetupProgressProvider.notifier).setPhase(
      PairingProgressPhase.downloading,
    );

    final s = container.read(syncSetupProgressProvider);
    expect(s.phase, PairingProgressPhase.downloading);
    expect(s.phaseStartedAt.isAfter(before), isTrue);
  });

  test('setPhase(connecting) after downloading is a no-op', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final notifier = container.read(syncSetupProgressProvider.notifier);
    notifier.setPhase(PairingProgressPhase.downloading);

    final phaseStarted =
        container.read(syncSetupProgressProvider).phaseStartedAt;
    notifier.setPhase(PairingProgressPhase.connecting);

    final s = container.read(syncSetupProgressProvider);
    expect(s.phase, PairingProgressPhase.downloading);
    expect(s.phaseStartedAt, phaseStarted);
  });

  test('RemoteChanges events tally per table after 300ms throttle', () {
    fakeAsync((fake) {
      final container = makeContainer();
      addTearDown(container.dispose);

      final changes =
          List.filled(3, 'members') + List.filled(104, 'chat_messages');
      controller.add(_remoteChanges(changes));
      fake.flushMicrotasks();

      // Before 300ms: counts not yet flushed.
      fake.elapse(const Duration(milliseconds: 299));
      expect(container.read(syncSetupProgressProvider).liveCounts, isEmpty);

      // After 300ms + 2ms: counts appear.
      fake.elapse(const Duration(milliseconds: 2));
      final counts = container.read(syncSetupProgressProvider).liveCounts;
      expect(counts['members'], 3);
      expect(counts['chat_messages'], 104);
    });
  });

  test('multiple RemoteChanges within the throttle window merge', () {
    fakeAsync((fake) {
      final container = makeContainer();
      addTearDown(container.dispose);

      controller.add(_remoteChanges(['members', 'members']));
      fake.flushMicrotasks();

      fake.elapse(const Duration(milliseconds: 100));

      controller.add(_remoteChanges(['members']));
      fake.flushMicrotasks();

      fake.elapse(const Duration(milliseconds: 200));

      final counts = container.read(syncSetupProgressProvider).liveCounts;
      expect(counts['members'], 3);
    });
  });

  test('RemoteChanges during phase=finishing is dropped', () {
    fakeAsync((fake) {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(syncSetupProgressProvider.notifier);
      notifier.setPhase(PairingProgressPhase.downloading);
      notifier.setPhase(PairingProgressPhase.restoring);
      notifier.setPhase(PairingProgressPhase.finishing);

      controller.add(_remoteChanges(['members', 'members']));
      fake.flushMicrotasks();

      fake.elapse(const Duration(milliseconds: 400));

      expect(
        container.read(syncSetupProgressProvider).liveCounts,
        isEmpty,
      );
    });
  });

  test('phase advance flushes pending tally first', () {
    fakeAsync((fake) {
      final container = makeContainer();
      addTearDown(container.dispose);

      controller.add(_remoteChanges(['members', 'members']));
      fake.flushMicrotasks();

      // Only 100ms elapsed — throttle not yet fired.
      fake.elapse(const Duration(milliseconds: 100));
      expect(container.read(syncSetupProgressProvider).liveCounts, isEmpty);

      // Advancing phase flushes pending tally immediately.
      container.read(syncSetupProgressProvider.notifier).setPhase(
        PairingProgressPhase.downloading,
      );

      final s = container.read(syncSetupProgressProvider);
      expect(s.phase, PairingProgressPhase.downloading);
      expect(s.liveCounts['members'], 2);
    });
  });

  test('WebSocketStateChanged flips wsConnected', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    controller.add(_wsChanged(connected: true));
    await pump();
    expect(container.read(syncSetupProgressProvider).wsConnected, isTrue);

    controller.add(_wsChanged(connected: false));
    await pump();
    expect(container.read(syncSetupProgressProvider).wsConnected, isFalse);

    controller.add(_wsChanged(connected: true));
    await pump();
    expect(container.read(syncSetupProgressProvider).wsConnected, isTrue);
  });

  test('markTimedOut sets timedOut=true', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    container.read(syncSetupProgressProvider.notifier).markTimedOut();
    expect(container.read(syncSetupProgressProvider).timedOut, isTrue);
  });

  test('reset returns to fresh state and clears pending tally', () {
    fakeAsync((fake) {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(syncSetupProgressProvider.notifier);
      notifier.setPhase(PairingProgressPhase.restoring);

      controller.add(_remoteChanges(['members']));
      fake.flushMicrotasks();

      // Pending tally exists but not flushed yet.
      fake.elapse(const Duration(milliseconds: 100));

      notifier.reset();

      final s = container.read(syncSetupProgressProvider);
      expect(s.phase, PairingProgressPhase.connecting);
      expect(s.liveCounts, isEmpty);
      expect(s.timedOut, isFalse);

      // Elapse past where the old timer would have fired — no late flush.
      fake.elapse(const Duration(milliseconds: 400));
      expect(container.read(syncSetupProgressProvider).liveCounts, isEmpty);
    });
  });

  test('dispose cancels flush timer — no exceptions after dispose', () {
    fakeAsync((fake) {
      final container = makeContainer();

      controller.add(_remoteChanges(['members']));
      fake.flushMicrotasks();

      // Timer is scheduled but not fired.
      fake.elapse(const Duration(milliseconds: 100));

      container.dispose();

      // Elapse well past the timer duration — should not throw.
      fake.elapse(const Duration(milliseconds: 500));
    });
  });
}
