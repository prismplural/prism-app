/// `SyncRecordMixin` tests.
///
/// Pins three contracts:
///
/// 1. The suppression contract used by the per-member fronting migration:
///    - [SyncRecordMixin.suppress] short-circuits every `syncRecord*`
///      call so the FFI never runs while the body executes.
///    - Outside `suppress`, the mixin behaves as before.
///    - The flag clears even if the body throws (verified via a probe
///      repository that records every FFI invocation).
///
/// 2. The durable-outbox emit contract: a live `syncRecord*` call no
///    longer dispatches the FFI inline. On a sync-paired device it persists an
///    outbox row and triggers the drainer (the drainer owns engine-availability
///    handling); on a never-paired device it enqueues nothing. A Drift insert
///    failure is reported once and swallowed (the data row is already
///    committed).
///
/// 3. The suppress/capture seam still routes emissions to a capture sink and
///    stamps `capturedAtMs`.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/core/sync/sync_outbox_drainer.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // Default to "paired" for the enqueue tests; individual tests flip it.
    syncCredentialsPersisted.value = true;
  });

  tearDown(() async {
    SyncRecordMixin.debugInstallOutboxRuntimeForTesting();
    syncCredentialsPersisted.value = false;
    syncAutoConfigureInProgress.value = false;
    syncCurrentHandle.value = null;
    // Tolerate a test that already closed the DB (the enqueue-failure case).
    try {
      await db.close();
    } catch (_) {}
  });

  group('SyncRecordMixin.suppress', () {
    test(
      'short-circuits syncRecordCreate / Update / Delete inside body',
      () async {
        final repo = _ProbeRepository();

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

        // Suppression short-circuits before the enqueue path, so nothing lands
        // in the outbox even though credentials are "persisted".
        expect(await db.syncOutboxDao.count(), 0);
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
  });

  group('SyncRecordMixin durable-outbox enqueue (F05)', () {
    test(
      'null handle + not-in-progress persists a durable outbox row '
      '(inverts the old "skip quietly" behavior)',
      () async {
        final repo = _ProbeRepository();
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async {}, // no-op: assert the persisted row only
        );

        // No handle, not auto-configuring — the historical drop path. It now
        // durably enqueues instead.
        await repo.syncRecordUpdate('members', 'm1', {'name': 'Later'});

        final rows = await db.syncOutboxDao.allInIdOrder();
        expect(rows, hasLength(1));
        expect(rows.single.opType, 'update');
        expect(rows.single.entityTable, 'members');
        expect(rows.single.entityId, 'm1');
        expect(rows.single.fieldsJson, '{"name":"Later"}');
      },
    );

    test('never-paired device enqueues nothing', () async {
      final repo = _ProbeRepository();
      syncCredentialsPersisted.value = false;
      SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
        db: db,
        drainTrigger: (_) async {},
      );

      await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
      await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
      await repo.syncRecordDelete('members', 'm1');

      expect(await db.syncOutboxDao.count(), 0);
    });

    test(
      'enqueue then drain after a handle install emits exactly the op '
      'and deletes the row',
      () async {
        final repo = _ProbeRepository();
        final dispatched = <String>[];
        final drainer = SyncOutboxDrainer(
          db,
          dispatchOp: (h, op) async {
            dispatched.add('${op.opType.name}:${op.table}/${op.entityId}');
          },
        );
        // No handle yet: the trigger drains against null (a no-op deferral).
        ffi.PrismSyncHandle? installedHandle;
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) => drainer.drain(installedHandle),
        );

        await repo.syncRecordUpdate('members', 'm1', {'name': 'A'});
        // The trigger ran with a null handle — row still pending.
        expect(dispatched, isEmpty);
        expect(await db.syncOutboxDao.count(), 1);

        // Handle installed; an explicit drain dispatches the row and deletes it.
        installedHandle = const _FakePrismSyncHandle();
        await drainer.drain(installedHandle);

        expect(dispatched, ['update:members/m1']);
        expect(await db.syncOutboxDao.count(), 0);
      },
    );

    test(
      "FFI 'sync not configured' leaves attempts unchanged (deferral)",
      () async {
        await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
          CapturedSyncOp('members', 'm1', SyncRecordOpType.update, {'k': 'v'}),
        ]);

        const handle = _FakePrismSyncHandle();
        final drainer = SyncOutboxDrainer(
          db,
          quarantineAfter: 3,
          dispatchOp: (h, op) async =>
              throw StateError('engine error: sync not configured'),
        );

        // Several passes — a deferral must never increment attempts or
        // quarantine; the row is left untouched for the next trigger.
        for (var i = 0; i < 4; i++) {
          await drainer.drainOnce(handle);
        }

        final m1 = (await db.syncOutboxDao.allInIdOrder()).single;
        expect(m1.entityId, 'm1');
        expect(m1.attempts, 0);
        expect(m1.quarantined, isFalse);
      },
    );

    test(
      'a generic FFI error quarantines after N without blocking a '
      'different entity',
      () async {
        // c1 hits a generic error (quarantines after N); c2 is an independent
        // lane that must still drain to completion.
        await SyncRecordMixin.persistCapturedOpsToOutbox(db, const [
          CapturedSyncOp('chat_messages', 'c1', SyncRecordOpType.create, {'x': 1}),
          CapturedSyncOp('chat_messages', 'c2', SyncRecordOpType.create, {'y': 2}),
        ]);

        const handle = _FakePrismSyncHandle();
        final dispatched = <String>[];
        final drainer = SyncOutboxDrainer(
          db,
          quarantineAfter: 3,
          dispatchOp: (h, op) async {
            dispatched.add(op.entityId);
            if (op.entityId == 'c1') {
              throw StateError('generic boom');
            }
            // c2 succeeds.
          },
        );

        for (var i = 0; i < 4; i++) {
          await drainer.drainOnce(handle);
        }

        final rows = await db.syncOutboxDao.allInIdOrder();
        // c1 quarantined after N generic failures; it blocks only its own lane.
        final c1 = rows.firstWhere((r) => r.entityId == 'c1');
        expect(c1.quarantined, isTrue);
        // c2 (a different entity) drained successfully despite c1's poison.
        expect(rows.any((r) => r.entityId == 'c2'), isFalse);
        expect(dispatched, contains('c2'));
      },
    );

    test('an enqueue failure is reported once and swallowed', () async {
      final reported = <AppError>[];
      void listener(AppError e) => reported.add(e);
      ErrorReportingService.instance.addListener(listener);
      addTearDown(() => ErrorReportingService.instance.removeListener(listener));

      final repo = _ProbeRepository();
      SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
        db: db,
        drainTrigger: (_) async {},
      );

      // A non-JSON-encodable field value makes the outbox row build (jsonEncode)
      // throw inside the enqueue. The data row is already committed upstream, so
      // the user must not see a failure — it is reported once and swallowed.
      await repo.syncRecordCreate('members', 'm1', {'bad': Object()});

      expect(await db.syncOutboxDao.count(), 0);
      expect(
        reported.where((e) => e.message.contains('outbox enqueue failed')),
        hasLength(1),
      );
    });

    test(
      'syncRecordDeleteMulti enqueues one durable row per id (drainer coalesces)',
      () async {
        final repo = _ProbeRepository();
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async {},
        );

        await repo.syncRecordDeleteMulti('members', const ['m1', 'm2', 'm3']);

        final rows = await db.syncOutboxDao.allInIdOrder();
        expect(rows.map((r) => r.entityId), ['m1', 'm2', 'm3']);
        expect(rows.map((r) => r.opType), everyElement('delete'));
      },
    );

    test('drain fires from a simulated disconnected-health boot path', () async {
      // Simulates the disconnected-boot gap: an edit is enqueued while the
      // engine is unconfigured (the live trigger drains against null), then a
      // later boot trigger drains REGARDLESS of health outcome and flushes it.
      final repo = _ProbeRepository();
      final dispatched = <String>[];
      ffi.PrismSyncHandle? handle; // null during the "disconnected" window
      final drainer = SyncOutboxDrainer(
        db,
        dispatchOp: (h, op) async => dispatched.add(op.entityId),
      );
      SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
        db: db,
        drainTrigger: (_) => drainer.drain(handle),
      );

      // Edit made while disconnected: enqueued, drain no-ops against null.
      await repo.syncRecordUpdate('members', 'm1', {'name': 'A'});
      expect(dispatched, isEmpty);
      expect(await db.syncOutboxDao.count(), 1);

      // Boot ends with the engine configured but health "disconnected"; the
      // unconditional boot drain still flushes the stranded row.
      handle = const _FakePrismSyncHandle();
      await drainer.drain(handle);

      expect(dispatched, ['m1']);
      expect(await db.syncOutboxDao.count(), 0);
    });

    test(
      'emit inside a Drift transaction dispatches NO FFI before commit '
      '(emit-after-commit invariant)',
      () async {
        // The reachable-today shape: an unsuppressed importer emits
        // a live syncRecord* INSIDE db.transaction(). The outbox row must be
        // persisted atomically with the data write, but the live trigger must
        // NOT fire the drain (which would dispatch FFI before the outer commit
        // and leak on rollback). The post-commit drain picks the row up.
        final repo = _ProbeRepository();
        final dispatched = <String>[];
        const handle = _FakePrismSyncHandle();
        final drainer = SyncOutboxDrainer(
          db,
          dispatchOp: (h, op) async => dispatched.add(op.entityId),
        );
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) => drainer.drain(handle),
        );

        await db.transaction(() async {
          await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
          // Inside the open transaction: row enqueued, but NO FFI dispatched —
          // the live trigger was skipped because we are mid-transaction.
          expect(dispatched, isEmpty);
          expect(await db.syncOutboxDao.count(), 1);
        });

        // Still no dispatch right after commit (the live trigger never fired).
        expect(dispatched, isEmpty);
        expect(await db.syncOutboxDao.count(), 1);

        // A post-commit drain (boot/resume/catch-up) flushes it.
        await drainer.drain(handle);
        expect(dispatched, ['m1']);
        expect(await db.syncOutboxDao.count(), 0);
      },
    );

    test(
      'a rolled-back transaction leaves the data row absent AND no FFI '
      'dispatched (no phantom op)',
      () async {
        final repo = _ProbeRepository();
        final dispatched = <String>[];
        const handle = _FakePrismSyncHandle();
        final drainer = SyncOutboxDrainer(
          db,
          dispatchOp: (h, op) async => dispatched.add(op.entityId),
        );
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) => drainer.drain(handle),
        );

        Object? caught;
        try {
          await db.transaction(() async {
            await db
                .into(db.members)
                .insert(
                  MembersCompanion(
                    id: const Value('m1'),
                    name: const Value('Phantom'),
                    emoji: const Value('P'),
                    createdAt: Value(DateTime.now().toUtc()),
                  ),
                );
            await repo.syncRecordCreate('members', 'm1', {'name': 'Phantom'});
            // Give any fire-and-forget drain a chance to run BEFORE we roll
            // back. With the guard in place no drain is triggered in-txn, so
            // nothing dispatches; without it, this is the window where the old
            // code would have leaked a phantom FFI op (the row is deleted by
            // the drain but the data + outbox writes still roll back).
            await pumpEventQueue();
            throw StateError('import failed mid-transaction');
          });
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<StateError>());
        // Both the data row and the outbox row rolled back with the txn.
        expect(
          await db.select(db.members).get(),
          isEmpty,
          reason: 'data row must not survive the rollback',
        );
        expect(await db.syncOutboxDao.count(), 0);
        // No FFI ever dispatched — the op was never sent to a peer.
        expect(dispatched, isEmpty);
        // A subsequent drain finds nothing to send (no phantom op leaked).
        await drainer.drain(handle);
        expect(dispatched, isEmpty);
      },
    );
  });

  group('SyncRecordMixin.suppressAndCapture', () {
    test('plain suppress drops emissions', () async {
      final repo = _ProbeRepository();
      await SyncRecordMixin.suppress(() async {
        await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        await repo.syncRecordDelete('members', 'm1');
      });
      expect(await db.syncOutboxDao.count(), 0);
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
    });

    test(
      'nested suppress inside suppressAndCapture drops inner emissions',
      () async {
        final repo = _ProbeRepository();
        final outer = <CapturedSyncOp>[];

        await SyncRecordMixin.suppressAndCapture(() async {
          await repo.syncRecordCreate('members', 'outer', {'k': 'v'});
          await SyncRecordMixin.suppress(() async {
            await repo.syncRecordCreate('members', 'inner', {'k': 'v'});
            await repo.syncRecordUpdate('members', 'inner', {'k': 'v2'});
          });
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

        expect(inner.map((o) => o.entityId), ['inner']);
        expect(outer.map((o) => o.entityId), ['outer', 'outer-2']);
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
      expect(captured, hasLength(1));
      expect(SyncRecordMixin.isSuppressed, isFalse);
    });
  });

  group('SyncRecordMixin capture sink install/remove guard', () {
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

      SyncRecordMixin.installCaptureSinkForTesting(sinkB);
      expect(SyncRecordMixin.hasCaptureSink, isTrue);
      SyncRecordMixin.removeCaptureSinkForTesting();
    });
  });

  group('SyncRecordMixin.runSyncedWrite (F08)', () {
    test(
      'success: data row + outbox rows commit together, in capture order, '
      'before any FFI dispatch',
      () async {
        final repo = _ProbeRepository();
        final dispatched = <String>[];
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          // No-op drain: assert the persisted rows BEFORE any dispatch.
          drainTrigger: (_) async {},
        );

        await repo.runSyncedWrite(() async {
          await db
              .into(db.members)
              .insert(
                MembersCompanion(
                  id: const Value('m1'),
                  name: const Value('A'),
                  emoji: const Value('A'),
                  createdAt: Value(DateTime.now().toUtc()),
                ),
              );
          await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
          await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        });

        // Data row committed.
        expect((await db.select(db.members).get()).single.id, 'm1');
        // Outbox rows present in capture order; nothing dispatched yet.
        final rows = await db.syncOutboxDao.allInIdOrder();
        expect(rows.map((r) => r.entityId), ['m1', 'm1']);
        expect(rows.map((r) => r.opType), ['create', 'update']);
        expect(dispatched, isEmpty);
      },
    );

    test(
      'body throw: data rows AND outbox rows both absent (atomic rollback)',
      () async {
        final repo = _ProbeRepository();
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async {},
        );

        Object? caught;
        try {
          await repo.runSyncedWrite(() async {
            await db
                .into(db.members)
                .insert(
                  MembersCompanion(
                    id: const Value('m1'),
                    name: const Value('Phantom'),
                    emoji: const Value('P'),
                    createdAt: Value(DateTime.now().toUtc()),
                  ),
                );
            await repo.syncRecordCreate('members', 'm1', {'name': 'Phantom'});
            throw StateError('mutation failed mid-write');
          });
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<StateError>());
        expect(
          await db.select(db.members).get(),
          isEmpty,
          reason: 'data row must roll back',
        );
        expect(
          await db.syncOutboxDao.count(),
          0,
          reason: 'outbox row must roll back atomically with the data',
        );
      },
    );

    test(
      'never-paired device: body still writes data, but persists no outbox row',
      () async {
        syncCredentialsPersisted.value = false;
        final repo = _ProbeRepository();
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async {},
        );

        await repo.runSyncedWrite(() async {
          await db
              .into(db.members)
              .insert(
                MembersCompanion(
                  id: const Value('m1'),
                  name: const Value('A'),
                  emoji: const Value('A'),
                  createdAt: Value(DateTime.now().toUtc()),
                ),
              );
          await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        });

        expect((await db.select(db.members).get()).single.id, 'm1');
        expect(await db.syncOutboxDao.count(), 0);
      },
    );

    test(
      'crash-sim: a fresh drainer over the same DB recovers the persisted op '
      'after a "relaunch" with the drainer disabled at write time',
      () async {
        final repo = _ProbeRepository();
        // Write time: drainer "disabled" (no-op trigger), simulating a process
        // that committed the outbox row then died before dispatch.
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async {},
        );
        await repo.runSyncedWrite(() async {
          await repo.syncRecordDelete('members', 'gone');
        });
        expect(await db.syncOutboxDao.count(), 1);

        // "Relaunch": a fresh drainer constructed over the same DB drains it.
        final dispatched = <String>[];
        final drainer = SyncOutboxDrainer(
          db,
          dispatchOp: (h, op) async =>
              dispatched.add('${op.opType.name}:${op.entityId}'),
          dispatchDeleteMulti: (h, table, ids) async {
            for (final id in ids) {
              dispatched.add('delete:$id');
            }
          },
        );
        await drainer.drain(const _FakePrismSyncHandle());

        expect(dispatched, ['delete:gone']);
        expect(await db.syncOutboxDao.count(), 0);
      },
    );

    test('an outer suppression wins: runSyncedWrite defers to it', () async {
      final repo = _ProbeRepository();
      SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
        db: db,
        drainTrigger: (_) async {},
      );

      // Under suppress, the body's emission must be dropped (not enqueued) —
      // runSyncedWrite must not install its own capture context and shadow the
      // outer suppression (the burned-id sentinel path relies on this).
      await SyncRecordMixin.suppress(() async {
        await repo.runSyncedWrite(() async {
          await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        });
      });

      expect(await db.syncOutboxDao.count(), 0);
    });
  });

  group('F19/F37 fenced-emission defense in depth', () {
    test(
      'a live emit that escapes the capture seam inside a fenced transaction '
      'asserts in debug/test',
      () async {
        final repo = _ProbeRepository();
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async {},
        );

        // Simulate the regression the assert guards: inside a fenced emission
        // transaction, an inner operation reaches the LIVE emit path because it
        // ran outside the suppress/capture seam. We reproduce "outside the
        // seam, still inside the fence" by clearing only the capture-context
        // zone value while the fence flag stays set.
        final captured = <CapturedSyncOp>[];
        await expectLater(
          SyncRecordMixin.runFencedEmissionTransaction<void>(db, () async {
            await runZoned(
              () => repo.syncRecordCreate('members', 'escaped', {'k': 'v'}),
              // #prismSyncCaptureContext is the mixin's private capture key;
              // nulling it drops the capture context inherited from the fence's
              // suppressAndCapture, leaving the fence flag in place.
              zoneValues: {#prismSyncCaptureContext: null},
            );
          }, captured.add),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test(
      'runFencedEmissionTransaction captures emissions and persists them '
      'inside the transaction (no live dispatch)',
      () async {
        final repo = _ProbeRepository();
        var triggered = 0;
        SyncRecordMixin.debugInstallOutboxRuntimeForTesting(
          db: db,
          drainTrigger: (_) async => triggered++,
        );

        final captured = <CapturedSyncOp>[];
        await SyncRecordMixin.runFencedEmissionTransaction<void>(db, () async {
          await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
          await SyncRecordMixin.persistCapturedOpsToOutbox(db, captured);
        }, captured.add);

        // The emission was captured (not dispatched live) and persisted.
        expect(captured, hasLength(1));
        expect(triggered, 0, reason: 'no live drain trigger fired in the fence');
        final rows = await db.syncOutboxDao.allInIdOrder();
        expect(rows.single.entityId, 'm1');
      },
    );
  });

  group('CapturedSyncOp.capturedAtMs + reconcile/backfill entry points', () {
    test('live syncRecord* stamp capturedAtMs at construction', () async {
      final repo = _ProbeRepository();
      final captured = <CapturedSyncOp>[];
      final before = DateTime.now().millisecondsSinceEpoch;

      await SyncRecordMixin.suppressAndCapture(() async {
        await repo.syncRecordCreate('members', 'm1', {'name': 'A'});
        await repo.syncRecordUpdate('members', 'm1', {'name': 'B'});
        await repo.syncRecordDelete('members', 'm1');
      }, captured.add);

      final after = DateTime.now().millisecondsSinceEpoch;
      expect(captured, hasLength(3));
      for (final op in captured) {
        expect(op.capturedAtMs, isNotNull);
        expect(op.capturedAtMs! >= before && op.capturedAtMs! <= after, isTrue);
      }
    });

    test('syncRecordReconcile / syncRecordBackfill capture as update ops', () async {
      final repo = _ProbeRepository();
      final captured = <CapturedSyncOp>[];

      await SyncRecordMixin.suppressAndCapture(() async {
        await repo.syncRecordReconcile('members', 'm1', {'name': 'R'});
        await repo.syncRecordBackfill('members', 'm2', {'name': 'B'});
      }, captured.add);

      expect(captured, hasLength(2));
      expect(captured[0].opType, SyncRecordOpType.update);
      expect(captured[0].entityId, 'm1');
      expect(captured[0].fields, {'name': 'R'});
      expect(captured[0].capturedAtMs, isNotNull);
      expect(captured[1].opType, SyncRecordOpType.update);
      expect(captured[1].entityId, 'm2');
      expect(captured[1].fields, {'name': 'B'});
    });
  });
}

/// Test double whose `syncHandle` getter is always null (the live path resolves
/// the handle only for the fire-and-forget drain trigger).
class _ProbeRepository with SyncRecordMixin {
  @override
  ffi.PrismSyncHandle? get syncHandle => null;
}

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
