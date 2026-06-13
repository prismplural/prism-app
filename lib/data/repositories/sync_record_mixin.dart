import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';

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
  const CapturedSyncOp(
    this.table,
    this.entityId,
    this.opType,
    this.fields, {
    this.capturedAtMs,
    this.isDivergenceAware = false,
  });

  final String table;
  final String entityId;
  final SyncRecordOpType opType;

  /// Empty map for [SyncRecordOpType.delete] (the FFI does not carry fields
  /// for deletes).
  final Map<String, dynamic> fields;

  /// Wall-clock capture time (`DateTime.now().millisecondsSinceEpoch`) stamped
  /// when the live `syncRecord*` path builds the op. A replay that is dispatched
  /// later carries this as its origin HLC so chronologically-older data never
  /// wins LWW against an edit made after capture. `null` for ops built by
  /// legacy const-ctor sites; dispatch falls back to a fresh emit-time HLC for
  /// those, while the live `syncRecord*` and outbox paths always populate it.
  final int? capturedAtMs;

  /// True when this op originated from [SyncRecordMixin.syncRecordReconcile] or
  /// [SyncRecordMixin.syncRecordBackfill]. Those carry merge-relevant divergence
  /// semantics (per-field reconcile / floor-HLC backfill) that the plain
  /// create/update/delete outbox vocabulary CANNOT represent — captured as
  /// [SyncRecordOpType.update], they would drain as a fresh-HLC update and
  /// reintroduce the exact reconcile/backfill clobber. The outbox
  /// guard ([SyncRecordMixin.persistCapturedOpsToOutbox]) refuses any op with
  /// this flag set. Reconcile/backfill ops dispatch directly today, so nothing
  /// legitimately routes them through the outbox; the flag pins that invariant.
  final bool isDivergenceAware;
}

/// Test-only callback type: invoked once per intercepted sync emission.
typedef SyncRecordCaptureSink = void Function(CapturedSyncOp op);

/// Drain trigger wired by the app at start ([SyncRecordMixin.installOutboxRuntime]).
/// Invoked after a live emit enqueues an outbox row, carrying the handle the
/// drainer should dispatch against (`null` is a safe no-op deferral).
typedef OutboxDrainTrigger = Future<void> Function(ffi.PrismSyncHandle? handle);

/// Active suppression context, carried as a [Zone] value. `null` [capture]
/// drops emissions ([SyncRecordMixin.suppress]); a non-null [capture] receives
/// them instead of the FFI ([SyncRecordMixin.suppressAndCapture]).
class _SyncCaptureContext {
  const _SyncCaptureContext(this.capture);
  final void Function(CapturedSyncOp op)? capture;
}

