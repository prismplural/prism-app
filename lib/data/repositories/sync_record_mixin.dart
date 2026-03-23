import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

/// Mixin for repositories that record mutations to the Rust sync engine.
mixin SyncRecordMixin {
  ffi.PrismSyncHandle? get syncHandle;

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
      debugPrint('Sync recordDelete failed: $e');
    }
  }
}
