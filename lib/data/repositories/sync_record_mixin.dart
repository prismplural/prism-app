import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
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
mixin SyncRecordMixin {
  ffi.PrismSyncHandle? get syncHandle;

  static const int _notConfiguredRetryAttempts = 10;
  static const Duration _notConfiguredRetryDelay = Duration(milliseconds: 100);

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
    } catch (e) {
      debugPrint('Sync recordCreate failed: $e');
    }
  }

  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
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
    } catch (e) {
      debugPrint('Sync recordUpdate failed: $e');
    }
  }

  Future<void> syncRecordDelete(String table, String entityId) async {
    try {
      await _runWithConfiguredRetry((handle) {
        return ffi.recordDelete(
          handle: handle,
          table: table,
          entityId: entityId,
        );
      });
    } catch (e) {
      debugPrint('Sync recordDelete failed: $e');
    }
  }
}
