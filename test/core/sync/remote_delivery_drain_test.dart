import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync_drift/prism_sync_drift.dart' show DriftSyncAdapter;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/remote_delivery_drain.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';

/// In-memory stand-in for the Rust consumer-delivery journal. Mimics the
/// FFI `take_undelivered_changes` / `ack_consumer_deliveries` contract: rows
/// are append-only with monotonic ids, `take` reads in id order, and `ack`
/// deletes everything `id <= upToId`. The cap drives the over-cap spill flags
/// exactly as the engine does (`take` flags the oldest `total - cap` rows).
class _FakeJournal {
  _FakeJournal({this.cap = 1 << 30});

  final int cap;
  final List<Map<String, dynamic>> _rows = [];
  int _nextId = 0;
  int takeCalls = 0;
  int ackCalls = 0;

  /// Append one journal row (one winning op). Returns the assigned id.
  int append({
    required String table,
    required String entityId,
    required bool isDelete,
    String? fieldName,
    String? encodedValue,
  }) {
    final id = ++_nextId;
    _rows.add({
      'id': id,
      'table': table,
      'entity_id': entityId,
      'is_delete': isDelete,
      'field_name': fieldName,
      'encoded_value': encodedValue,
    });
    return id;
  }

  int get length => _rows.length;

  Future<DrainChunk> take(int limit) async {
    takeCalls++;
    final slice = _rows.take(limit).toList();
    if (slice.isEmpty) {
      return const DrainChunk(
        deliveries: [],
        maxId: 0,
        spillUpToId: 0,
        overCap: false,
      );
    }
    final total = _rows.length;
    final overCap = total > cap;
    // Oldest `total - cap` rows spill; spill_up_to_id is the highest such id
    // present in this slice.
    var spillUpToId = 0;
    if (overCap) {
      final spillCount = total - cap;
      final threshold = _rows[spillCount - 1]['id'] as int;
      for (final r in slice) {
        final id = r['id'] as int;
        if (id <= threshold) spillUpToId = id;
      }
    }
    // Coalesce per (table, entity_id) the same way the FFI does (delete is
    // absorbing) so the drain consumes the same shape it would in production.
    final order = <String>[];
    final acc = <String, Map<String, dynamic>>{};
    for (final r in slice) {
      final key = '${r['table']}\u0001${r['entity_id']}';
      final entry = acc.putIfAbsent(key, () {
        order.add(key);
        return {
          'id': r['id'],
          'table': r['table'],
          'entity_id': r['entity_id'],
          'is_delete': false,
          'fields': <String, dynamic>{},
        };
      });
      entry['id'] = (entry['id'] as int) > (r['id'] as int)
          ? entry['id']
          : r['id'];
      if (r['is_delete'] as bool) {
        entry['is_delete'] = true;
        (entry['fields'] as Map).clear();
      } else if (!(entry['is_delete'] as bool)) {
        final fieldName = r['field_name'] as String?;
        if (fieldName != null) {
          // Mirror the Rust FFI coalescer: decode the wire `encoded_value`
          // into its natural JSON type so `fields` matches the RemoteChanges
          // shape the apply pipeline expects.
          final encoded = r['encoded_value'] as String?;
          (entry['fields'] as Map<String, dynamic>)[fieldName] = encoded == null
              ? null
              : jsonDecode(encoded);
        }
      }
    }
    final deliveries = order.map((k) => acc[k]!).toList();
    final maxId = slice
        .map((r) => r['id'] as int)
        .reduce((a, b) => a > b ? a : b);
    return DrainChunk.fromJson({
      'deliveries': deliveries,
      'max_id': maxId,
      'spill_up_to_id': spillUpToId,
      'over_cap': overCap,
    });
  }

  Future<void> ack(int upToId) async {
    ackCalls++;
    _rows.removeWhere((r) => (r['id'] as int) <= upToId);
  }
}

