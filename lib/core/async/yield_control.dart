import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Cooperative scheduling helper for background work that runs on the **main
/// isolate** (which it must: these loops touch Drift DAOs and Rust FFI handles,
/// neither of which is safe to move to another isolate).
///
/// Awaiting a future only yields to the *microtask* queue — and the Flutter
/// engine does not drain the platform event queue, and therefore does not draw
/// a frame or service input, until the microtask queue empties. A background
/// loop that chains thousands of microtask continuations (one per row, chunk,
/// or media id) can therefore hold the main isolate past Android's ANR window
/// even though it "awaits" all the way through.
///
/// Note on how much this is worth today: the production app opens Drift with
/// `NativeDatabase.createInBackground`, so each DAO call in these loops already
/// awaits a cross-isolate reply, which ordinarily gives the event loop a turn.
/// The explicit yield is therefore a *guarantee*, not the current sole source of
/// responsiveness: it keeps the property from silently regressing if a read
/// becomes synchronous/cached, or if the database is opened in-isolate.
///
/// [yieldToEventLoop] hops the *event* queue once, so pending frames, gestures,
/// and platform messages get a turn between batches of work. It is deliberately
/// cheap: call it every N items of a loop, never per item.
Future<void> yieldToEventLoop() => debugYieldOverride();

/// Test seam: lets a test count (or suppress) yields deterministically instead
/// of relying on real timers. Mirrors the existing
/// `debugDrainRemoteDeliveriesOverride` pattern. Production never sets it.
@visibleForTesting
Future<void> Function() debugYieldOverride = _defaultYield;

Future<void> _defaultYield() => Future<void>.delayed(Duration.zero);

/// Restore the real yield implementation (call from test `tearDown`).
@visibleForTesting
void debugResetYieldOverride() {
  debugYieldOverride = _defaultYield;
}

/// Yields to the event loop after every [workUnits] units of work in a
/// cooperative loop.
///
/// A *unit* is one iteration's worth of main-isolate work (one drained row, one
/// applied chunk, one enqueued media id) — not one item of the underlying
/// collection. Count whole units with [countUnit] and let this class decide when
/// the accumulated work warrants a turn; a unit that fans out over several items
/// should count as several units, so the yield cadence is tied to real work
/// rather than to iteration count.
class CooperativeYield {
  CooperativeYield({this.workUnits = 1})
    : assert(workUnits >= 1, 'workUnits must be >= 1');

  /// Main-isolate work units to accumulate before yielding. Chosen small enough
  /// that a single batch stays well inside a frame budget on a slow Android
  /// device, and large enough that the event-queue hop is negligible against the
  /// per-unit work (each unit here is at least one database round trip).
  final int workUnits;

  int _sinceYield = 0;

  /// Record [units] units of work; returns true when the caller must
  /// `await yieldToEventLoop()` before continuing.
  bool countUnit([int units = 1]) {
    assert(units > 0, 'units must be > 0');
    _sinceYield += units;
    return _sinceYield >= workUnits;
  }

  /// Yield to the event loop if [countUnit] said so, then reset the counter.
  ///
  /// Usage:
  /// ```dart
  /// if (yielder.countUnit()) await yielder.yieldNow();
  /// ```
  Future<void> yieldNow() {
    _sinceYield = 0;
    return yieldToEventLoop();
  }

  /// Drop any accumulated work without yielding — for loops that must not
  /// straddle an event-loop turn (e.g. a final chunk whose durability ordering
  /// depends on completing in the same turn).
  void reset() => _sinceYield = 0;
}
