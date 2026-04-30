import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';

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

  /// Run [body] with sync emission suppressed.
  ///
  /// Used by the per-member fronting migration (`fronting_migration_service`)
  /// so the intra-transaction repository writes don't emit Rust pending_ops
  /// that would survive a Drift rollback. The `try`/`finally` ensures the
  /// flag clears even if [body] throws — propagating the original exception.
  static Future<T> suppress<T>(Future<T> Function() body) async {
    final wasSuppressed = _suppressed;
    _suppressed = true;
    try {
      return await body();
    } finally {
      _suppressed = wasSuppressed;
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
    if (_suppressed) return;
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
    if (_suppressed) return;
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
    if (_suppressed) return;
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
}
