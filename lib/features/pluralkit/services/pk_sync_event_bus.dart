import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pk_sync_event.dart';

/// Process-wide broadcast bus for [PkSyncEvent]s.
///
/// PluralKit sync activity is emitted from multiple call sites (main sync
/// service, mapping applier, request queue, auto-poll notifier). They all push
/// onto a shared bus and the debug-log notifier listens to it. We use a
/// `broadcast` controller because there are several listeners over time (the
/// notifier plus any test capture) and we never want emissions to back-pressure
/// the sync layer.
///
/// Emits are guarded by two checks:
///   1. [_isPkBusMainIsolate] — must be flipped to `true` in `main()` via
///      [markPkBusMainIsolate]. The workmanager background isolate cannot
///      reach a `StreamController` created on the main isolate, so any emit
///      from a background isolate would crash or leak. The flag stays `false`
///      in background isolates, so emits silently no-op there.
///   2. [_controller.isClosed] — once the bus is disposed (e.g., via the
///      Riverpod `ref.onDispose` hook on [pkSyncEventBusProvider]), late
///      emissions from in-flight callers are dropped instead of throwing.
class PkSyncEventBus {
  PkSyncEventBus();

  final StreamController<PkSyncEvent> _controller =
      StreamController<PkSyncEvent>.broadcast();

  /// Broadcast stream of every [PkSyncEvent] emitted since this bus was
  /// constructed. Broadcast semantics: listeners only see events emitted while
  /// they are subscribed.
  Stream<PkSyncEvent> get stream => _controller.stream;

  /// Adds [event] to [stream], unless the bus is closed or this isolate hasn't
  /// been marked as the main isolate. Never throws.
  void emit(PkSyncEvent event) {
    if (!_isPkBusMainIsolate) return;
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  /// Closes the underlying stream controller. Safe to call multiple times —
  /// subsequent [emit] calls become silent no-ops.
  void dispose() {
    if (_controller.isClosed) return;
    _controller.close();
  }
}

/// Whether this isolate is the main (UI) isolate.
///
/// Defaults to `false` so that any isolate that hasn't been explicitly marked
/// (e.g., the workmanager background isolate that runs `callbackDispatcher`)
/// will silently drop emits instead of crashing or leaking a stream
/// controller across isolate boundaries.
bool _isPkBusMainIsolate = false;

/// Marks this isolate as the main isolate so [PkSyncEventBus.emit] will
/// actually deliver events. Call this once from `main()` before `runApp`.
void markPkBusMainIsolate() {
  _isPkBusMainIsolate = true;
}

/// Test-only helper to flip the main-isolate flag back to `false`.
///
/// Tests that emit events typically call [markPkBusMainIsolate] in `setUp`;
/// without a corresponding reset in `tearDown`, the flag leaks into sibling
/// test files and produces order-dependent suites.
@visibleForTesting
void resetPkBusMainIsolateForTest() {
  _isPkBusMainIsolate = false;
}

/// Riverpod provider exposing the app-wide [PkSyncEventBus].
///
/// The bus is constructed lazily on first read and disposed automatically when
/// the surrounding container is torn down.
final pkSyncEventBusProvider = Provider<PkSyncEventBus>((ref) {
  final bus = PkSyncEventBus();
  ref.onDispose(bus.dispose);
  return bus;
});

/// Test helper that wraps a real [PkSyncEventBus] and mirrors every emission
/// into [events] for synchronous assertion in tests.
///
/// Usage:
/// ```dart
/// final capture = PkSyncEventBusCapture();
/// final container = ProviderContainer(overrides: [
///   pkSyncEventBusProvider.overrideWithValue(capture.bus),
/// ]);
/// // ... drive code that emits ...
/// expect(capture.events, hasLength(2));
/// ```
@visibleForTesting
class PkSyncEventBusCapture {
  PkSyncEventBusCapture() : bus = _RecordingPkSyncEventBus() {
    (bus as _RecordingPkSyncEventBus)._sink = events;
  }

  /// Backing bus to inject into production code under test. Behaves exactly
  /// like a normal [PkSyncEventBus] — same guards, same broadcast semantics —
  /// but ALSO appends every successful emit to [events] so tests can assert
  /// directly on a `List<PkSyncEvent>` without subscribing to the stream.
  final PkSyncEventBus bus;

  /// Every [PkSyncEvent] that was delivered through [bus]. Append order
  /// matches emit order.
  final List<PkSyncEvent> events = <PkSyncEvent>[];
}

/// Internal: a [PkSyncEventBus] that ALSO records every delivered emit into a
/// caller-supplied list. Used only by [PkSyncEventBusCapture].
class _RecordingPkSyncEventBus extends PkSyncEventBus {
  _RecordingPkSyncEventBus();

  late final List<PkSyncEvent> _sink;

  @override
  void emit(PkSyncEvent event) {
    if (!_isPkBusMainIsolate) return;
    if (_controller.isClosed) return;
    _sink.add(event);
    _controller.add(event);
  }
}
