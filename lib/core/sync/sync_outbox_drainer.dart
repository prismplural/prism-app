import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/sync_op_outbox_dao.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// Serialized drainer for the durable sync-op outbox (CRDT remediation wave 4,
/// emission-outbox-atomicity family / F05/F08/F19/F33/F37).
///
/// The outbox rows are written inside the same Drift transaction as the data
/// write (see [SyncRecordMixin.persistCapturedOpsToOutbox]); this drainer
/// dispatches them to the Rust FFI STRICTLY AFTER commit, deleting a row only
/// once its FFI call returns Ok. That is the durable form of the approved
/// capture-ops + replay-after-commit shape — no FFI dispatch ever happens
/// inside a transaction, so the emit-after-commit invariant holds.
///
/// Semantics:
///  * **Single in-flight + coalescing.** Concurrent [drain] triggers never run
///    two passes at once; a trigger that arrives while a pass is running sets a
///    dirty flag so exactly one more pass runs afterward, covering rows
///    enqueued during the first pass.
///  * **Drain order.** Rows are processed in `id` (autoincrement) order.
///  * **Per-(table, entity) lanes.** A row drains only if no EARLIER undrained
///    or quarantined row exists for the same `(table_name, entity_id)`. A
///    poisoned op blocks only its own entity, never the whole outbox.
///  * **Delete coalescing.** Consecutive deletes for one table (in id order,
///    once lane-eligible) are packed into one [ffi.recordDeleteMulti] call,
///    preserving the bulk-delete coalescing fix.
///  * **At-least-once.** Rust mints a fresh HLC per emission, so a duplicate
///    drain is a same-value LWW op; the row is deleted ONLY after Ok.
///  * **Deferral, never drop.** A null handle or an engine-unconfigured error
///    leaves rows untouched and returns — the next trigger re-runs. Any other
///    error increments `attempts`/`last_error`, and after [quarantineAfter]
///    deterministic failures the row is quarantined with an
///    ErrorReportingService report (it then blocks only its own lane).
class SyncOutboxDrainer {
  SyncOutboxDrainer(
    this._db, {
    this.quarantineAfter = kDefaultQuarantineAfter,
    DispatchOp? dispatchOp,
    DispatchDeleteMulti? dispatchDeleteMulti,
  })  : _dispatchOp = dispatchOp ?? SyncRecordMixin.dispatchCapturedOpForDrain,
        _dispatchDeleteMulti =
            dispatchDeleteMulti ?? SyncRecordMixin.dispatchDeleteMultiForDrain;

  /// How many deterministic failures before a row is quarantined.
  static const int kDefaultQuarantineAfter = 5;

  final AppDatabase _db;
  final int quarantineAfter;
  final DispatchOp _dispatchOp;
  final DispatchDeleteMulti _dispatchDeleteMulti;

  SyncOutboxDao get _dao => _db.syncOutboxDao;

  Future<void>? _inFlight;
  bool _dirty = false;
  ffi.PrismSyncHandle? _pendingHandle;

  /// Trigger a drain pass against [handle]. Returns when the current pass (and
  /// any pass coalesced onto it) completes. Concurrent calls share the same
  /// in-flight future; a call that arrives mid-pass schedules exactly one
  /// follow-up pass so rows enqueued during the first pass are covered.
  ///
  /// A null [handle] is a safe no-op: the rows are left untouched (deferral,
  /// not drop), so a trigger that fires before the engine handle is published
  /// simply does nothing until a later trigger carries a handle.
  Future<void> drain(ffi.PrismSyncHandle? handle) {
    if (handle == null) {
      // Don't disturb an in-flight pass that has a real handle; just defer.
      return _inFlight ?? Future<void>.value();
    }
    _pendingHandle = handle;
    if (_inFlight != null) {
      _dirty = true;
      return _inFlight!;
    }
    final future = _runLoop();
    _inFlight = future;
    return future;
  }

  Future<void> _runLoop() async {
    try {
      do {
        _dirty = false;
        final handle = _pendingHandle;
        if (handle == null) return;
        await _drainOnce(handle);
      } while (_dirty);
    } finally {
      _inFlight = null;
    }
  }

  /// One full pass over the outbox in id order. Visible for tests so the
  /// lane-blocking / coalescing / quarantine logic can be exercised without the
  /// coalescing wrapper.
  @visibleForTesting
  Future<void> drainOnce(ffi.PrismSyncHandle handle) => _drainOnce(handle);

