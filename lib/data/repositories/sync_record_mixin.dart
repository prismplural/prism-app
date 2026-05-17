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
/// **Suppression mode** ([SyncRecordMixin.suppress]). The fronting migration
/// (and any future destructive bulk-rewrite path) needs to write to repository
/// methods inside a Drift transaction WITHOUT emitting CRDT ops to the Rust
/// engine — because the Rust engine commits to its own SQLite store, those
/// ops would survive a Drift rollback and could leak to peers via auto-sync
/// before the migration's `reset_sync_state` cutover runs. While
/// `_suppressed` is true, every record method early-returns without touching
/// the FFI. Process-wide static flag is sufficient — Dart UI is single-isolate
/// and the migration runs mutually-exclusive with normal user activity.
mixin SyncRecordMixin {
  ffi.PrismSyncHandle? get syncHandle;

  static const int _notConfiguredRetryAttempts = 10;
  static const Duration _notConfiguredRetryDelay = Duration(milliseconds: 100);

  /// While `true`, every `syncRecord*` call short-circuits before the FFI.
  /// Toggled exclusively via [suppress]; never written directly.
  static bool _suppressed = false;

  /// Returns whether suppression is currently active. Exposed for tests
  /// that want to assert "suppression cleanly entered + exited."
  static bool get isSuppressed => _suppressed;

  /// Optional capture sink wired in by [suppressAndCapture]. When active,
  /// every `syncRecord{Create,Update,Delete}` call inside the suppress
  /// block hands its tuple to this sink *instead of* dropping it silently.
  /// Used by the Phase 5 SP-import capture-replay path
  /// (`docs/plans/sp-import-perf-quick-wins.md`) — the importer wraps its
  /// transaction in `suppressAndCapture(body, list.add)`, then replays each
  /// captured tuple post-commit so per-row FFI dispatch happens after the
  /// transaction has committed (zero FFI hops inside the transaction).
  ///
  /// This is distinct from [_captureSink] (the test-only harness sink set
  /// via [installCaptureSinkForTesting]). The harness sink intercepts
  /// emissions when suppress is NOT active; this sink intercepts emissions
  /// when suppress IS active. They never run together — if [_suppressed] is
  /// true the harness sink is bypassed by the early-return.
  ///
  /// Production code may set this only via [suppressAndCapture]; the field
  /// is cleared in the `finally` of [suppress] and [suppressAndCapture].
  static void Function(CapturedSyncOp op)? _suppressCapture;

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
  /// suppression early-return (`_suppressed == true` → no capture either,
  /// because suppression bypasses everything; that's the intentional
  /// semantics tested by the `failing_tx` fixture).
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

  /// Run [body] with sync emission suppressed.
  ///
  /// Used by the per-member fronting migration (`fronting_migration_service`)
  /// so the intra-transaction repository writes don't emit Rust pending_ops
  /// that would survive a Drift rollback. The `try`/`finally` ensures the
  /// flag clears even if [body] throws — propagating the original exception.
  ///
  /// **Semantic: drop emissions.** Every `syncRecord{Create,Update,Delete}`
  /// invocation inside [body] is silently dropped. Use [suppressAndCapture]
  /// instead if you want to receive the would-be tuples (e.g., for the
  /// Phase 5 SP-import post-commit replay path).
  ///
  /// **Nested suppress.** If [body] is itself running inside an outer
  /// `suppressAndCapture(..., outerSink)` and calls `suppress(...)`, the
  /// inner emissions are explicitly dropped — they do NOT bubble up to
  /// `outerSink`. This preserves the historical "I am suppressing this
  /// sub-operation entirely" intent at call sites that nest a drop inside a
  /// capture. The prior sink is restored on exit.
  static Future<T> suppress<T>(Future<T> Function() body) async {
    final wasSuppressed = _suppressed;
    final priorCapture = _suppressCapture;
    _suppressed = true;
    // Explicit-drop semantic: clear the inherited sink so emissions inside
    // [body] are dropped even when nested inside an outer suppressAndCapture.
    _suppressCapture = null;
    try {
      return await body();
    } finally {
      _suppressed = wasSuppressed;
      _suppressCapture = priorCapture;
    }
  }

  /// Run [body] with sync emission suppressed AND captured.
  ///
  /// Phase 5 of `docs/plans/sp-import-perf-quick-wins.md`. Every
  /// `syncRecord{Create,Update,Delete}` invocation inside [body] hands its
  /// tuple to [capture] instead of being silently dropped or hitting the
  /// FFI. The SP importer uses this to collect would-be emissions during
  /// the transaction and replay them post-commit — keeping the FFI off the
  /// transaction's critical path while preserving the per-row emission
  /// multiset.
  ///
  /// **Nested calls.** If [body] itself calls `suppressAndCapture(...,
  /// innerSink)`, only [capture] receives ops produced *directly* by
  /// [body]; ops produced inside the nested call go to `innerSink` only.
  /// If [body] calls plain `suppress(...)`, the inner emissions are dropped
  /// — they do NOT bubble up to [capture]. This matches the call-site
  /// intent: `suppress` historically means "drop entirely" and that
  /// semantic is preserved verbatim regardless of an outer capture.
  ///
  /// The `try`/`finally` restores the prior capture sink (which may be
  /// `null` or another capture from an outer call) even if [body] throws.
  static Future<T> suppressAndCapture<T>(
    Future<T> Function() body,
    void Function(CapturedSyncOp op) capture,
  ) async {
    final wasSuppressed = _suppressed;
    final priorCapture = _suppressCapture;
    _suppressed = true;
    _suppressCapture = capture;
    try {
      return await body();
    } finally {
      _suppressed = wasSuppressed;
      _suppressCapture = priorCapture;
    }
  }

  /// Returns true if [error]'s string representation indicates the sync
  /// engine simply isn't configured (pre-pairing). Used to suppress log
  /// spam during onboarding and other unconfigured states.
  static bool _isNotConfigured(Object error) =>
      error.toString().contains('sync not configured');

  Future<void> _runWithConfiguredRetry(
    Future<void> Function(ffi.PrismSyncHandle handle) attempt,
  ) async {
    for (var i = 0; i < _notConfiguredRetryAttempts; i++) {
      final handle = syncHandle;
      if (handle == null) return;
      try {
        await attempt(handle);
        return;
      } catch (e) {
        if (!_isNotConfigured(e)) {
          rethrow;
        }
        if (!syncAutoConfigureInProgress.value) {
          return;
        }
        if (i == _notConfiguredRetryAttempts - 1) {
          return;
        }
        await Future<void>.delayed(_notConfiguredRetryDelay);
      }
    }
  }

  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    if (_suppressed) {
      final captureSink = _suppressCapture;
      if (captureSink != null) {
        captureSink(
          CapturedSyncOp(
            table,
            entityId,
            SyncRecordOpType.create,
            Map<String, dynamic>.of(fields),
          ),
        );
      }
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      sink(
        CapturedSyncOp(
          table,
          entityId,
          SyncRecordOpType.create,
          Map<String, dynamic>.of(fields),
        ),
      );
      return;
    }
    final payload = jsonEncode(fields);
    try {
      await _runWithConfiguredRetry((handle) {
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
    if (_suppressed) {
      final captureSink = _suppressCapture;
      if (captureSink != null) {
        captureSink(
          CapturedSyncOp(
            table,
            entityId,
            SyncRecordOpType.update,
            Map<String, dynamic>.of(fields),
          ),
        );
      }
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      sink(
        CapturedSyncOp(
          table,
          entityId,
          SyncRecordOpType.update,
          Map<String, dynamic>.of(fields),
        ),
      );
      return;
    }
    final payload = jsonEncode(fields);
    try {
      await _runWithConfiguredRetry((handle) {
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
    if (_suppressed) {
      final captureSink = _suppressCapture;
      if (captureSink != null) {
        captureSink(
          CapturedSyncOp(
            table,
            entityId,
            SyncRecordOpType.delete,
            const <String, dynamic>{},
          ),
        );
      }
      return;
    }
    final sink = _captureSink;
    if (sink != null) {
      sink(
        CapturedSyncOp(
          table,
          entityId,
          SyncRecordOpType.delete,
          const <String, dynamic>{},
        ),
      );
      return;
    }
    try {
      await _runWithConfiguredRetry((handle) {
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
