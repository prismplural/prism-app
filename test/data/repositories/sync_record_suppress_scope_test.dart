// Zone-scoping contract for SyncRecordMixin.suppress / suppressAndCapture.
//
// The hazard guarded against: suppression used to be a process-wide static
// flag, so an emission from an unrelated concurrent task running during one of
// the suppressed body's `await` gaps could be wrongly captured/dropped. It is
// now Zone-scoped — it follows the body's async causal chain only. These tests
// prove a foreign emission in a different zone is neither captured nor
// suppressed.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// Minimal real-path [SyncRecordMixin] host. No `syncRecord*` overrides, so the
/// actual zone-context / capture-sink / suppression logic runs. `syncHandle`
/// is null, so a non-suppressed, non-captured emission is a harmless no-op.
class _Emitter with SyncRecordMixin {
  @override
  ffi.PrismSyncHandle? get syncHandle => null;
}

void main() {
  setUp(() {
    // Each test installs its own sink; guarantee a clean slot.
    expect(SyncRecordMixin.hasCaptureSink, isFalse);
  });

  test(
    'a foreign emission in a different zone during the body is NOT captured',
    () async {
      final a = _Emitter();
      final foreign = _Emitter();

      // The test capture sink fires only when suppression is NOT active in the
      // caller's zone — so it observes exactly what escaped the batch capture.
      final escaped = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(escaped.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final captured = <CapturedSyncOp>[];
      await SyncRecordMixin.suppressAndCapture(() async {
        // Our own write, in the suppressed zone → captured.
        await a.syncRecordCreate('values', 'mine', {'v': 1});
        // A background task's emission, running in the ROOT zone (as a real
        // concurrent timer/microtask would) → must bypass our capture.
        await Zone.root.run(
          () => foreign.syncRecordCreate('members', 'foreign', {'n': 2}),
        );
      }, captured.add);

      // Capture saw only our op; the foreign op did NOT leak in.
      expect(captured.map((o) => o.entityId), ['mine']);
      // The foreign op escaped to the normal (FFI/sink) path, with its own
      // identity intact — not suppressed, not misrouted.
      expect(escaped.map((o) => o.entityId), ['foreign']);
    },
  );

  test('isSuppressed is zone-scoped (true inside body, false in a root-zone '
      'callback and after exit)', () async {
    expect(SyncRecordMixin.isSuppressed, isFalse);

    bool? insideBody;
    bool? insideForeignZone;
    await SyncRecordMixin.suppressAndCapture(() async {
      insideBody = SyncRecordMixin.isSuppressed;
      await Zone.root.run(() async {
        insideForeignZone = SyncRecordMixin.isSuppressed;
      });
    }, (_) {});

    expect(insideBody, isTrue);
    expect(insideForeignZone, isFalse);
    expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'exited cleanly');
  });

  test('suppress drops emissions from its own causal chain', () async {
    final e = _Emitter();
    final escaped = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(escaped.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await SyncRecordMixin.suppress(() async {
      await e.syncRecordCreate('values', 'dropped', {});
    });

    expect(escaped, isEmpty, reason: 'suppress drops, never reaches the sink');
  });

  test('nested suppress inside suppressAndCapture drops (does not bubble to '
      'the outer capture)', () async {
    final e = _Emitter();
    final outer = <CapturedSyncOp>[];

    await SyncRecordMixin.suppressAndCapture(() async {
      await e.syncRecordCreate('values', 'captured', {});
      await SyncRecordMixin.suppress(() async {
        await e.syncRecordCreate('values', 'dropped', {});
      });
    }, outer.add);

    expect(outer.map((o) => o.entityId), ['captured']);
  });

  test('nested suppressAndCapture routes inner ops to the inner sink only',
      () async {
    final e = _Emitter();
    final outer = <CapturedSyncOp>[];
    final inner = <CapturedSyncOp>[];

    await SyncRecordMixin.suppressAndCapture(() async {
      await e.syncRecordCreate('values', 'outer', {});
      await SyncRecordMixin.suppressAndCapture(() async {
        await e.syncRecordCreate('values', 'inner', {});
      }, inner.add);
    }, outer.add);

    expect(outer.map((o) => o.entityId), ['outer']);
    expect(inner.map((o) => o.entityId), ['inner']);
  });

  test('a throwing body propagates and the suppression zone still exits',
      () async {
    expect(SyncRecordMixin.isSuppressed, isFalse);
    await expectLater(
      SyncRecordMixin.suppressAndCapture(() async {
        throw StateError('boom');
      }, (_) {}),
      throwsStateError,
    );
    expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'zone torn down');
  });
}