/// Mixin for repositories that record mutations to the Rust sync engine.
///
/// **Durable outbox.** A live `syncRecord*` call no longer dispatches to
/// the FFI directly. It persists a row into the durable `sync_op_outbox` Drift
/// table (gated on persisted sync-group credentials) and then triggers the
/// [SyncOutboxDrainer]. The drainer owns ALL engine-availability handling: a
/// null handle or an engine-unconfigured error leaves the row untouched
/// (deferral), so "unconfigured" is a deferral state and never a drop. The
/// engine may exist (Rust side constructed) but be unconfigured (the brief
/// startup window before `configureEngine()`, or the documented
/// "Relay not configured" disconnect episodes); in every such case the row
/// survives and the next drain trigger re-dispatches it. The only remaining
/// local failure mode on the emit path is the Drift insert itself, which is
/// reported (the data row is already committed).
///
/// Never-paired devices (no persisted credentials) keep the historical local
/// -only behavior: nothing is enqueued, because `bootstrapExistingData` seeds
/// everything into `field_versions` at sync setup.
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

  /// The handle the emit path actually targets: the live runtime handle when
  /// one is published, else the injected [syncHandle]. Resolved identically to
  /// the outbox drain trigger so a gate/read built from it sees the same engine
  /// state the next drain would write to.
  ffi.PrismSyncHandle? get resolvedSyncHandle =>
      syncCurrentHandle.value ?? syncHandle;

  /// Test-only override for [tombstoneGate]. Production builds never set this
  /// (it is gated behind `assert`), so the getter falls through to a gate built
  /// from the live handle. Tests inject a fake gate to exercise the burned-id
  /// ingress path without a real engine.
  TombstoneGate? _tombstoneGateOverride;

  @visibleForTesting
  set debugTombstoneGateForTesting(TombstoneGate? gate) {
    assert(() {
      _tombstoneGateOverride = gate;
      return true;
    }());
  }

  /// A [TombstoneGate] over the same engine the emit path targets, or `null`
  /// when no handle is available. Ingress sites that reuse a deterministic
  /// entity id (e.g. the Unknown-sentinel member) consult this BEFORE emitting
  /// a create: an absorbing tombstone on that id makes the create a silent
  /// fleet-wide no-op, so the caller must skip the emission instead. A null
  /// gate means "no engine to consult" → behave exactly as before.
  TombstoneGate? get tombstoneGate =>
      _tombstoneGateOverride ?? TombstoneGate.forHandle(resolvedSyncHandle);

  /// App database used by the live emit path to persist outbox rows, plus the
  /// drain trigger fired right after an enqueue. Both are wired once at app
  /// start ([installOutboxRuntime]); they are `null` in unit tests that don't
  /// exercise the live path (those use suppress/capture or the capture sink),
  /// so a live emit with no runtime simply no-ops (the data row is still
  /// committed; the missing runtime only suppresses sync emission in that
  /// degenerate test configuration).
  static AppDatabase? _outboxDb;
  static OutboxDrainTrigger? _outboxDrainTrigger;

  /// Wire the durable-outbox runtime: [db] receives the enqueued rows and
  /// [drainTrigger] is invoked after each enqueue to dispatch them. Called once
  /// the AppDatabase and the SyncOutboxDrainer are constructed at app start.
  /// Passing `null` for either clears the wiring (used by tests / teardown).
  static void installOutboxRuntime({
    AppDatabase? db,
    OutboxDrainTrigger? drainTrigger,
  }) {
    _outboxDb = db;
    _outboxDrainTrigger = drainTrigger;
  }

  @visibleForTesting
  static void debugInstallOutboxRuntimeForTesting({
    AppDatabase? db,
    OutboxDrainTrigger? drainTrigger,
  }) => installOutboxRuntime(db: db, drainTrigger: drainTrigger);

  /// The database [runSyncedWrite] opens its transaction on. Defaults to the
  /// wired runtime db ([_outboxDb]); a repository that mixes this in overrides
  /// it to return its own `_dao.attachedDatabase` so the data write, the outbox
  /// rows, and the transaction all live on the one database the repository
  /// actually writes to (in production every repo shares the singleton
  /// AppDatabase, so they coincide). Never `null` for an overriding repository,
  /// which is why [runSyncedWrite] can always wrap the data write atomically.
  AppDatabase? get syncOutboxDatabase => _outboxDb;

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

  /// Zone key carrying a replay-origin timestamp. [replayCapturedOps]
  /// sets it around each re-dispatch so `syncRecord*` stamps the re-emitted op
  /// at the op's ORIGINAL capture time instead of `now`, without changing the
  /// entry-point signatures (their test-double overrides must keep matching).
  static const Object _replayOriginZoneKey = #prismSyncReplayOrigin;

  /// The replay-origin timestamp for the current async context, or `null` when
  /// not inside a [replayCapturedOps] re-dispatch.
  static int? get _replayOriginMs =>
      Zone.current[_replayOriginZoneKey] as int?;

  /// Capture time to stamp a freshly-built op with: the replay origin when
  /// re-emitting, else now.
  static int get _opCaptureTimeMs =>
      _replayOriginMs ?? DateTime.now().millisecondsSinceEpoch;

  /// Run [body] with the replay-origin timestamp [originMs] in scope. A null
  /// origin leaves the zone untouched (legacy capture ops fall back to now).
  static Future<T> _withReplayOrigin<T>(
    int? originMs,
    Future<T> Function() body,
  ) {
    if (originMs == null) return body();
    return runZoned(body, zoneValues: {_replayOriginZoneKey: originMs});
  }

  /// Drift stamps the active executor into the zone under this key while a
  /// `db.transaction(...)` body runs (including nested transactions). A
  /// non-null value means the current async context is inside an OPEN Drift
  /// transaction, so any FFI dispatch fired now would run BEFORE the outermost
  /// commit and survive a rollback. See [_inDriftTransaction].
  static const Object _driftTxnZoneKey = #DatabaseConnectionUser;

  /// Whether the current async context is inside an open Drift transaction.
  /// The live emit path uses this to defer the drain trigger: persisting the
  /// outbox row inside the txn is safe (it commits/rolls back atomically with
  /// the data write), but DISPATCHING it must wait until after commit, or the
  /// emit-after-commit invariant breaks and a rollback leaks a phantom op.
  static bool get _inDriftTransaction =>
      Zone.current[_driftTxnZoneKey] != null;

  /// Zone key set by [runFencedEmissionTransaction] (and [runSyncedWrite]) to
  /// mark "this Drift transaction routes all CRDT emissions through the
  /// suppress/capture seam — no live FFI dispatch is allowed inside it." The
  /// emit-after-commit fences ([runSyncedWrite], `importData`, the PK
  /// `PkMappingApplier` transaction) set it so the defense-in-depth assert below
  /// can catch a future code path that emits live inside one of them (i.e. the
  /// phantom-op bug class re-tripping).
  static const Object _fencedEmissionTxnZoneKey = #prismSyncFencedEmissionTxn;

  /// Whether the current async context is inside a fenced emission transaction.
  static bool get _inFencedEmissionTransaction =>
      Zone.current[_fencedEmissionTxnZoneKey] == true;

  /// Run [body] inside a Drift transaction on [db] that captures every CRDT
  /// emission into [capture] and is marked as a fenced emission transaction.
  ///
  /// The fence flag arms the defense-in-depth assert in the live emit path:
  /// inside this transaction every `syncRecord*` MUST route through the active
  /// suppress/capture context, so reaching the live FFI/outbox-enqueue path
  /// here means a code path escaped the seam — the exact phantom-op
  /// bug class. In debug/test builds that assert-fails loudly; in release the
  /// row is still persisted durably (and dispatched only post-commit), so the
  /// emit-after-commit invariant holds even if the assert is stripped.
  ///
  /// Used by the importers ([runSyncedWrite], `importData`, the PK applier)
  /// that wrap a whole rollback-able restore/apply: they collect the captured
  /// ops, [persistCapturedOpsToOutbox] inside the same transaction, and drain
  /// strictly after commit.
  static Future<T> runFencedEmissionTransaction<T>(
    AppDatabase db,
    Future<T> Function() body,
    void Function(CapturedSyncOp op) capture,
  ) {
    return runZoned(
      () => db.transaction(() => suppressAndCapture(body, capture)),
      zoneValues: {_fencedEmissionTxnZoneKey: true},
    );
  }

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

  /// Whether [error] is the engine-unconfigured signal (pre-pairing /
  /// disconnected boot). Exposed so [SyncOutboxDrainer] uses the same
  /// detection to LEAVE rows untouched (deferral, not drop) rather than
  /// forking the string check.
  static bool isNotConfiguredError(Object error) => _isNotConfigured(error);

  static Future<void> _dispatchCapturedOp(
    ffi.PrismSyncHandle handle,
    CapturedSyncOp op,
  ) {
    final payload = jsonEncode(op.fields);
    // Origin stamping: when the op carries its capture time, dispatch
    // through the `*_at` FFI so the engine mints the HLC at the origin
    // timestamp (clamped to (floor, now]) instead of a fresh emit-time tick.
    // The watermark is left untouched and the field_versions upsert is
    // `wins_over`-guarded, so a late replay never regresses a newer local
    // winner. Legacy const-ctor sites leave `capturedAtMs` null and keep the
    // legacy fresh-HLC behavior; the live `syncRecord*` and outbox paths
    // always populate it.
    final originMs = op.capturedAtMs;
    if (originMs != null) {
      return switch (op.opType) {
        SyncRecordOpType.create => ffi.recordCreateAt(
          handle: handle,
          table: op.table,
          entityId: op.entityId,
          fieldsJson: payload,
          originTimestampMs: originMs,
        ),
        SyncRecordOpType.update => ffi.recordUpdateAt(
          handle: handle,
          table: op.table,
          entityId: op.entityId,
          changedFieldsJson: payload,
          originTimestampMs: originMs,
        ),
        SyncRecordOpType.delete => ffi.recordDeleteAt(
          handle: handle,
          table: op.table,
          entityId: op.entityId,
          originTimestampMs: originMs,
        ),
      };
    }
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

  /// Dispatch a single captured op to the FFI via the canonical
  /// [_dispatchCapturedOp] switch. Exposed so [SyncOutboxDrainer] reuses the
  /// one dispatch mapping instead of forking it. The outbox owns its own
  /// delete-coalescing, so it never routes a delete here when more than one
  /// consecutive delete is pending — it calls [dispatchDeleteMultiForDrain].
  static Future<void> dispatchCapturedOpForDrain(
    ffi.PrismSyncHandle handle,
    CapturedSyncOp op,
  ) => _dispatchCapturedOp(handle, op);

  /// Coalesced delete dispatch for the drainer: packs a run of consecutive
  /// same-table deletes into one [ffi.recordDeleteMulti] call (preserving the
  /// bulk-delete coalescing fix).
  static Future<void> dispatchDeleteMultiForDrain(
    ffi.PrismSyncHandle handle,
    String table,
    List<String> entityIds,
  ) => ffi.recordDeleteMulti(
    handle: handle,
    table: table,
    entityIds: entityIds,
  );

  /// The outbox `op_type` string for a captured op. The vocabulary is
  /// create/update/delete ONLY and cannot represent the divergence-aware
  /// reconcile/backfill modes — those are captured as [SyncRecordOpType.update]
  /// but MUST NOT reach the outbox (the [CapturedSyncOp.isDivergenceAware]
  /// guard in [persistCapturedOpsToOutbox] refuses them), because a drained
  /// plain `update` carries a fresh HLC and would reintroduce the
  /// reconcile/backfill clobber. Reconcile/backfill ops dispatch directly, so
  /// nothing legitimately routes a reconcile/backfill through here.
  static String outboxOpTypeName(SyncRecordOpType opType) => switch (opType) {
    SyncRecordOpType.create => 'create',
    SyncRecordOpType.update => 'update',
    SyncRecordOpType.delete => 'delete',
  };

  /// Parse an outbox `op_type` string back into a [SyncRecordOpType]. Throws on
  /// an unrecognized value so a corrupt row surfaces rather than silently
  /// dispatching the wrong FFI entry point.
  static SyncRecordOpType outboxOpTypeFromName(String name) => switch (name) {
    'create' => SyncRecordOpType.create,
    'update' => SyncRecordOpType.update,
    'delete' => SyncRecordOpType.delete,
    _ => throw ArgumentError('Unknown outbox op_type: $name'),
  };

  /// Persist [ops] as durable outbox rows inside the CURRENT Drift transaction.
  ///
  /// For in-transaction callers (`runSyncedWrite`, the wrapped importers): the
  /// data write and the emission intent commit atomically, then the drainer
  /// dispatches the rows to the FFI strictly AFTER commit. This is the durable
  /// form of the approved capture-ops + replay-after-commit shape — NO FFI
  /// dispatch happens here, so the emit-after-commit invariant holds even
  /// though the rows are written inside the transaction.
  ///
  /// Stores each op's real `op_type` (create/update/delete) and the
  /// `jsonEncode` of its fields (empty `{}` for deletes); `created_at` carries
  /// the op's [CapturedSyncOp.capturedAtMs] so the drainer can re-derive the
  /// origin HLC.
  ///
  /// GUARD: refuses a reconcile/backfill-origin op.
  /// The outbox vocabulary cannot represent divergence-aware emission; such an
  /// op is captured as an `update` and would drain as a fresh-HLC update,
  /// reintroducing the reconcile/backfill clobber. Reconcile/backfill ops
  /// dispatch directly today, so reaching here with one is a code-path bug —
  /// fail loudly.
  static Future<void> persistCapturedOpsToOutbox(
    AppDatabase db,
    List<CapturedSyncOp> ops,
  ) async {
    if (ops.isEmpty) return;
    for (final op in ops) {
      if (op.isDivergenceAware) {
        throw StateError(
          'Refusing to persist a reconcile/backfill op to the sync outbox '
          '(${op.table}/${op.entityId}): the outbox cannot represent '
          'divergence-aware emission and would drain it as a fresh-HLC update, '
          'reintroducing the F43/F44 clobber. Dispatch it directly instead.',
        );
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <SyncOpOutboxCompanion>[
      for (final op in ops)
        SyncOpOutboxCompanion.insert(
          entityTable: op.table,
          entityId: op.entityId,
          opType: outboxOpTypeName(op.opType),
          fieldsJson: op.opType == SyncRecordOpType.delete
              ? '{}'
              : jsonEncode(op.fields),
          createdAt: op.capturedAtMs ?? now,
        ),
    ];
    await db.syncOutboxDao.insertAll(rows);
  }

  /// Run [body]'s data write and its sync-op intent in ONE Drift transaction,
  /// then dispatch the ops strictly AFTER the commit.
  ///
  /// This closes the per-mutation dual-write crash window: a repository
  /// mutation used to commit its Drift rows and then make a SEPARATE
  /// best-effort FFI call, so a crash between the two committed the data but
  /// lost (or — inside a rollback-able transaction — leaked) the emission.
  /// Here the writes [body] performs and the durable outbox rows for the ops it
  /// emits commit or roll back together: a thrown [body] leaves zero data rows
  /// AND zero outbox rows, and a committed [body] leaves the data plus an outbox
  /// row per op in capture order.
  ///
  /// **Emit-after-commit (absolute invariant).** No FFI dispatch happens inside
  /// the transaction — the body emits through the Zone-scoped
  /// [suppressAndCapture] seam, the captured ops are persisted as outbox rows
  /// (a Drift write, not an FFI call), and the drainer is triggered only after
  /// the transaction returns. This is the durable form of the approved
  /// capture-ops + replay-after-commit shape; the reverted add-member txn-wrap
  /// failed precisely because it emitted to the engine INSIDE the transaction,
  /// so a rollback left a phantom Rust pending_op. Routing every dispatch
  /// outside the commit is what keeps that revert from re-tripping.
  ///
  /// Gated on persisted sync-group credentials ([syncCredentialsPersisted]):
  /// a never-paired device runs [body]'s write transaction but persists no
  /// outbox rows (and so triggers no drain), keeping the historical local-only
  /// behavior — `bootstrapExistingData` seeds the whole store into
  /// `field_versions` at sync setup, so a pre-pairing outbox would be redundant.
  Future<T> runSyncedWrite<T>(Future<T> Function() body) async {
    if (isSuppressed) {
      // An outer suppress/capture seam already owns this body's emissions (e.g.
      // the burned-id sentinel create runs under [suppress], and the importers
      // run under [suppressAndCapture]). Installing our own capture context here
      // would shadow theirs — dropping a suppression or stealing the importer's
      // capture into a second outbox batch. Defer entirely to the outer context:
      // run the body so its emissions route there, with no nested transaction or
      // outbox persist of our own.
      return body();
    }
    final db = syncOutboxDatabase;
    if (db == null) {
      // No database to open a transaction on (degenerate test config with no
      // runtime wired and no override). Run the body so the data write still
      // happens; there is nothing to enqueue against. Production repositories
      // override [syncOutboxDatabase], so this branch is test-only.
      return body();
    }
    final captured = <CapturedSyncOp>[];
    // The test-only capture sink (null in every shipped build — assert-gated)
    // observes emissions at the `syncRecord*` boundary. Because we install our
    // own capture context for the body, that boundary's normal sink dispatch is
    // shadowed; forward to it here so the sink still sees each op exactly once,
    // preserving the emission-observation contract repository tests rely on.
    void capture(CapturedSyncOp op) {
      captured.add(op);
      _captureSink?.call(op);
    }

    final result = await runFencedEmissionTransaction(db, () async {
      final r = await body();
      if (syncCredentialsPersisted.value) {
        await persistCapturedOpsToOutbox(db, captured);
      }
      return r;
    }, capture);
    // Strictly post-commit: the rows are durable, so dispatching now (or on the
    // next boot/resume/catch-up/backoff trigger if this one defers) can never
    // run an FFI call before the data write committed.
    if (syncCredentialsPersisted.value && captured.isNotEmpty) {
      final trigger = _outboxDrainTrigger;
      if (trigger != null) {
        unawaited(trigger(syncCurrentHandle.value ?? syncHandle));
      }
    }
    return result;
  }

  /// Live emit (no active suppression / capture sink): enqueue [ops] into the
  /// durable outbox, then trigger the drainer. The drainer dispatches the rows
  /// to the FFI and owns all engine-availability handling — a null handle or an
  /// unconfigured engine leaves the rows for the next trigger (deferral, never
  /// drop). The only failure surfaced here is the Drift insert itself (the data
  /// row is already committed, so this is reported and swallowed).
  ///
  /// **Emit-after-commit (absolute invariant).** When this runs inside an open
  /// Drift transaction (a live `syncRecord*` reached from an unsuppressed
  /// importer — `importData`, the PK importers — whose in-txn fencing is
  /// deferred work), the outbox row is persisted atomically with
  /// the data write but the drain trigger is SKIPPED: dispatching now would run
  /// the FFI before the outermost commit and leak a phantom op on rollback. The
  /// row stays durable and a post-commit drain (boot/resume/catch-up, the
  /// backoff timer armed by any later live emit, or the importer's own
  /// post-commit trigger) picks it up. Outside a transaction (the live
  /// single-statement path) the trigger fires immediately as before.
  ///
  /// Gated on persisted sync-group credentials ([syncCredentialsPersisted]):
  /// never-paired devices enqueue nothing — `bootstrapExistingData` seeds the
  /// whole store into `field_versions` at sync setup, so a pre-pairing outbox
  /// would be redundant (and is cleared there).
  Future<void> _enqueueAndDrain(List<CapturedSyncOp> ops) async {
    // Defense in depth: the live path runs only when NO suppress/
    // capture context is active. Reaching it inside a fenced emission
    // transaction ([runFencedEmissionTransaction] / [runSyncedWrite]) means an
    // emission escaped the seam — the phantom-op-on-rollback bug class. Fail
    // loudly in debug/test so a regression can't ship silently. Release keeps
    // going: the row below is still persisted atomically and dispatched only
    // post-commit, so emit-after-commit holds even with the assert stripped.
    assert(
      !_inFencedEmissionTransaction,
      'syncRecord* reached the live emit path inside a fenced emission '
      'transaction — an emission escaped the suppress/capture seam and would '
      'leak a phantom op on rollback (F19/F37).',
    );
    if (ops.isEmpty || !syncCredentialsPersisted.value) {
      return;
    }
    final db = _outboxDb;
    if (db == null) {
      // No runtime wired (degenerate test config). The data row is committed;
      // nothing to enqueue against. Production always installs the runtime.
      return;
    }
    try {
      await persistCapturedOpsToOutbox(db, ops);
    } catch (e, st) {
      ErrorReportingService.instance.report(
        'Sync outbox enqueue failed (${ops.length} op(s)): $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
      return;
    }
    if (_inDriftTransaction) {
      // Defer the dispatch to a post-commit drain (see doc above): the row is
      // durable and atomic with the data write; firing now would violate
      // emit-after-commit and leak on rollback.
      return;
    }
    final trigger = _outboxDrainTrigger;
    if (trigger != null) {
      // Fire-and-forget: a failed drain leaves the rows durable for the next
      // trigger. We do not await it on the write's critical path.
      unawaited(trigger(syncCurrentHandle.value ?? syncHandle));
    }
  }

  /// Direct live FFI dispatch for the divergence-aware reconcile/backfill paths
  /// ([syncRecordReconcile] / [syncRecordBackfill]). These carry merge-relevant
  /// semantics (per-field divergence / floor-HLC backfill) that the plain
  /// create/update/delete outbox does not model, so they are NOT routed through
  /// it. They are one-shot catch-up/migration emissions invoked post-healthy
  /// (the migration repair drain), so an unconfigured engine is a
  /// no-op deferral the next catch-up trigger re-runs; any other error is
  /// reported and swallowed (the local data is already correct).
  Future<void> _dispatchLiveFfi(
    String logLabel,
    Future<void> Function(ffi.PrismSyncHandle handle) attempt,
  ) async {
    final handle = syncCurrentHandle.value ?? syncHandle;
    if (handle == null) return;
    try {
      await attempt(handle);
    } catch (e, st) {
      if (_isNotConfigured(e)) return;
      ErrorReportingService.instance.report(
        '$logLabel failed: $e',
        severity: ErrorSeverity.error,
        stackTrace: st,
      );
    }
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
      capturedAtMs: _opCaptureTimeMs,
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
    await _enqueueAndDrain([op]);
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
      capturedAtMs: _opCaptureTimeMs,
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
    await _enqueueAndDrain([op]);
  }

  Future<void> syncRecordDelete(String table, String entityId) async {
    final op = CapturedSyncOp(
      table,
      entityId,
      SyncRecordOpType.delete,
      const <String, dynamic>{},
      capturedAtMs: _opCaptureTimeMs,
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
    await _enqueueAndDrain([op]);
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
    final capturedAtMs = _opCaptureTimeMs;
    CapturedSyncOp opFor(String id) => CapturedSyncOp(
      table,
      id,
      SyncRecordOpType.delete,
      const <String, dynamic>{},
      capturedAtMs: capturedAtMs,
    );

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
    // Enqueue one delete row per id; the drainer coalesces a consecutive run of
    // same-table deletes into one recordDeleteMulti, preserving the bulk-delete
    // coalescing fix while keeping each id durable in its own lane.
    await _enqueueAndDrain([for (final id in entityIds) opFor(id)]);
  }

  /// Reconcile [fields] for an entity against this device's `field_versions`,
  /// emitting only fields whose local value diverges from the known winner (at
  /// a fresh HLC) or that have never been synced (at the floor backfill HLC).
  ///
  /// The clobber-free replacement for full-row fresh-HLC re-broadcasts: a
  /// value-unchanged field produces zero ops, so a re-broadcast can never beat
  /// a peer's un-pulled newer edit on an unchanged field. Honors the same
  /// suppress/capture seam as [syncRecordUpdate] (captured as an update op so
  /// replay stays row-granular and the parity sink still sees it).
  Future<void> syncRecordReconcile(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final op = CapturedSyncOp(
      table,
      entityId,
      SyncRecordOpType.update,
      Map<String, dynamic>.of(fields),
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      isDivergenceAware: true,
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
    await _dispatchLiveFfi('Sync recordReconcile', (handle) {
      return ffi.recordReconcile(
        handle: handle,
        table: table,
        entityId: entityId,
        fieldsJson: payload,
        divergentFreshHlc: true,
      );
    });
  }

  /// Pure write-if-absent backfill: emit only fields with no `field_versions`
  /// row, at the floor backfill HLC, so they establish an entity group-wide
  /// while losing to every genuine edit. Divergent local values are left alone
  /// (first-device-wins). Honors the same suppress/capture seam as
  /// [syncRecordReconcile].
  Future<void> syncRecordBackfill(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final op = CapturedSyncOp(
      table,
      entityId,
      SyncRecordOpType.update,
      Map<String, dynamic>.of(fields),
      capturedAtMs: DateTime.now().millisecondsSinceEpoch,
      isDivergenceAware: true,
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
    await _dispatchLiveFfi('Sync recordBackfill', (handle) {
      return ffi.recordBackfill(
        handle: handle,
        table: table,
        entityId: entityId,
        fieldsJson: payload,
      );
    });
  }

  /// Replay [ops] through the live FFI path, in capture order — the post-commit
  /// half of the capture-then-replay pattern ([suppressAndCapture] captures
  /// inside a Drift transaction, this re-emits after it durably commits). Each
  /// op re-dispatches through the same `syncRecord*` entry point with its
  /// original type and `fields`, and is origin-stamped at its original
  /// [CapturedSyncOp.capturedAtMs] via a zone-scoped replay-origin override so
  /// the re-emit carries the capture-time HLC rather than a fresh replay-time
  /// one.
  ///
  /// **Not durable — do not use for new production durability.** This is the
  /// in-memory leg of the capture-then-replay pattern: a crash between the
  /// transaction commit and the replay loses the ops (the documented
  /// commit-to-replay gap). Durable callers must persist captured ops with
  /// [persistCapturedOpsToOutbox] inside the transaction (or wrap the whole
  /// mutation in [runSyncedWrite]) and let the drainer dispatch them — the
  /// outbox row commits atomically with the data write, so the gap is closed.
  /// This function survives only for the remaining suppress/capture seam users
  /// (the PK importers' in-memory replay) until those are migrated.
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
        // Re-emit at the op's ORIGINAL capture time, never a fresh replay
        // -time HLC, so a post-commit replay can never beat an edit made after
        // capture. The zone-scoped origin override is read by `syncRecord*`
        // when it builds the op, leaving the entry-point signatures (and their
        // test-double overrides) untouched.
        await _withReplayOrigin(op.capturedAtMs, () async {
          switch (op.opType) {
            case SyncRecordOpType.create:
              await syncRecordCreate(op.table, op.entityId, op.fields);
            case SyncRecordOpType.update:
              await syncRecordUpdate(op.table, op.entityId, op.fields);
            case SyncRecordOpType.delete:
              await syncRecordDelete(op.table, op.entityId);
          }
        });
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
