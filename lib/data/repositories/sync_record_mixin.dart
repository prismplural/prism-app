import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// Mixin for repositories that record mutations to the Rust sync engine.
///
/// The handle may exist (Rust side constructed) but the engine may not be
/// configured yet — for example during onboarding, before the user has
/// paired a device. In that state the FFI returns
/// `engine error: sync not configured`; that's expected, not an error, and
/// should be silently skipped rather than logged for every write.
mixin SyncRecordMixin {
  ffi.PrismSyncHandle? get syncHandle;

  /// Returns true if [error]'s string representation indicates the sync
  /// engine simply isn't configured (pre-pairing). Used to suppress log
  /// spam during onboarding and other unconfigured states.
  static bool _isNotConfigured(Object error) =>
      error.toString().contains('sync not configured');

  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    if (syncHandle == null) return;
    try {
      await ffi.recordCreate(
        handle: syncHandle!,
        table: table,
        entityId: entityId,
        fieldsJson: jsonEncode(fields),
      );
    } catch (e) {
      if (_isNotConfigured(e)) return;
      debugPrint('Sync recordCreate failed: $e');
    }
  }

  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    if (syncHandle == null) return;
    try {
      await ffi.recordUpdate(
        handle: syncHandle!,
        table: table,
        entityId: entityId,
        changedFieldsJson: jsonEncode(fields),
      );
    } catch (e) {
      if (_isNotConfigured(e)) return;
      debugPrint('Sync recordUpdate failed: $e');
    }
  }

  Future<void> syncRecordDelete(String table, String entityId) async {
    if (syncHandle == null) return;
    try {
      await ffi.recordDelete(
        handle: syncHandle!,
        table: table,
        entityId: entityId,
      );
    } catch (e) {
      if (_isNotConfigured(e)) return;
      debugPrint('Sync recordDelete failed: $e');
    }
  }
}