void main() {
  // Several cases open multiple isolated in-memory databases to mimic peers /
  // sequential attempts; that is intentional, so silence the multi-DB warning.
  setUpAll(() {
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(debugResetRemoteDeliveryDrainState);
  tearDown(debugResetRemoteDeliveryDrainState);

  // ------------------------------------------------------------------
  // Pure loop: ack-after-commit ordering
  // ------------------------------------------------------------------

  group('runRemoteDeliveryDrain — ack ordering', () {
    test(
      'ack fires for a chunk ONLY after that chunk applies (commits)',
      () async {
        final journal = _FakeJournal();
        journal.append(
          table: 'members',
          entityId: 'm1',
          isDelete: false,
          fieldName: 'name',
          encodedValue: '"Alice"',
        );

        // Record the call order: the apply must complete before the ack runs.
        final events = <String>[];

        final result = await runRemoteDeliveryDrain(
          take: journal.take,
          ack: (upToId) async {
            events.add('ack:$upToId');
            await journal.ack(upToId);
          },
          applyChanges: (deliveries) async {
            // Simulate a non-trivial commit window.
            await Future<void>.delayed(Duration.zero);
            events.add('apply:${deliveries.length}');
            return deliveries.length;
          },
          quarantineSpill: (_) async {},
        );

        expect(events, ['apply:1', 'ack:1']);
        expect(result.rowsApplied, 1);
        expect(result.chunksAcked, 1);
        expect(result.aborted, isFalse);
        // Journal emptied after ack.
        expect(journal.length, 0);
      },
    );

    test('empty journal acks nothing and reports zero applied', () async {
      final journal = _FakeJournal();
      var ackCalls = 0;
      final result = await runRemoteDeliveryDrain(
        take: journal.take,
        ack: (upToId) async => ackCalls++,
        applyChanges: (deliveries) async => deliveries.length,
        quarantineSpill: (_) async {},
      );
      expect(result.rowsApplied, 0);
      expect(result.chunksAcked, 0);
      expect(ackCalls, 0);
    });
  });

  // ------------------------------------------------------------------
  // Crash-window recovery: an aborted drain never loses rows;
  // un-acked rows survive and are re-drained on the next loop.
  // ------------------------------------------------------------------

  group('runRemoteDeliveryDrain — crash-window recovery', () {
    test('a drain aborted before ACK leaves journal rows for re-drain; the '
        're-drain applies them exactly-once-effectively', () async {
      final journal = _FakeJournal();
      for (var i = 0; i < 3; i++) {
        journal.append(
          table: 'members',
          entityId: 'm$i',
          isDelete: false,
          fieldName: 'name',
          encodedValue: '"M$i"',
        );
      }

      // First run: simulate process death AFTER the Drift commit but BEFORE
      // the ack by throwing inside the ack. The rows stay in the journal.
      final applied = <String>[];
      await expectLater(
        runRemoteDeliveryDrain(
          take: journal.take,
          ack: (_) async => throw StateError('killed before ack'),
          applyChanges: (deliveries) async {
            for (final d in deliveries) {
              applied.add(d.entityId);
            }
            return deliveries.length;
          },
          quarantineSpill: (_) async {},
        ),
        throwsA(isA<StateError>()),
      );
      // Apply ran but ack did not → rows still present (would re-deliver).
      expect(applied, ['m0', 'm1', 'm2']);
      expect(journal.length, 3, reason: 'un-acked rows must survive the crash');

      // Second run (process relaunch): the same rows are re-taken and applied
      // again, then acked. Re-apply is idempotent at the Drift layer (CRDT
      // upsert); here we just assert the rows are delivered again and cleared.
      final reapplied = <String>[];
      final result = await runRemoteDeliveryDrain(
        take: journal.take,
        ack: journal.ack,
        applyChanges: (deliveries) async {
          for (final d in deliveries) {
            reapplied.add(d.entityId);
          }
          return deliveries.length;
        },
        quarantineSpill: (_) async {},
      );
      expect(reapplied, ['m0', 'm1', 'm2']);
      expect(result.rowsApplied, 3);
      expect(journal.length, 0, reason: 'all rows acked after the re-drain');
    });

    test(
      'ack high-water tracks the last committed chunk across chunks',
      () async {
        final journal = _FakeJournal();
        for (var i = 0; i < 5; i++) {
          journal.append(
            table: 'members',
            entityId: 'm$i',
            isDelete: false,
            fieldName: 'name',
            encodedValue: '"M$i"',
          );
        }
        final ackedHighWater = <int>[];
        final result = await runRemoteDeliveryDrain(
          take: journal.take,
          ack: (upToId) async {
            ackedHighWater.add(upToId);
            await journal.ack(upToId);
          },
          applyChanges: (deliveries) async => deliveries.length,
          quarantineSpill: (_) async {},
          chunkSize: 2,
        );
        // 5 rows / chunk 2 → acks at 2, 4, 5.
        expect(ackedHighWater, [2, 4, 5]);
        expect(result.rowsApplied, 5);
        expect(result.chunksAcked, 3);
      },
    );
  });

  // ------------------------------------------------------------------
  // shouldAbort short-circuits the loop (revoked / disposed handle)
  // ------------------------------------------------------------------

  test(
    'shouldAbort=true before the loop applies nothing and reports aborted',
    () async {
      final journal = _FakeJournal();
      journal.append(
        table: 'members',
        entityId: 'm1',
        isDelete: false,
        fieldName: 'name',
        encodedValue: '"A"',
      );
      var applyCalls = 0;
      final result = await runRemoteDeliveryDrain(
        take: journal.take,
        ack: journal.ack,
        applyChanges: (deliveries) async {
          applyCalls++;
          return deliveries.length;
        },
        quarantineSpill: (_) async {},
        shouldAbort: () => true,
      );
      expect(applyCalls, 0);
      expect(result.aborted, isTrue);
      expect(
        journal.length,
        1,
        reason: 'aborted drain leaves the journal intact',
      );
    },
  );

  // ------------------------------------------------------------------
  // Over-cap spill: oldest rows route to quarantine (with payload), not
  // applied; the whole chunk is still acked so growth is bounded without
  // silent loss.
  // ------------------------------------------------------------------

  test(
    'over-cap spill rows quarantine (not apply) but the chunk still acks',
    () async {
      // cap=1 with 3 rows → 2 oldest spill, 1 newest applies.
      final journal = _FakeJournal(cap: 1);
      journal.append(
        table: 'members',
        entityId: 'old1',
        isDelete: false,
        fieldName: 'name',
        encodedValue: '"Old1"',
      );
      journal.append(
        table: 'members',
        entityId: 'old2',
        isDelete: false,
        fieldName: 'name',
        encodedValue: '"Old2"',
      );
      journal.append(
        table: 'members',
        entityId: 'new1',
        isDelete: false,
        fieldName: 'name',
        encodedValue: '"New1"',
      );

      final applied = <String>[];
      final spilled = <String>[];
      final result = await runRemoteDeliveryDrain(
        take: journal.take,
        ack: journal.ack,
        applyChanges: (deliveries) async {
          for (final d in deliveries) {
            applied.add(d.entityId);
          }
          return deliveries.length;
        },
        quarantineSpill: (spill) async {
          for (final d in spill) {
            spilled.add(d.entityId);
          }
        },
      );

      expect(applied, ['new1'], reason: 'only the in-cap newest row applies');
      expect(
        spilled,
        ['old1', 'old2'],
        reason: 'the 2 oldest over-cap rows route to quarantine, not apply',
      );
      expect(result.rowsApplied, 1);
      expect(result.rowsSpilled, 2);
      // Whole chunk acked despite the spill → no unbounded growth, no loss.
      expect(journal.length, 0);
    },
  );

  // ------------------------------------------------------------------
  // onProgress heartbeat (Finding A / blocker 1): the bootstrap path forwards
  // this to the strict-apply watchdog so a long large-system apply does not
  // collapse the 60s idle timeout into a 60s TOTAL cap.
  // ------------------------------------------------------------------

  test(
    'onProgress fires per chunk with the running applied/spilled totals',
    () async {
      final journal = _FakeJournal();
      for (var i = 0; i < 5; i++) {
        journal.append(
          table: 'members',
          entityId: 'm$i',
          isDelete: false,
          fieldName: 'name',
          encodedValue: '"M$i"',
        );
      }
      final progress = <List<int>>[];
      await runRemoteDeliveryDrain(
        take: journal.take,
        ack: journal.ack,
        applyChanges: (deliveries) async => deliveries.length,
        quarantineSpill: (_) async {},
        onProgress: (applied, spilled) => progress.add([applied, spilled]),
        chunkSize: 2,
      );
      // 5 rows / chunk 2 → 3 chunks → 3 heartbeats with monotonic running totals.
      expect(progress, [
        [2, 0],
        [4, 0],
        [5, 0],
      ]);
    },
  );

  test('DrainResult.touchedTables collects every applied table', () async {
    final journal = _FakeJournal();
    journal.append(
      table: 'members',
      entityId: 'm1',
      isDelete: false,
      fieldName: 'name',
      encodedValue: '"A"',
    );
    journal.append(
      table: 'media_attachments',
      entityId: 'a1',
      isDelete: false,
      fieldName: 'path',
      encodedValue: '"/x"',
    );
    final result = await runRemoteDeliveryDrain(
      take: journal.take,
      ack: journal.ack,
      applyChanges: (deliveries) async => deliveries.length,
      quarantineSpill: (_) async {},
    );
    expect(result.touchedTables, {'members', 'media_attachments'});
  });

  test('spilled-only rows are NOT counted in touchedTables', () async {
    // cap=0 → all rows spill, none apply → no table is "touched" (applied).
    final journal = _FakeJournal(cap: 0);
    journal.append(
      table: 'members',
      entityId: 'old1',
      isDelete: false,
      fieldName: 'name',
      encodedValue: '"Old"',
    );
    final result = await runRemoteDeliveryDrain(
      take: journal.take,
      ack: journal.ack,
      applyChanges: (deliveries) async => deliveries.length,
      quarantineSpill: (_) async {},
    );
    expect(result.rowsSpilled, 1);
    expect(result.rowsApplied, 0);
    expect(result.touchedTables, isEmpty);
  });

  // ------------------------------------------------------------------
  // Strict apply: a per-row apply failure rethrows
  // BEFORE the chunk is acked, so journal rows survive for a retry. Without
  // this the chunk would ack and the failed consumer row would be lost
  // permanently (the payload-bearing lane is not built in this step).
  // ------------------------------------------------------------------

  test('a throwing applyChanges leaves the chunk un-acked (rows survive)', () async {
    final journal = _FakeJournal();
    journal.append(
      table: 'members',
      entityId: 'm1',
      isDelete: false,
      fieldName: 'name',
      encodedValue: '"A"',
    );
    var ackCalls = 0;
    await expectLater(
      runRemoteDeliveryDrain(
        take: journal.take,
        ack: (upToId) async {
          ackCalls++;
          await journal.ack(upToId);
        },
        // Simulates a strict per-row apply failure surfacing out of the apply.
        applyChanges: (_) async => throw StateError('strict apply failed'),
        quarantineSpill: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(ackCalls, 0, reason: 'throw before ack → chunk not acked');
    expect(journal.length, 1, reason: 'the failed row survives for retry');
  });

  // ------------------------------------------------------------------
  // Integration: real Drift DB + adapter + fake journal. Verifies the
  // journal drains into Drift through the production apply pipeline, acks
  // after commit, and survives a simulated crash window (journal rows
  // present, Drift rows absent → re-drain materializes them).
  // ------------------------------------------------------------------

  group('drain into a real Drift DB', () {
    Future<int> applyVia(
      AppDatabase db,
      DriftSyncAdapter adapter,
      List<ConsumerDelivery> deliveries,
    ) {
      return applyConsumerDeliveries(db, adapter, deliveries);
    }

    test('journaled member rows materialize in Drift and the journal acks '
        'after commit', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db);

      final now = DateTime.utc(2026, 6, 10, 12).millisecondsSinceEpoch;
      final journal = _FakeJournal();
      // A member create carries the required NOT-NULL columns (name,
      // created_at) so a non-sparse insert succeeds.
      journal.append(
        table: 'members',
        entityId: 'mem-1',
        isDelete: false,
        fieldName: 'name',
        encodedValue: jsonEncode('Alice'),
      );
      journal.append(
        table: 'members',
        entityId: 'mem-1',
        isDelete: false,
        fieldName: 'created_at',
        encodedValue: jsonEncode(now),
      );

      adapter.beginSyncBatch();
      final result = await runRemoteDeliveryDrain(
        take: journal.take,
        ack: journal.ack,
        applyChanges: (deliveries) => applyVia(db, adapter.adapter, deliveries),
        quarantineSpill: (_) async {},
      );
      await adapter.completeSyncBatch();

      expect(result.rowsApplied, 1, reason: 'one coalesced member entity');
      final member = await (db.select(
        db.members,
      )..where((t) => t.id.equals('mem-1'))).getSingleOrNull();
      expect(member, isNotNull);
      expect(member!.name, 'Alice');
      expect(journal.length, 0, reason: 'acked after the Drift commit');
    });

    test('crash window: journal rows present, Drift row absent — a re-drain '
        'materializes the row without divergence', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db);
      final quarantine = SyncQuarantineService(db.syncQuarantineDao);

      final now = DateTime.utc(2026, 6, 10, 12).millisecondsSinceEpoch;
      final journal = _FakeJournal();
      journal.append(
        table: 'members',
        entityId: 'mem-crash',
        isDelete: false,
        fieldName: 'name',
        encodedValue: jsonEncode('Bob'),
      );
      journal.append(
        table: 'members',
        entityId: 'mem-crash',
        isDelete: false,
        fieldName: 'created_at',
        encodedValue: jsonEncode(now),
      );

      // First attempt simulates a kill BETWEEN the Drift apply and the ack:
      // apply runs (Drift row lands) but the ack throws. Production death
      // could happen the other way (before the Drift commit), which this
      // models as the "Drift absent, journal present" case below by NOT
      // applying. To exercise the harness-specified "journal rows present,
      // Drift rows absent" crash, fail the apply itself so Drift stays empty.
      adapter.beginSyncBatch();
      await expectLater(
        runRemoteDeliveryDrain(
          take: journal.take,
          ack: journal.ack,
          // Drift apply "killed" before any write commits.
          applyChanges: (_) async => throw StateError('killed mid-apply'),
          quarantineSpill: (spill) =>
              quarantineConsumerDeliverySpill(quarantine, spill),
        ),
        throwsA(isA<StateError>()),
      );
      await adapter.completeSyncBatch();

      // Drift row absent, journal rows present — the exact crash-window state.
      expect(
        await (db.select(
          db.members,
        )..where((t) => t.id.equals('mem-crash'))).getSingleOrNull(),
        isNull,
      );
      expect(journal.length, 2, reason: 'un-acked rows survive the crash');

      // Relaunch: re-drain succeeds and materializes the row.
      adapter.beginSyncBatch();
      final result = await runRemoteDeliveryDrain(
        take: journal.take,
        ack: journal.ack,
        applyChanges: (deliveries) => applyVia(db, adapter.adapter, deliveries),
        quarantineSpill: (spill) =>
            quarantineConsumerDeliverySpill(quarantine, spill),
      );
      await adapter.completeSyncBatch();

      expect(result.rowsApplied, 1);
      final member = await (db.select(
        db.members,
      )..where((t) => t.id.equals('mem-crash'))).getSingleOrNull();
      expect(member, isNotNull);
      expect(member!.name, 'Bob');
      expect(journal.length, 0);
    });

    test(
      'over-cap spill rows land in sync_quarantine with full payload',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final adapter = buildSyncAdapterWithCompletion(db);
        final quarantine = SyncQuarantineService(db.syncQuarantineDao);

        final now = DateTime.utc(2026, 6, 10, 12).millisecondsSinceEpoch;
        // cap=1, two distinct members → the older one spills.
        final journal = _FakeJournal(cap: 1);
        journal.append(
          table: 'members',
          entityId: 'spill-me',
          isDelete: false,
          fieldName: 'name',
          encodedValue: jsonEncode('Old'),
        );
        journal.append(
          table: 'members',
          entityId: 'keep-me',
          isDelete: false,
          fieldName: 'name',
          encodedValue: jsonEncode('New'),
        );
        journal.append(
          table: 'members',
          entityId: 'keep-me',
          isDelete: false,
          fieldName: 'created_at',
          encodedValue: jsonEncode(now),
        );

        adapter.beginSyncBatch();
        final result = await runRemoteDeliveryDrain(
          take: journal.take,
          ack: journal.ack,
          applyChanges: (deliveries) =>
              applyVia(db, adapter.adapter, deliveries),
          quarantineSpill: (spill) =>
              quarantineConsumerDeliverySpill(quarantine, spill),
        );
        await adapter.completeSyncBatch();

        expect(result.rowsSpilled, 1);
        final quarantined = await db.syncQuarantineDao.getAll();
        expect(quarantined, hasLength(1));
        final row = quarantined.single;
        expect(row.entityType, 'members');
        expect(row.entityId, 'spill-me');
        expect(row.receivedType, 'SpilledApply');
        // Full field payload is preserved for a later repair/replay pass. The
        // value is the decoded natural type, matching RemoteChanges/apply shape.
        final payload = jsonDecode(row.receivedValue!) as Map<String, dynamic>;
        expect(payload['name'], 'Old');
        // The journal was fully acked → bounded growth, no silent loss.
        expect(journal.length, 0);
      },
    );
  });

  // ------------------------------------------------------------------
  // drainRemoteDeliveries serialization: overlapping triggers (startup +
  // RemoteChanges + SyncCompleted + post-bootstrap) must coalesce onto one
  // in-flight drain, not run the journal concurrently.
  // ------------------------------------------------------------------
  group('drainRemoteDeliveries — serialization', () {
    const handle = _FakeHandle();
    final db = AppDatabase(NativeDatabase.memory());
    final adapter = buildSyncAdapterWithCompletion(db);
    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    tearDownAll(db.close);

    tearDown(() {
      debugDrainRemoteDeliveriesOverride = null;
      debugResetRemoteDeliveryDrainState();
    });

    test(
      'a trigger arriving mid-drain coalesces and re-checks once after',
      () async {
        var active = 0;
        var maxConcurrent = 0;
        var runs = 0;
        final firstStarted = Completer<void>();
        final release = Completer<void>();

        debugDrainRemoteDeliveriesOverride = (_) async {
          runs++;
          active++;
          maxConcurrent = active > maxConcurrent ? active : maxConcurrent;
          if (!firstStarted.isCompleted) {
            firstStarted.complete();
            // Hold the first run open so the second trigger lands mid-drain.
            await release.future;
          }
          active--;
          return const DrainResult(
            rowsApplied: 0,
            rowsSpilled: 0,
            chunksAcked: 0,
            aborted: false,
          );
        };

        final first = drainRemoteDeliveries(
          handle,
          db: db,
          syncAdapter: adapter,
          quarantine: quarantine,
        );
        await firstStarted.future;

        // Second trigger while the first is in flight — must NOT start a parallel
        // run; it chains onto the in-flight one and queues a trailing pass.
        final second = drainRemoteDeliveries(
          handle,
          db: db,
          syncAdapter: adapter,
          quarantine: quarantine,
        );

        release.complete();
        await Future.wait([first, second]);

        expect(maxConcurrent, 1, reason: 'drains never run concurrently');
        // First run + one trailing pass for the queued trigger = 2.
        expect(runs, 2);
      },
    );

    test(
      'the test override is invoked (FFI bypass) and its result returned',
      () async {
        debugDrainRemoteDeliveriesOverride = (_) async => const DrainResult(
          rowsApplied: 7,
          rowsSpilled: 0,
          chunksAcked: 1,
          aborted: false,
        );
        final result = await drainRemoteDeliveries(
          handle,
          db: db,
          syncAdapter: adapter,
          quarantine: quarantine,
        );
        expect(result.rowsApplied, 7);
      },
    );
  });

}

/// Minimal fake handle — `drainRemoteDeliveries` short-circuits to the override
/// before touching the handle, so it only needs to satisfy the type.
class _FakeHandle implements ffi.PrismSyncHandle {
  const _FakeHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
