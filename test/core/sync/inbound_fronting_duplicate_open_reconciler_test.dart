import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/inbound_fronting_duplicate_open_reconciler.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show
        applyConsumerDeliveriesHealingUnappliable,
        reconcileInboundDuplicateOpensAfterSyncCompletedEvent,
        repairConsumerDeliverySpillQuarantineRows;
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

void main() {
  Future<void> seedMember(SyncAdapterWithCompletion adapter, String memberId) {
    return adapter.adapter.applyFields('members', memberId, {
      'name': 'Fixture-$memberId',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_active': true,
      'is_deleted': false,
    });
  }

  Future<void> seedSession(
    DriftFrontingSessionRepository repository, {
    required String id,
    required String memberId,
    required DateTime start,
    DateTime? end,
    String? pluralkitUuid,
  }) {
    return repository.createSession(
      FrontingSession(
        id: id,
        memberId: memberId,
        startTime: start,
        endTime: end,
        pluralkitUuid: pluralkitUuid,
      ),
    );
  }

  group('InboundFrontingDuplicateOpenReconciler', () {
    test('delayed two-device distinct-id switch closes the older open after '
        'delivery commit', () async {
      final previousMultiDatabaseWarning =
          drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousMultiDatabaseWarning;
      });
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final peerDb = AppDatabase(NativeDatabase.memory());
      addTearDown(peerDb.close);
      final adapter = buildSyncAdapterWithCompletion(db);
      final peerAdapter = buildSyncAdapterWithCompletion(peerDb);
      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      const memberId = 'member-01';
      await seedMember(adapter, memberId);
      await seedMember(peerAdapter, memberId);

      final repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final peerRepository = DriftFrontingSessionRepository(
        peerDb.frontingSessionsDao,
        null,
      );
      final earlier = DateTime.utc(2026, 9, 10, 10);
      final later = DateTime.utc(2026, 9, 10, 11);
      await seedSession(
        repository,
        id: 'session-device-01',
        memberId: memberId,
        start: earlier,
      );
      await seedSession(
        peerRepository,
        id: 'session-device-02',
        memberId: memberId,
        start: later,
      );
      final peerSession = (await peerRepository.getActiveSessions()).single;

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      var journal = <DrainChunk>[
        DrainChunk(
          deliveries: [
            ConsumerDelivery(
              id: 1,
              table: 'fronting_sessions',
              entityId: 'session-device-02',
              isDelete: false,
              fields: {
                'member_id': peerSession.memberId,
                'start_time': peerSession.startTime.toIso8601String(),
                'end_time': peerSession.endTime?.toIso8601String(),
                'session_type': 0,
                'is_health_kit_import': false,
                'is_deleted': false,
              },
            ),
          ],
          maxId: 1,
          spillUpToId: 0,
          overCap: false,
        ),
      ];

      adapter.beginSyncBatch();
      final drainResult = await runRemoteDeliveryDrain(
        take: (_) async => journal.isEmpty
            ? const DrainChunk(
                deliveries: [],
                maxId: 0,
                spillUpToId: 0,
                overCap: false,
              )
            : journal.single,
        ack: (_) async => journal = [],
        applyChanges: (deliveries) async {
          final applied = await applyConsumerDeliveriesHealingUnappliable(
            db,
            adapter.adapter,
            quarantine,
            deliveries,
          );
          expect(
            await repository.getActiveSessions(),
            hasLength(2),
            reason: 'the inbound apply does not mutate history itself',
          );
          return applied;
        },
        quarantineSpill: (rows) =>
            quarantineConsumerDeliverySpill(quarantine, rows),
      );
      await adapter.completeSyncBatch();

      expect(drainResult.touchedTables, {'fronting_sessions'});
      final result = await InboundFrontingDuplicateOpenReconciler(
        db,
        repository,
      ).reconcileAfterCommittedDelivery(drainResult.touchedTables);

      expect(result.sessionsClosed, 1);
      expect(result.membersWithDuplicateOpens, 1);
      final active = await repository.getActiveSessions();
      expect(active, hasLength(1));
      expect(active.single.id, 'session-device-02');
      final history = await repository.getFrontingSessions();
      expect(history, hasLength(2));
      expect(
        history.singleWhere((row) => row.id == 'session-device-01').endTime,
        later.toLocal(),
      );
      expect(
        captured.where(
          (op) =>
              op.table == 'fronting_sessions' &&
              op.opType == SyncRecordOpType.update &&
              op.entityId == 'session-device-01' &&
              op.fields['end_time'] != null,
        ),
        hasLength(1),
        reason: 'the close must be a synced repository update',
      );
      expect(
        captured.where((op) => op.opType == SyncRecordOpType.delete),
        isEmpty,
        reason: 'reconciliation preserves both history rows',
      );
    });

    test(
      'spill replay reconciles only after its fronting row commits',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final adapter = buildSyncAdapterWithCompletion(db);
        final quarantine = SyncQuarantineService(db.syncQuarantineDao);
        const memberId = 'member-spill';
        await seedMember(adapter, memberId);
        final repository = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final earlier = DateTime.utc(2026, 9, 5, 8);
        final later = DateTime.utc(2026, 9, 5, 9);
        await seedSession(
          repository,
          id: 'spill-older',
          memberId: memberId,
          start: earlier,
        );
        await quarantineConsumerDeliverySpill(quarantine, [
          ConsumerDelivery(
            id: 1,
            table: 'fronting_sessions',
            entityId: 'spill-newer',
            isDelete: false,
            fields: {
              'member_id': memberId,
              'start_time': later.toIso8601String(),
              'end_time': null,
              'session_type': 0,
              'is_health_kit_import': false,
              'is_deleted': false,
            },
          ),
        ]);

        var callbackSawCommittedRows = false;
        final repaired = await repairConsumerDeliverySpillQuarantineRows(
          db,
          adapter,
          db.syncQuarantineDao,
          onCommittedTables: (touchedTables) async {
            expect(touchedTables, {'fronting_sessions'});
            expect(await repository.getActiveSessions(), hasLength(2));
            callbackSawCommittedRows = true;
            await InboundFrontingDuplicateOpenReconciler(
              db,
              repository,
            ).reconcileAfterCommittedDelivery(touchedTables);
          },
        );

        expect(repaired, 1);
        expect(callbackSawCommittedRows, isTrue);
        expect(await db.syncQuarantineDao.getAll(), isEmpty);
        final active = await repository.getActiveSessions();
        expect(active.map((session) => session.id), ['spill-newer']);
      },
    );

    test('SyncCompleted reconciliation uses committed tables from an aborted '
        'drain', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db);
      const memberId = 'member-completed';
      await seedMember(adapter, memberId);
      final repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await seedSession(
        repository,
        id: 'completed-older',
        memberId: memberId,
        start: DateTime.utc(2026, 9, 6, 8),
      );
      final newer = DateTime.utc(2026, 9, 6, 9);
      final event = SyncEvent('SyncCompleted', {
        'type': 'SyncCompleted',
        'result': {'error_kind': 'Network'},
      });

      await reconcileInboundDuplicateOpensAfterSyncCompletedEvent(
        event,
        strict: false,
        drain: () async {
          adapter.beginSyncBatch();
          await adapter.adapter
              .applyFields('fronting_sessions', 'completed-newer', {
                'member_id': memberId,
                'start_time': newer.toIso8601String(),
                'end_time': null,
                'session_type': 0,
                'is_health_kit_import': false,
                'is_deleted': false,
              });
          await adapter.completeSyncBatch();
          return const DrainResult(
            rowsApplied: 1,
            rowsSpilled: 0,
            chunksAcked: 1,
            aborted: true,
            touchedTables: {'fronting_sessions'},
          );
        },
        reconciler: InboundFrontingDuplicateOpenReconciler(db, repository),
      );

      final active = await repository.getActiveSessions();
      expect(active.map((session) => session.id), ['completed-newer']);
    });

    test('same-id replay is a no-op', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db);
      const memberId = 'member-02';
      await seedMember(adapter, memberId);
      final repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      final start = DateTime.utc(2026, 9, 10, 12);

      for (var replay = 0; replay < 2; replay++) {
        adapter.beginSyncBatch();
        await adapter.adapter
            .applyFields('fronting_sessions', 'stable-session-id', {
              'member_id': memberId,
              'start_time': start.toIso8601String(),
              'end_time': null,
              'session_type': 0,
              'is_health_kit_import': false,
              'is_deleted': false,
            });
        await adapter.completeSyncBatch();
      }

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);
      final result = await InboundFrontingDuplicateOpenReconciler(
        db,
        repository,
      ).reconcileAfterCommittedDelivery({'fronting_sessions'});

      expect(result.sessionsClosed, 0);
      expect(await repository.getActiveSessions(), hasLength(1));
      expect(await repository.getFrontingSessions(), hasLength(1));
      expect(captured, isEmpty);
    });

    test(
      'only true duplicate opens change; other history and PK identity remain',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        final base = DateTime.utc(2026, 9, 1);

        await seedSession(
          repository,
          id: 'duplicate-open-older',
          memberId: 'member-duplicate',
          start: base.add(const Duration(hours: 1)),
          pluralkitUuid: '00000000-0000-4000-8000-000000000001',
        );
        await seedSession(
          repository,
          id: 'duplicate-open-newer',
          memberId: 'member-duplicate',
          start: base.add(const Duration(hours: 2)),
        );
        await seedSession(
          repository,
          id: 'adjacent-01',
          memberId: 'member-adjacent',
          start: base.add(const Duration(hours: 3)),
          end: base.add(const Duration(hours: 4)),
        );
        await seedSession(
          repository,
          id: 'adjacent-02',
          memberId: 'member-adjacent',
          start: base.add(const Duration(hours: 4)),
          end: base.add(const Duration(hours: 5)),
        );
        await seedSession(
          repository,
          id: 'closed-overlap-01',
          memberId: 'member-overlap',
          start: base.add(const Duration(hours: 6)),
          end: base.add(const Duration(hours: 8)),
          pluralkitUuid: '00000000-0000-4000-8000-000000000002',
        );
        await seedSession(
          repository,
          id: 'closed-overlap-02',
          memberId: 'member-overlap',
          start: base.add(const Duration(hours: 7)),
          end: base.add(const Duration(hours: 9)),
          pluralkitUuid: '00000000-0000-4000-8000-000000000003',
        );
        await seedSession(
          repository,
          id: 'clean-open',
          memberId: 'member-clean',
          start: base.add(const Duration(hours: 10)),
        );
        final before = {
          for (final row in await repository.getFrontingSessions()) row.id: row,
        };

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);
        final result = await InboundFrontingDuplicateOpenReconciler(
          db,
          repository,
        ).reconcileAfterCommittedDelivery({'fronting_sessions'});

        expect(result.sessionsClosed, 1);
        final afterRows = await repository.getFrontingSessions();
        expect(afterRows, hasLength(before.length));
        final after = {for (final row in afterRows) row.id: row};
        expect(
          after['duplicate-open-older']!.endTime,
          before['duplicate-open-newer']!.startTime,
        );
        expect(
          after['duplicate-open-older']!.pluralkitUuid,
          before['duplicate-open-older']!.pluralkitUuid,
        );
        for (final id in [
          'duplicate-open-newer',
          'adjacent-01',
          'adjacent-02',
          'closed-overlap-01',
          'closed-overlap-02',
          'clean-open',
        ]) {
          expect(after[id], before[id], reason: '$id must remain unchanged');
        }
        expect(captured, hasLength(1));
        expect(captured.single.entityId, 'duplicate-open-older');
      },
    );

    test(
      'concurrent delivery completions serialize without duplicate writes',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        await seedSession(
          repository,
          id: 'serial-older',
          memberId: 'member-serial',
          start: DateTime.utc(2026, 9, 2, 8),
        );
        await seedSession(
          repository,
          id: 'serial-newer',
          memberId: 'member-serial',
          start: DateTime.utc(2026, 9, 2, 9),
        );
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        final reconciler = InboundFrontingDuplicateOpenReconciler(
          db,
          repository,
        );
        final results = await Future.wait([
          reconciler.reconcileAfterCommittedDelivery({'fronting_sessions'}),
          reconciler.reconcileAfterCommittedDelivery({'fronting_sessions'}),
        ]);

        expect(
          results.map((result) => result.sessionsClosed),
          containsAll([0, 1]),
        );
        expect(await repository.getActiveSessions(), hasLength(1));
        expect(captured, hasLength(1));
      },
    );

    test(
      'a concurrent local close cannot be overwritten by the repair',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repairRepository = _BlockingRepairRepository(
          db.frontingSessionsDao,
        );
        final localRepository = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );
        const memberId = 'member-concurrent-close';
        final earlier = DateTime.utc(2026, 9, 7, 8);
        final duplicateStart = DateTime.utc(2026, 9, 7, 9);
        final localCloseAt = DateTime.utc(2026, 9, 7, 10);
        await seedSession(
          repairRepository,
          id: 'concurrent-close-older',
          memberId: memberId,
          start: earlier,
        );
        await seedSession(
          repairRepository,
          id: 'concurrent-close-newer',
          memberId: memberId,
          start: duplicateStart,
        );

        final repair = InboundFrontingDuplicateOpenReconciler(
          db,
          repairRepository,
        ).reconcileAfterCommittedDelivery({'fronting_sessions'});
        await repairRepository.repairCloseReached.future;

        var localCloseCompleted = false;
        final localClose = localRepository
            .endSession('concurrent-close-older', localCloseAt)
            .then((_) => localCloseCompleted = true);
        await Future<void>.delayed(Duration.zero);
        expect(
          localCloseCompleted,
          isFalse,
          reason: 'the local writer must wait for the repair transaction',
        );

        repairRepository.allowRepairClose.complete();
        await repair;
        await localClose;

        final older = await localRepository.getSessionById(
          'concurrent-close-older',
        );
        expect(
          older!.endTime,
          localCloseAt.toLocal(),
          reason: 'the already-valid local close must win over the repair',
        );
      },
    );

    test('completed repair stays idempotent after database restart', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prism-inbound-front-reconcile-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final file = File('${directory.path}/state.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      addTearDown(() => db.close());
      var repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await seedSession(
        repository,
        id: 'restart-older',
        memberId: 'member-restart',
        start: DateTime.utc(2026, 9, 3, 8),
      );
      await seedSession(
        repository,
        id: 'restart-newer',
        memberId: 'member-restart',
        start: DateTime.utc(2026, 9, 3, 9),
      );
      expect(
        (await InboundFrontingDuplicateOpenReconciler(
              db,
              repository,
            ).reconcileAfterCommittedDelivery({'fronting_sessions'}))
            .sessionsClosed,
        1,
      );
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      repository = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);
      final afterRestart = await InboundFrontingDuplicateOpenReconciler(
        db,
        repository,
      ).reconcileAfterCommittedDelivery({'fronting_sessions'});

      expect(afterRestart.sessionsClosed, 0);
      expect(await repository.getActiveSessions(), hasLength(1));
      expect(await repository.getFrontingSessions(), hasLength(2));
      expect(captured, isEmpty);
    });

    test('unrelated inbound tables do not trigger a scan or write', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      await seedSession(
        repository,
        id: 'untouched-older',
        memberId: 'member-untouched',
        start: DateTime.utc(2026, 9, 4, 8),
      );
      await seedSession(
        repository,
        id: 'untouched-newer',
        memberId: 'member-untouched',
        start: DateTime.utc(2026, 9, 4, 9),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final result = await InboundFrontingDuplicateOpenReconciler(
        db,
        repository,
      ).reconcileAfterCommittedDelivery({'members'});

      expect(result.frontingTableTouched, isFalse);
      expect(await repository.getActiveSessions(), hasLength(2));
      expect(captured, isEmpty);
    });
  });
}

class _BlockingRepairRepository extends DriftFrontingSessionRepository {
  _BlockingRepairRepository(FrontingSessionsDao dao) : super(dao, null);

  final repairCloseReached = Completer<void>();
  final allowRepairClose = Completer<void>();

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    if (!repairCloseReached.isCompleted) {
      repairCloseReached.complete();
      await allowRepairClose.future;
    }
    await super.endSession(id, endTime);
  }
}