  Future<void> _drainOnce(ffi.PrismSyncHandle handle) async {
    final rows = await _dao.allInIdOrder();
    if (rows.isEmpty) return;

    // An entity is blocked once any of its rows is quarantined or has failed to
    // drain this pass: later rows for the same entity must wait so a poisoned
    // op cannot be skipped-and-advanced past.
    final blockedEntities = <String>{};
    for (final row in rows) {
      if (row.quarantined) {
        blockedEntities.add(_laneKey(row.entityTable, row.entityId));
      }
    }

    // Buffer of consecutive deletes for one table, flushed (as a coalesced
    // recordDeleteMulti) when the run breaks. `null` table means no run open.
    String? deleteRunTable;
    final deleteRunRows = <SyncOpOutboxRow>[];

    Future<bool> flushDeleteRun() async {
      if (deleteRunTable == null || deleteRunRows.isEmpty) {
        deleteRunTable = null;
        deleteRunRows.clear();
        return true;
      }
      final table = deleteRunTable!;
      final batch = List<SyncOpOutboxRow>.from(deleteRunRows);
      deleteRunTable = null;
      deleteRunRows.clear();
      try {
        await _dispatchDeleteMulti(
          handle,
          table,
          [for (final r in batch) r.entityId],
        );
        await _dao.deleteByIds([for (final r in batch) r.id]);
        return true;
      } on Object catch (e) {
        if (_isDeferral(e)) {
          // Engine unconfigured: leave every row in this run untouched and
          // stop the whole pass — deferral, not drop.
          return false;
        }
        // Each row in the failed batch takes a failure independently so its own
        // lane is the only thing that quarantines.
        for (final r in batch) {
          await _recordRowFailure(r, e, blockedEntities);
        }
        return true;
      }
    }

    for (final row in rows) {
      if (row.quarantined) continue;
      final lane = _laneKey(row.entityTable, row.entityId);

      // Lane blocking: an earlier undrained/quarantined row for this entity
      // means this row must wait. Flush any open delete run first so ordering
      // across a blocked entity stays correct.
      if (blockedEntities.contains(lane)) {
        if (!await flushDeleteRun()) return;
        continue;
      }

      final opType = SyncRecordMixin.outboxOpTypeFromName(row.opType);

      if (opType == SyncRecordOpType.delete) {
        // Extend / open the delete run only while the table matches; a table
        // switch flushes the prior run first.
        if (deleteRunTable != null && deleteRunTable != row.entityTable) {
          if (!await flushDeleteRun()) return;
        }
        deleteRunTable = row.entityTable;
        deleteRunRows.add(row);
        continue;
      }

      // A create/update breaks any open delete run (ordering must be
      // preserved), then dispatches on its own.
      if (!await flushDeleteRun()) return;
      if (!await _dispatchSingle(handle, row, blockedEntities)) return;
    }

    // Flush a trailing delete run.
    await flushDeleteRun();
  }

  /// Dispatch one create/update/delete row. Returns false (stop the pass) only
  /// on a deferral (null/unconfigured) so the rows are left for the next
  /// trigger. Other errors are recorded against the row and processing
  /// continues with the rest of the outbox.
  Future<bool> _dispatchSingle(
    ffi.PrismSyncHandle handle,
    SyncOpOutboxRow row,
    Set<String> blockedEntities,
  ) async {
    final op = _toCapturedOp(row);
    try {
      await _dispatchOp(handle, op);
      await _dao.deleteByIds([row.id]);
      return true;
    } on Object catch (e) {
      if (_isDeferral(e)) return false;
      await _recordRowFailure(row, e, blockedEntities);
      return true;
    }
  }

  Future<void> _recordRowFailure(
    SyncOpOutboxRow row,
    Object error,
    Set<String> blockedEntities,
  ) async {
    await _dao.recordFailure(
      row.id,
      error.toString(),
      quarantineAfter: quarantineAfter,
    );
    // This entity's lane is now blocked for the rest of the pass regardless of
    // whether it crossed the quarantine threshold — never skip-and-advance past
    // a failed op for the same entity.
    blockedEntities.add(_laneKey(row.entityTable, row.entityId));
    if (await _dao.isQuarantined(row.id)) {
      ErrorReportingService.instance.report(
        'Sync outbox row quarantined after $quarantineAfter attempts '
        '(${row.opType} ${row.entityTable}/${row.entityId}): $error',
        severity: ErrorSeverity.error,
      );
    }
  }

  CapturedSyncOp _toCapturedOp(SyncOpOutboxRow row) {
    final opType = SyncRecordMixin.outboxOpTypeFromName(row.opType);
    final fields = opType == SyncRecordOpType.delete
        ? const <String, dynamic>{}
        : (jsonDecodeFields(row.fieldsJson));
    return CapturedSyncOp(
      row.entityTable,
      row.entityId,
      opType,
      fields,
      capturedAtMs: row.createdAt,
    );
  }

  bool _isDeferral(Object error) => SyncRecordMixin.isNotConfiguredError(error);

  static String _laneKey(String table, String entityId) => '$table $entityId';
}

/// Dispatch a single captured op (create/update/delete) to the FFI.
typedef DispatchOp = Future<void> Function(
  ffi.PrismSyncHandle handle,
  CapturedSyncOp op,
);

/// Dispatch a coalesced run of deletes for one table to the FFI.
typedef DispatchDeleteMulti = Future<void> Function(
  ffi.PrismSyncHandle handle,
  String table,
  List<String> entityIds,
);

/// Decode an outbox `fields_json` payload into a field map. Kept here (rather
/// than inline) so a malformed payload surfaces a clear error instead of a bare
/// cast failure deep in the drain loop.
Map<String, dynamic> jsonDecodeFields(String fieldsJson) {
  final decoded = _decode(fieldsJson);
  if (decoded is Map) return decoded.cast<String, dynamic>();
  throw FormatException('Outbox fields_json is not a JSON object', fieldsJson);
}

Object? _decode(String s) => s.isEmpty ? const <String, dynamic>{} : jsonDecode(s);
