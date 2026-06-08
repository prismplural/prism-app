import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';

/// Operation type for a captured sync emission.
///
/// Mirrors the three FFI entry points (`recordCreate`, `recordUpdate`,
/// `recordDelete`). Used by the Phase 0 parity harness to record what the
/// FFI would have seen, and by the Phase 5 capture-replay path to re-emit
/// the exact tuples after a batched transaction commits.
enum SyncRecordOpType { create, update, delete }

/// A single sync emission captured under [SyncRecordMixin.suppressAndCapture].
///
/// Production callers (the Phase 5 SP-import path) receive these tuples via
/// the `capture` callback and replay them post-commit via `syncRecord*`.
/// The Phase 0 parity-test harness also uses these tuples via a test-only
/// install sink ([SyncRecordMixin.installCaptureSinkForTesting]).
class CapturedSyncOp {
  const CapturedSyncOp(this.table, this.entityId, this.opType, this.fields);

  final String table;
  final String entityId;
  final SyncRecordOpType opType;

  /// Empty map for [SyncRecordOpType.delete] (the FFI does not carry fields
  /// for deletes).
  final Map<String, dynamic> fields;
}

/// Test-only callback type: invoked once per intercepted sync emission.
typedef SyncRecordCaptureSink = void Function(CapturedSyncOp op);

/// Active suppression context, carried as a [Zone] value. `null` [capture]
/// drops emissions ([SyncRecordMixin.suppress]); a non-null [capture] receives
/// them instead of the FFI ([SyncRecordMixin.suppressAndCapture]).
class _SyncCaptureContext {
  const _SyncCaptureContext(this.capture);
  final void Function(CapturedSyncOp op)? capture;
}

