/// `SyncRecordMixin` tests.
///
/// Pins two contracts:
///
/// 1. The suppression contract used by the per-member fronting migration:
///    - [SyncRecordMixin.suppress] short-circuits every `syncRecord*`
///      call so the FFI never runs while the body executes.
///    - Outside `suppress`, the mixin behaves as before.
///    - The flag clears even if the body throws (verified via a probe
///      repository that records every FFI invocation).
///
/// 2. The best-effort failure contract (Workstream 2 step 3,
///    remediation-plan-2026-04-30): when the underlying FFI call throws,
///    the mixin reports to `ErrorReportingService` exactly once and
///    swallows the exception. User data has already been persisted to
///    Drift; sync-log emission is best-effort and must not surface as a
///    write failure to the UI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

void main() {
  tearDown(() {
    SyncRecordMixin.debugClearStartupDeferredOpsForTesting();
    syncAutoConfigureInProgress.value = false;
    syncCurrentHandle.value = null;
  });

  group('SyncRecordMixin.suppress', () {
    test(
      'short-circuits syncRecordCreate / Update / Delete inside body',
      () async {
        final repo = _ProbeRepository();

        // Sanity: outside `suppress`, the calls flow through the
        // _runWithConfiguredRetry wrapper. We can't actually hit the FFI
        // in tests (no Rust handle), but we can prove the suppression
        // gate by asserting that the per-call entry point ran or didn't.
        // Pre-suppression: a call with a null handle returns silently
        // but never sets `_probeMarker` because we never reach inside
        // the function body. Replace the marker assertion with a counter
        // tracked via the wrapper — see _ProbeRepository.

        expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'pre-suppress');

        await SyncRecordMixin.suppress(() async {
          expect(
            SyncRecordMixin.isSuppressed,
            isTrue,
            reason: 'inside suppress',
          );
          await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
          await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
          await repo.syncRecordDelete('members', 'm1');
        });

        expect(SyncRecordMixin.isSuppressed, isFalse, reason: 'post-suppress');

        // Probe repo had a non-null handle stub but the mixin's early
        // return prevented it from being read. The probe asserts via
        // `handleAccessCount` how many times the wrapper got past the
        // suppression gate.
        expect(
          repo.handleAccessCount,
          0,
          reason:
              'no syncRecord* call should reach the FFI gate while suppressed',
        );
      },
    );

    test('flag clears after body throws', () async {
      expect(SyncRecordMixin.isSuppressed, isFalse);

      Object? caught;
      try {
        await SyncRecordMixin.suppress<void>(() async {
          throw StateError('boom');
        });
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<StateError>());
      expect(
        SyncRecordMixin.isSuppressed,
        isFalse,
        reason: 'finally block must reset the flag even on throw',
      );
    });

    test('nested suppress blocks restore the previous value', () async {
      // Outer suppress → inner suppress → inner exits → outer still
      // suppressed → outer exits → flag clears.
      await SyncRecordMixin.suppress(() async {
        expect(SyncRecordMixin.isSuppressed, isTrue);
        await SyncRecordMixin.suppress(() async {
          expect(SyncRecordMixin.isSuppressed, isTrue);
        });
        expect(
          SyncRecordMixin.isSuppressed,
          isTrue,
          reason: 'inner suppress exit must not clear outer flag',
        );
      });
      expect(SyncRecordMixin.isSuppressed, isFalse);
    });

    test(
      'passes calls through when not suppressed (handle = null branch)',
      () async {
        final repo = _ProbeRepository();
        // Outside suppress: the wrapper calls the syncHandle getter
        // exactly once per record method. With a null handle the wrapper
        // returns early — that's the historical "skip quietly" behavior
        // we keep alongside the new suppression gate.
        await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        await repo.syncRecordDelete('members', 'm1');
        expect(
          repo.handleAccessCount,
          3,
          reason:
              'unsuppressed calls reach the FFI gate (and exit early '
              'on null handle)',
        );
      },
    );
  });

  group('SyncRecordMixin best-effort failure contract', () {
    // Workstream 2 step 3 (remediation-plan-2026-04-30): an FFI failure
    // must not surface to the UI. The user data has already been written
    // to Drift; sync-log emission is best-effort, so the mixin reports
    // once and swallows. A throwing `syncHandle` getter is the simplest
    // way to drive the catch path in tests — the throw originates inside
    // `_runWithConfiguredRetry` (line `final handle = syncHandle;`),
    // propagates to the outer try/catch in each `syncRecord*` method,
    // and gets reported via `ErrorReportingService.report`.

    late List<AppError> reported;
    late ErrorListener listener;

    setUp(() {
      reported = <AppError>[];
      listener = (e) => reported.add(e);
      ErrorReportingService.instance.addListener(listener);
    });

    tearDown(() {
      ErrorReportingService.instance.removeListener(listener);
    });

    test('syncRecordCreate swallows FFI failure and reports once', () async {
      final repo = _ThrowingHandleRepository();
      await repo.syncRecordCreate('members', 'm1', const <String, dynamic>{});
      expect(
        reported.where((e) => e.message.contains('recordCreate')),
        hasLength(1),
        reason: 'failure must be reported exactly once per failed FFI call',
      );
    });

    test('syncRecordUpdate swallows FFI failure and reports once', () async {
      final repo = _ThrowingHandleRepository();
      await repo.syncRecordUpdate('members', 'm1', const <String, dynamic>{});
      expect(
        reported.where((e) => e.message.contains('recordUpdate')),
        hasLength(1),
      );
    });

    test('syncRecordDelete swallows FFI failure and reports once', () async {
      final repo = _ThrowingHandleRepository();
      await repo.syncRecordDelete('members', 'm1');
      expect(
        reported.where((e) => e.message.contains('recordDelete')),
        hasLength(1),
      );
    });

    test('syncRecordDeleteMulti swallows FFI failure and reports once', () async {
      final repo = _ThrowingHandleRepository();
      await repo.syncRecordDeleteMulti('members', const ['m1', 'm2', 'm3']);
      // One coalesced FFI call for the whole list — one report, not one per id.
      expect(
        reported.where((e) => e.message.contains('recordDeleteMulti')),
        hasLength(1),
      );
    });
  });

  group('SyncRecordMixin startup deferred ops', () {
    test(
      'queues record update when startup is configuring with no handle',
      () async {
        final repo = _ProbeRepository();
        syncAutoConfigureInProgress.value = true;

        await repo.syncRecordUpdate('members', 'm1', {
          'avatar_image_data': 'base64-avatar',
        });

        expect(repo.handleAccessCount, 1);
        expect(SyncRecordMixin.debugStartupDeferredOpCount, 1);
      },
    );

    test('queues provisional-handle sync-not-configured failures', () async {
      final repo = _FixedHandleRepository(const _FakePrismSyncHandle());
      syncAutoConfigureInProgress.value = true;

      await repo.debugRunWithConfiguredRetryForTesting(
        const CapturedSyncOp('members', 'm1', SyncRecordOpType.update, {
          'profile_header_image_data': 'base64-banner',
        }),
        (_) async => throw StateError('sync not configured'),
      );

      expect(SyncRecordMixin.debugStartupDeferredOpCount, 1);
    });

    test('keeps local-only null-handle behavior outside startup', () async {
      final repo = _ProbeRepository();

      await repo.syncRecordUpdate('members', 'm1', {'name': 'Later'});

      expect(repo.handleAccessCount, 1);
      expect(SyncRecordMixin.debugStartupDeferredOpCount, 0);
    });

    test(
      'syncRecordDeleteMulti defers every entity (not just the first) '
      'when startup is configuring',
      () async {
        final repo = _ProbeRepository();
        syncAutoConfigureInProgress.value = true;

        await repo.syncRecordDeleteMulti('members', const ['m1', 'm2', 'm3']);

        // Regression guard: the bulk path must defer ALL ids on the startup
        // window, or N-1 deletes are silently dropped.
        expect(SyncRecordMixin.debugStartupDeferredOpCount, 3);
      },
    );
  });

  group('SyncRecordMixin.suppressAndCapture', () {
    // `suppress` drops emissions; `suppressAndCapture` routes them to a sink.

    test('plain suppress drops emissions', () async {
      final repo = _ProbeRepository();
      await SyncRecordMixin.suppress(() async {
        await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        await repo.syncRecordDelete('members', 'm1');
      });
      // No FFI hops (handleAccessCount == 0) AND no captured tuples to
      // verify — the only sink that could observe them is the
      // _suppressCapture which was cleared by `suppress`.
      expect(repo.handleAccessCount, 0);
    });

    test('suppressAndCapture routes emissions to its sink', () async {
      final repo = _ProbeRepository();
      final captured = <CapturedSyncOp>[];
      await SyncRecordMixin.suppressAndCapture(() async {
        await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        await repo.syncRecordDelete('members', 'm1');
      }, captured.add);
      expect(captured, hasLength(3));
      expect(captured[0].opType, SyncRecordOpType.create);
      expect(captured[0].table, 'members');
      expect(captured[0].entityId, 'm1');
      expect(captured[0].fields, {'name': 'A'});
      expect(captured[1].opType, SyncRecordOpType.update);
      expect(captured[1].fields, {'name': 'B'});
      expect(captured[2].opType, SyncRecordOpType.delete);
      expect(captured[2].fields, isEmpty);
      // Suppression gate fired — no FFI access.
      expect(repo.handleAccessCount, 0);
    });

    test(
      'nested suppress inside suppressAndCapture drops inner emissions',
      () async {
        final repo = _ProbeRepository();
        final outer = <CapturedSyncOp>[];

        await SyncRecordMixin.suppressAndCapture(() async {
          // Outer-level emission goes to outer sink.
          await repo.syncRecordCreate('members', 'outer', {'k': 'v'});
          // Inner explicit-drop block; emissions here must NOT bubble.
          await SyncRecordMixin.suppress(() async {
            await repo.syncRecordCreate('members', 'inner', {'k': 'v'});
            await repo.syncRecordUpdate('members', 'inner', {'k': 'v2'});
          });
          // Back at outer level after suppress exits — outer sink active.
          await repo.syncRecordDelete('members', 'outer-2');
        }, outer.add);

        expect(
          outer.map((o) => o.entityId),
          ['outer', 'outer-2'],
          reason: 'inner suppress emissions must be dropped, not captured',
        );
        expect(outer[0].opType, SyncRecordOpType.create);
        expect(outer[1].opType, SyncRecordOpType.delete);
      },
    );

    test(
      'nested suppressAndCapture routes emissions to the innermost sink',
      () async {
        final repo = _ProbeRepository();
        final outer = <CapturedSyncOp>[];
        final inner = <CapturedSyncOp>[];

        await SyncRecordMixin.suppressAndCapture(() async {
          await repo.syncRecordCreate('members', 'outer', {'k': 'v'});
          await SyncRecordMixin.suppressAndCapture(() async {
            await repo.syncRecordCreate('members', 'inner', {'k': 'v'});
          }, inner.add);
          await repo.syncRecordDelete('members', 'outer-2');
        }, outer.add);

        expect(
          inner.map((o) => o.entityId),
          ['inner'],
          reason: 'inner sink receives only the inner block emission',
        );
        expect(
          outer.map((o) => o.entityId),
          ['outer', 'outer-2'],
          reason: 'outer sink receives only its own-level emissions',
        );
      },
    );

    test('suppressAndCapture clears the sink on body throw', () async {
      final repo = _ProbeRepository();
      final captured = <CapturedSyncOp>[];

      Object? caught;
      try {
        await SyncRecordMixin.suppressAndCapture<void>(() async {
          await repo.syncRecordCreate('members', 'm1', {'k': 'v'});
          throw StateError('boom');
        }, captured.add);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
      // The one emission before the throw was captured…
      expect(captured, hasLength(1));
      // …but the suppression + capture sink are reset.
      expect(SyncRecordMixin.isSuppressed, isFalse);

      // A subsequent un-suppressed call must reach the FFI gate.
      await repo.syncRecordCreate('members', 'm2', {'k': 'v'});
      expect(repo.handleAccessCount, 1);
    });
  });

  group('SyncRecordMixin capture sink install/remove guard', () {
    // Parallel tests must not overwrite each other's capture sink.

    tearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    test('install throws StateError when a sink is already installed', () {
      void sinkA(CapturedSyncOp op) {}
      void sinkB(CapturedSyncOp op) {}

      SyncRecordMixin.installCaptureSinkForTesting(sinkA);
      expect(SyncRecordMixin.hasCaptureSink, isTrue);

      expect(
        () => SyncRecordMixin.installCaptureSinkForTesting(sinkB),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Capture sink already installed'),
          ),
        ),
      );

      SyncRecordMixin.removeCaptureSinkForTesting();
      expect(SyncRecordMixin.hasCaptureSink, isFalse);

      // After remove, install is permitted again.
      SyncRecordMixin.installCaptureSinkForTesting(sinkB);
      expect(SyncRecordMixin.hasCaptureSink, isTrue);
      SyncRecordMixin.removeCaptureSinkForTesting();
    });
  });
}

/// Test double that exposes a counter on the syncHandle getter so we
/// can prove the suppression gate fires before the wrapper starts
/// inspecting the handle.
class _ProbeRepository with SyncRecordMixin {
  int handleAccessCount = 0;

  @override
  ffi.PrismSyncHandle? get syncHandle {
    handleAccessCount++;
    return null;
  }
}

class _FixedHandleRepository with SyncRecordMixin {
  _FixedHandleRepository(this._handle);

  final ffi.PrismSyncHandle _handle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _handle;
}

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test double whose `syncHandle` getter throws on access. The throw
/// propagates out of `_runWithConfiguredRetry` (it happens before the
/// inner try/catch), gets caught by the outer try/catch in
/// `syncRecord{Create,Update,Delete}`, and exercises the best-effort
/// log-and-swallow path.
class _ThrowingHandleRepository with SyncRecordMixin {
  @override
  ffi.PrismSyncHandle? get syncHandle =>
      throw StateError('simulated FFI failure');
}
