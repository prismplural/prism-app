/// `SyncOutboxDrainer` + `SyncOutboxDao` + `persistCapturedOpsToOutbox` tests.
///
/// Pins the shared-infrastructure contracts the rest of the family depends on:
///  - `persistCapturedOpsToOutbox` round-trips an op multiset into durable rows
///    with faithful op_type (create/update/delete) and fields_json.
///  - The drainer dispatches in id order, deletes a row only AFTER the FFI
///    returns Ok (at-least-once), coalesces consecutive deletes per table,
///    blocks only the offending entity's lane on failure, defers (leaves rows
///    untouched) on a null handle / engine-unconfigured error, and quarantines
///    a row after N deterministic failures with one error report.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/sync_outbox_drainer.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

void main() {
  late AppDatabase db;
  const handle = _FakePrismSyncHandle();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('persistCapturedOpsToOutbox', () {
    test('round-trips create/update/delete with faithful op_type + fields',
        () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'},
            capturedAtMs: 1000),
        CapturedSyncOp('members', 'm1', SyncRecordOpType.update, {'name': 'B'},
            capturedAtMs: 2000),
        CapturedSyncOp('members', 'm1', SyncRecordOpType.delete, {},
            capturedAtMs: 3000),
      ]);

      final rows = await db.syncOutboxDao.allInIdOrder();
      expect(rows, hasLength(3));
      // id autoincrement preserves capture order.
      expect(rows.map((r) => r.entityTable), everyElement('members'));
      expect(rows.map((r) => r.entityId), everyElement('m1'));
      expect(rows.map((r) => r.opType), ['create', 'update', 'delete']);
      expect(rows[0].fieldsJson, '{"name":"A"}');
      expect(rows[1].fieldsJson, '{"name":"B"}');
      // Deletes carry no fields.
      expect(rows[2].fieldsJson, '{}');
      expect(rows.map((r) => r.createdAt), [1000, 2000, 3000]);
      expect(rows.map((r) => r.attempts), everyElement(0));
      expect(rows.map((r) => r.quarantined), everyElement(false));
    });

    test('a reconcile-shaped update op is persisted as a plain update', () async {
      // The reconcile/backfill entry points capture as SyncRecordOpType.update;
      // the outbox must store the real op_type (update), never a reconcile.
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.update, {'name': 'R'}),
      ]);
      final rows = await db.syncOutboxDao.allInIdOrder();
      expect(rows.single.opType, 'update');
    });

    test('empty list is a no-op', () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const []);
      expect(await db.syncOutboxDao.count(), 0);
    });
  });

  group('SyncOutboxDrainer drain', () {
    test('dispatches in id order and deletes each row after Ok', () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
        CapturedSyncOp('members', 'm2', SyncRecordOpType.update, {'name': 'B'}),
      ]);

      final dispatched = <String>[];
      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async {
          dispatched.add('${op.opType.name}:${op.table}/${op.entityId}');
        },
        dispatchDeleteMulti: (h, table, ids) async {
          dispatched.add('deleteMulti:$table:${ids.join(",")}');
        },
      );

      await drainer.drain(handle);

      expect(dispatched, [
        'create:members/m1',
        'update:members/m2',
      ]);
      // Rows deleted only after Ok.
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('at-least-once: a successful op is deleted; a failed op survives',
        () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
        CapturedSyncOp('chat_messages', 'c1', SyncRecordOpType.create, {'x': 1}),
      ]);

      final drainer = SyncOutboxDrainer(
        db,
        quarantineAfter: 5,
        dispatchOp: (h, op) async {
          if (op.table == 'chat_messages') {
            throw StateError('generic FFI failure');
          }
        },
      );

      await drainer.drain(handle);

      final rows = await db.syncOutboxDao.allInIdOrder();
      // m1 drained (deleted); c1 survives with attempts bumped.
      expect(rows, hasLength(1));
      expect(rows.single.entityId, 'c1');
      expect(rows.single.attempts, 1);
      expect(rows.single.lastError, contains('generic FFI failure'));
      expect(rows.single.quarantined, isFalse);
    });

    test('per-entity lane: an earlier failed row blocks later rows for the '
        'same entity, but a different entity still drains', () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        // m1 create fails -> blocks m1 update behind it.
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
        CapturedSyncOp('members', 'm1', SyncRecordOpType.update, {'name': 'B'}),
        // m2 is an independent lane and must still drain.
        CapturedSyncOp('members', 'm2', SyncRecordOpType.create, {'name': 'C'}),
      ]);

      final dispatched = <String>[];
      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async {
          dispatched.add(op.entityId);
          if (op.entityId == 'm1') {
            throw StateError('m1 is poison');
          }
        },
      );

      await drainer.drain(handle);

      // m1 create attempted (failed), m1 update NEVER attempted (lane blocked),
      // m2 still drained.
      expect(dispatched, ['m1', 'm2']);
      final rows = await db.syncOutboxDao.allInIdOrder();
      // m2 deleted; both m1 rows survive (the update never even attempted).
      expect(rows.map((r) => r.entityId), ['m1', 'm1']);
      expect(rows[0].attempts, 1); // create failed once
      expect(rows[1].attempts, 0); // update untouched (blocked)
    });

    test('null handle leaves all rows untouched', () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
      ]);

      var dispatched = 0;
      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async => dispatched++,
      );

      await drainer.drain(null);

      expect(dispatched, 0);
      expect(await db.syncOutboxDao.count(), 1);
    });

    test('engine-unconfigured error leaves rows untouched (deferral, not drop)',
        () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
        CapturedSyncOp('members', 'm2', SyncRecordOpType.create, {'name': 'B'}),
      ]);

      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async {
          throw StateError('engine error: sync not configured');
        },
      );

      await drainer.drain(handle);

      // No attempts bumped, no quarantine — pure deferral.
      final rows = await db.syncOutboxDao.allInIdOrder();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.attempts), everyElement(0));
      expect(rows.map((r) => r.quarantined), everyElement(false));
    });

    test('quarantines a row after N deterministic failures and reports once',
        () async {
      final reported = <AppError>[];
      void listener(AppError e) => reported.add(e);
      ErrorReportingService.instance.addListener(listener);
      addTearDown(() => ErrorReportingService.instance.removeListener(listener));

      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
      ]);

      final drainer = SyncOutboxDrainer(
        db,
        quarantineAfter: 3,
        dispatchOp: (h, op) async => throw StateError('always fails'),
      );

      // Three drain passes -> attempts 1, 2, 3 -> quarantined on the third.
      await drainer.drain(handle);
      expect((await db.syncOutboxDao.allInIdOrder()).single.quarantined, isFalse);
      await drainer.drain(handle);
      expect((await db.syncOutboxDao.allInIdOrder()).single.quarantined, isFalse);
      await drainer.drain(handle);

      final row = (await db.syncOutboxDao.allInIdOrder()).single;
      expect(row.attempts, 3);
      expect(row.quarantined, isTrue);
      // Exactly one quarantine report (only at the transition).
      expect(
        reported.where((e) => e.message.contains('quarantined')),
        hasLength(1),
      );

      // A subsequent pass leaves the quarantined row alone (no new dispatch,
      // no further reports).
      await drainer.drain(handle);
      expect((await db.syncOutboxDao.allInIdOrder()).single.attempts, 3);
      expect(
        reported.where((e) => e.message.contains('quarantined')),
        hasLength(1),
      );
    });

    test('coalesces consecutive same-table deletes into one recordDeleteMulti',
        () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.delete, {}),
        CapturedSyncOp('members', 'm2', SyncRecordOpType.delete, {}),
        CapturedSyncOp('members', 'm3', SyncRecordOpType.delete, {}),
      ]);

      final singleDeletes = <String>[];
      final multiCalls = <List<String>>[];
      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async => singleDeletes.add(op.entityId),
        dispatchDeleteMulti: (h, table, ids) async {
          expect(table, 'members');
          multiCalls.add(List.of(ids));
        },
      );

      await drainer.drain(handle);

      // One coalesced multi call for all three; no single-delete dispatches.
      expect(singleDeletes, isEmpty);
      expect(multiCalls, [
        ['m1', 'm2', 'm3'],
      ]);
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('a create between deletes breaks the coalesced run (order preserved)',
        () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.delete, {}),
        CapturedSyncOp('members', 'm2', SyncRecordOpType.delete, {}),
        CapturedSyncOp('members', 'm3', SyncRecordOpType.create, {'name': 'C'}),
        CapturedSyncOp('members', 'm4', SyncRecordOpType.delete, {}),
      ]);

      final ops = <String>[];
      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async => ops.add('${op.opType.name}:${op.entityId}'),
        dispatchDeleteMulti: (h, table, ids) async =>
            ops.add('multi:${ids.join(",")}'),
      );

      await drainer.drain(handle);

      expect(ops, [
        'multi:m1,m2',
        'create:m3',
        'multi:m4',
      ]);
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('single in-flight: a trigger during a pass coalesces into one re-run',
        () async {
      await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
        CapturedSyncOp('members', 'm1', SyncRecordOpType.create, {'name': 'A'}),
      ]);

      var passes = 0;
      late SyncOutboxDrainer drainer;
      final firstDispatch = Completer<void>();
      drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async {
          passes++;
          if (passes == 1) {
            // While pass 1 is mid-dispatch, fire a concurrent trigger.
            firstDispatch.complete();
            unawaited(drainer.drain(handle));
          }
        },
      );

      await drainer.drain(handle);
      await firstDispatch.future;

      // The row was deleted after pass 1, so the coalesced re-run finds an
      // empty outbox: dispatch ran exactly once.
      expect(passes, 1);
      expect(await db.syncOutboxDao.count(), 0);
    });
  });
}

/// Minimal stub handle. The drainer never touches it directly in these tests
/// (dispatch is injected), it only needs a non-null value to pass the
/// null-handle gate.
class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