/// Mixin for repositories that record mutations to the Rust sync engine.
///
/// The handle may exist (Rust side constructed) but the engine may not be
/// configured yet. This can happen briefly during startup because the app
/// publishes the raw handle before `configureEngine()` finishes so event
/// listeners can subscribe before auto-sync emits any early events. During
/// that window the FFI returns `engine error: sync not configured`.
///
/// A write dropped in that gap is user-visible: the local row exists, but no
/// `pending_op` is created until a later edit re-emits the entity. To close
/// that race, writes retry only while startup auto-config is actively in
/// progress, then fall back to the historical "skip quietly" behavior.
///
/// **Suppression mode** ([suppress] / [suppressAndCapture]). Destructive
/// bulk-rewrite paths (e.g. the fronting migration) write through repository
/// methods inside a Drift transaction without emitting CRDT ops — the Rust
/// engine commits to its own store, so an emission would survive a Drift
/// rollback and leak to peers. Suppression is [Zone]-scoped (see
/// [_captureZoneKey]), so it covers exactly the suppressed `body` and not
/// concurrent emissions from unrelated tasks.
mixin SyncRecordMixin {
  ffi.PrismSyncHandle? get syncHandle;

  static final List<CapturedSyncOp> _startupDeferredOps = <CapturedSyncOp>[];
  static bool _flushingStartupDeferredOps = false;

  /// Zone key for the active [_SyncCaptureContext]. As a zone value it follows
  /// the suppressed `body`'s async chain — including nested Drift transactions,
  /// whose executors fork child zones that inherit it — while a concurrent
  /// emission in another zone (e.g. a background sync during a member save) is
  /// unaffected.
  static const Object _captureZoneKey = #prismSyncCaptureContext;

  static _SyncCaptureContext? get _activeCaptureContext =>
      Zone.current[_captureZoneKey] as _SyncCaptureContext?;

  /// Whether the current async context is inside a [suppress] /
  /// [suppressAndCapture] body. Zone-scoped — reflects the caller's own
  /// suppression, not a process-wide flag. Exposed for tests that assert
  /// "suppression cleanly entered + exited."
  static bool get isSuppressed => _activeCaptureContext != null;

  /// Test-only sink that intercepts every sync emission before the FFI
  /// dispatch. Production code MUST NOT set this — the field is `null` in
  /// every shipped configuration. The Phase 0 SP-import parity harness sets
  /// it to record `(table, entityId, opType, fields)` tuples so it can
  /// assert `candidateEmissions.multiset == baselineEmissions.multiset`
  /// without relying on a live Rust sync engine.
  ///
  /// When set, the sink is invoked with the tuple that would have gone to
  /// the FFI; the FFI call is then **skipped**. This avoids needing a real
  /// `PrismSyncHandle` in tests. Combined with `syncHandle == null` it lets
  /// the harness exercise the full repository code path including the
  /// suppression early-return (an active suppression context → this sink is
  /// bypassed because the zone context handles the emission first; that's the
  /// intentional semantics tested by the `failing_tx` fixture).
  ///
  /// Use [installCaptureSinkForTesting] / [removeCaptureSinkForTesting] —
  /// never assign this field directly. The wrapper exists so tests can run
  /// concurrently without stomping each other and so static-analysis flags
  /// any accidental production use.
  static SyncRecordCaptureSink? _captureSink;

  /// Whether a test-only capture sink is currently installed. Tests can use
  /// this to assert clean install/remove pairing.
  @visibleForTesting
  static bool get hasCaptureSink => _captureSink != null;

  @visibleForTesting
  static int get debugStartupDeferredOpCount => _startupDeferredOps.length;

  @visibleForTesting
  static void debugClearStartupDeferredOpsForTesting() {
    _startupDeferredOps.clear();
    _flushingStartupDeferredOps = false;
  }

  /// Install a [SyncRecordCaptureSink]. Always returns `null` (the previous
  /// sink slot must be empty — see below).
  ///
  /// Production builds elide the install via `assert`; the capture sink is
  /// unreachable in release builds because Dart strips assert expressions
  /// entirely. Throws [StateError] if a sink is already installed — this
  /// protects against the default flutter-test isolate concurrency
  /// (>1) accidentally letting two parity tests steal each other's
  /// emissions. Tests that need re-entry must explicitly call
  /// [removeCaptureSinkForTesting] first.
  @visibleForTesting
  static SyncRecordCaptureSink? installCaptureSinkForTesting(
    SyncRecordCaptureSink sink,
  ) {
    assert(() {
      if (_captureSink != null) {
        throw StateError(
          'Capture sink already installed; another test forgot to remove or '
          'two parity tests are running concurrently',
        );
      }
      _captureSink = sink;
      return true;
    }());
    return null;
  }

  /// Remove any installed capture sink. Pass the prior sink (returned by
  /// [installCaptureSinkForTesting]) to restore a chained install; pass
  /// `null` to clear.
  ///
  /// Production builds elide the remove via `assert`; in release the capture
  /// sink is unreachable so this is a no-op anyway.
  @visibleForTesting
  static void removeCaptureSinkForTesting([SyncRecordCaptureSink? restore]) {
    assert(() {
      _captureSink = restore;
      return true;
    }());
  }

  /// Run [body] with every `syncRecord*` emission silently dropped. Used by
  /// the fronting migration so intra-transaction writes don't emit Rust
  /// pending_ops that would survive a Drift rollback. Zone-scoped (see
  /// [_captureZoneKey]): covers [body]'s async chain only. Nested inside a
  /// [suppressAndCapture], the drop shadows the outer capture (emissions do
  /// NOT bubble up). Use [suppressAndCapture] to receive the tuples instead.
  static Future<T> suppress<T>(Future<T> Function() body) {
    return runZoned(
      body,
      zoneValues: {_captureZoneKey: const _SyncCaptureContext(null)},
    );
  }

  /// Run [body] with every `syncRecord*` emission handed to [capture] instead
  /// of the FFI. Callers (the SP importer, [commitValueBatch]) collect the
  /// tuples during a Drift transaction and replay them post-commit, keeping
  /// the FFI off the transaction's critical path while preserving the per-row
  /// emission multiset. Zone-scoped (see [_captureZoneKey]): covers [body]'s
  /// async chain only, so a concurrent foreign emission isn't swept in. Nested
  /// calls shadow this context — an inner [suppressAndCapture] routes to its
  /// own sink, an inner [suppress] drops.
  static Future<T> suppressAndCapture<T>(
    Future<T> Function() body,
    void Function(CapturedSyncOp op) capture,
  ) {
    return runZoned(
      body,
      zoneValues: {_captureZoneKey: _SyncCaptureContext(capture)},
    );
  }

  /// Returns true if [error]'s string representation indicates the sync
  /// engine simply isn't configured (pre-pairing). Used to suppress log
  /// spam during onboarding and other unconfigured states.
  static bool _isNotConfigured(Object error) =>
      error.toString().contains('sync not configured');

  static void _deferStartupOp(CapturedSyncOp op) {
    _startupDeferredOps.add(op);
  }

  /// Replay sync emissions captured while startup configuration was in flight.
  static Future<void> flushStartupDeferredOps(
    ffi.PrismSyncHandle handle,
  ) async {
    if (_flushingStartupDeferredOps || _startupDeferredOps.isEmpty) return;
    _flushingStartupDeferredOps = true;
    try {
      while (_startupDeferredOps.isNotEmpty) {
        final op = _startupDeferredOps.removeAt(0);
        try {
          await _dispatchCapturedOp(handle, op);
        } catch (e, st) {
          ErrorReportingService.instance.report(
            'Deferred sync ${op.opType.name} failed: $e',
            severity: ErrorSeverity.error,
            stackTrace: st,
          );
        }
      }
    } finally {
      _flushingStartupDeferredOps = false;
    }
  }

  static Future<void> _dispatchCapturedOp(
    ffi.PrismSyncHandle handle,
    CapturedSyncOp op,
  ) {
    final payload = jsonEncode(op.fields);
    return switch (op.opType) {
      SyncRecordOpType.create => ffi.recordCreate(
        handle: handle,
        table: op.table,
        entityId: op.entityId,
        fieldsJson: payload,
      ),
      SyncRecordOpType.update => ffi.recordUpdate(
        handle: handle,
        table: op.table,
        entityId: op.entityId,
        changedFieldsJson: payload,
      ),
      SyncRecordOpType.delete => ffi.recordDelete(
        handle: handle,
        table: op.table,
        entityId: op.entityId,
      ),
    };
  }

  Future<void> _runWithConfiguredRetry(
    CapturedSyncOp op,
    Future<void> Function(ffi.PrismSyncHandle handle) attempt,
  ) async {
    final handle = syncCurrentHandle.value ?? syncHandle;
    if (handle == null) {
      if (syncAutoConfigureInProgress.value) {
        _deferStartupOp(op);
      }
      return;
    }
    try {
      await attempt(handle);
    } catch (e) {
      if (!_isNotConfigured(e)) {
        rethrow;
      }
      if (syncAutoConfigureInProgress.value) {
        _deferStartupOp(op);
      }
    }
  }

  /// Bulk variant of [_runWithConfiguredRetry]: runs one coalesced [attempt]
  /// when a handle is available, but defers EVERY op in [ops] (not just one) if
  /// the handle is missing mid-auto-configure. Each deferred op replays as an
  /// individual record on startup — correctness over coalescing on that rare
  /// path. Passing a single representative op here would silently drop the rest.
  Future<void> _runWithConfiguredRetryMulti(
    List<CapturedSyncOp> ops,
    Future<void> Function(ffi.PrismSyncHandle handle) attempt,
  ) async {
    final handle = syncCurrentHandle.value ?? syncHandle;
    if (handle == null) {
      if (syncAutoConfigureInProgress.value) {
        for (final op in ops) {
          _deferStartupOp(op);
        }
      }
      return;
    }
    try {
      await attempt(handle);
    } catch (e) {
      if (!_isNotConfigured(e)) {
        rethrow;
      }
      if (syncAutoConfigureInProgress.value) {
        for (final op in ops) {
          _deferStartupOp(op);
        }
      }
    }
  }

  @visibleForTesting
  Future<void> debugRunWithConfiguredRetryForTesting(
    CapturedSyncOp op,
    Future<void> Function(ffi.PrismSyncHandle handle) attempt,
  ) {
    return _runWithConfiguredRetry(op, attempt);
  }

  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final op = CapturedSyncOp(
      table,
      entityId,
      SyncRecordOpType.create,
      Map<String, dynamic>.of(fields),
    );
    final ctx = _activeCaptureContext;
    if (ctx != null) {
      ctx.capture?.call(op);
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      sink(op);
      return;
    }
    final payload = jsonEncode(fields);
    try {
      await _runWithConfiguredRetry(op, (handle) {
        return ffi.recordCreate(
          handle: handle,
          table: table,
          entityId: entityId,
          fieldsJson: payload,
        );
      });
    } catch (e, st) {
      // Sync-log emission is best-effort; user data has already been
      // persisted to Drift. Failure here must not surface to the UI.
      // Report once so the failure reaches `ErrorReportingService` (the
      // visibility motivation that originally introduced the rethrow),
      // then swallow — repository call sites do not catch and the user
      // shouldn't see "save failed" toasts for sync emission errors.
      ErrorReportingService.instance.report(
        'Sync recordCreate failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
    }
  }

  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final op = CapturedSyncOp(
      table,
      entityId,
      SyncRecordOpType.update,
      Map<String, dynamic>.of(fields),
    );
    final ctx = _activeCaptureContext;
    if (ctx != null) {
      ctx.capture?.call(op);
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      sink(op);
      return;
    }
    final payload = jsonEncode(fields);
    try {
      await _runWithConfiguredRetry(op, (handle) {
        return ffi.recordUpdate(
          handle: handle,
          table: table,
          entityId: entityId,
          changedFieldsJson: payload,
        );
      });
    } catch (e, st) {
      // Sync-log emission is best-effort; user data has already been
      // persisted to Drift. Failure here must not surface to the UI.
      ErrorReportingService.instance.report(
        'Sync recordUpdate failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
    }
  }

  Future<void> syncRecordDelete(String table, String entityId) async {
    final op = CapturedSyncOp(
      table,
      entityId,
      SyncRecordOpType.delete,
      const <String, dynamic>{},
    );
    final ctx = _activeCaptureContext;
    if (ctx != null) {
      ctx.capture?.call(op);
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      sink(op);
      return;
    }
    try {
      await _runWithConfiguredRetry(op, (handle) {
        return ffi.recordDelete(
          handle: handle,
          table: table,
          entityId: entityId,
        );
      });
    } catch (e, st) {
      // Sync-log emission is best-effort; user data has already been
      // persisted to Drift. Failure here must not surface to the UI.
      ErrorReportingService.instance.report(
        'Sync recordDelete failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
    }
  }

  /// Delete many entities of one [table] in a single coalesced FFI call, so the
  /// engine packs their tombstones into a few batches instead of one push per
  /// row. Use for bulk deletes (clearing a list, deleting a group's members).
  ///
  /// Suppress/capture paths still record one op per entity so replay stays
  /// row-granular; only the live emission is coalesced.
  Future<void> syncRecordDeleteMulti(String table, List<String> entityIds) async {
    if (entityIds.isEmpty) {
      return;
    }
    CapturedSyncOp opFor(String id) =>
        CapturedSyncOp(table, id, SyncRecordOpType.delete, const <String, dynamic>{});

    final ctx = _activeCaptureContext;
    if (ctx != null) {
      final capture = ctx.capture;
      if (capture != null) {
        for (final id in entityIds) {
          capture(opFor(id));
        }
      }
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      for (final id in entityIds) {
        sink(opFor(id));
      }
      return;
    }
    try {
      await _runWithConfiguredRetryMulti([
        for (final id in entityIds) opFor(id),
      ], (handle) {
        return ffi.recordDeleteMulti(
          handle: handle,
          table: table,
          entityIds: entityIds,
        );
      });
    } catch (e, st) {
      // Sync-log emission is best-effort; user data has already been
      // persisted to Drift. Failure here must not surface to the UI.
      ErrorReportingService.instance.report(
        'Sync recordDeleteMulti failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
    }
  }

  /// Replay [ops] through the live FFI path, in capture order — the post-commit
  /// half of the capture-then-replay pattern ([suppressAndCapture] captures
  /// inside a Drift transaction, this re-emits after it durably commits). Each
  /// op re-dispatches through the same `syncRecord*` entry point with its
  /// original type and `fields`.
  ///
  /// Caught per-op so one bad row can't abort the rest: `syncRecord*` swallows
  /// FFI errors internally, but a few edge cases still throw (e.g. `jsonEncode`
  /// on a non-serializable payload). Failures are reported (warning) and
  /// returned — the local DB is already correct; only the peer emission for a
  /// returned op didn't go out. [logLabel] prefixes the telemetry. Callers that
  /// hold the emitter as an interface type must gate on `is SyncRecordMixin`.
  Future<List<CapturedSyncOp>> replayCapturedOps(
    List<CapturedSyncOp> ops, {
    String logLabel = 'Sync',
  }) async {
    final failures = <CapturedSyncOp>[];
    for (final op in ops) {
      try {
        switch (op.opType) {
          case SyncRecordOpType.create:
            await syncRecordCreate(op.table, op.entityId, op.fields);
          case SyncRecordOpType.update:
            await syncRecordUpdate(op.table, op.entityId, op.fields);
          case SyncRecordOpType.delete:
            await syncRecordDelete(op.table, op.entityId);
        }
      } catch (e, st) {
        failures.add(op);
        ErrorReportingService.instance.report(
          '$logLabel replay failed for ${op.table}/${op.entityId}: $e',
          severity: ErrorSeverity.warning,
          stackTrace: st,
        );
      }
    }
    return failures;
  }

  /// Run [body] with all sync ops logically grouped into one batch.
  ///
  /// Callers should wrap multi-entity sync emissions in this helper so that
  /// peers see the writes as a single CRDT action. The Drift transaction that
  /// surrounds the DB writes must be opened by the caller — this helper only
  /// governs the sync emission side.
  ///
  /// **Current limitation:** the Rust FFI does not yet expose a batch-begin /
  /// batch-end API, so each `syncRecord*` call inside [body] still receives
  /// its own `local_batch_id` from the engine. This wrapper establishes the
  /// call-site pattern and will be wired to a real FFI batch fence once the
  /// Rust layer exposes one.
  Future<T> withSyncBatch<T>(Future<T> Function() body) async {
    return body();
  }
}
