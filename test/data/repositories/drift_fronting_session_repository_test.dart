// test/data/repositories/drift_fronting_session_repository_test.dart
//
// Patch-style emission for `updateSession` and `endSession` (item #9 of
// the drift-repo migration plan, /Users/sky/code/prism-workspace/docs/
// plans/2026-05-25-drift-repo-patch-update-migration.md). Asserts that:
//
// - `updateSession` emits only the columns whose values actually changed,
//   no-ops on identical input, refuses tombstoned/missing rows, and never
//   emits `is_deleted` through the diff path.
// - `endSession` reads the row BEFORE the DAO write so the diff sees
//   pre-end state — closes the read-after-write trap from the prior
//   implementation that refetched after writing and over-emitted columns
//   it never touched.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

void main() {
  late AppDatabase db;
  late FrontingSessionsDao dao;
  late DriftFrontingSessionRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = FrontingSessionsDao(db);
    repo = DriftFrontingSessionRepository(dao, null);
  });

  tearDown(() => db.close());

  final baseStart = DateTime.utc(2026, 5, 1, 12);

  domain.FrontingSession makeSession({
    String id = 's1',
    DateTime? startTime,
    DateTime? endTime,
    String? memberId = 'm1',
    String? notes,
    domain.FrontConfidence? confidence,
    String? pluralkitUuid,
    String? pkImportSource,
    String? pkFileSwitchId,
    domain.SessionType sessionType = domain.SessionType.normal,
    domain.SleepQuality? quality,
    bool isHealthKitImport = false,
    bool isDeleted = false,
  }) {
    return domain.FrontingSession(
      id: id,
      startTime: startTime ?? baseStart,
      endTime: endTime,
      memberId: memberId,
      notes: notes,
      confidence: confidence,
      pluralkitUuid: pluralkitUuid,
      pkImportSource: pkImportSource,
      pkFileSwitchId: pkFileSwitchId,
      sessionType: sessionType,
      quality: quality,
      isHealthKitImport: isHealthKitImport,
      isDeleted: isDeleted,
    );
  }

  group('updateSession (patch-style emission)', () {
    test('emits only the changed fields', () async {
      await repo.createSession(makeSession(notes: 'before'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSession(makeSession(notes: 'after'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'fronting_sessions');
      expect(captured.single.entityId, 's1');
      expect(captured.single.fields.keys.toSet(), {'notes'});
      expect(captured.single.fields['notes'], 'after');
    });

    test('emits nothing when the domain object matches the stored row',
        () async {
      await repo.createSession(makeSession(notes: 'same'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSession(makeSession(notes: 'same'));

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.createSession(
        makeSession(
          notes: 'hello',
          memberId: 'm1',
          confidence: domain.FrontConfidence.strong,
          pluralkitUuid: 'uuid-1',
        ),
      );

      await repo.updateSession(
        makeSession(
          notes: 'hello updated',
          memberId: 'm1',
          confidence: domain.FrontConfidence.strong,
          pluralkitUuid: 'uuid-1',
        ),
      );

      final row = await dao.getSessionById('s1');
      expect(row, isNotNull);
      expect(row!.notes, 'hello updated');
      expect(row.memberId, 'm1');
      expect(row.confidence, domain.FrontConfidence.strong.index);
      expect(row.pluralkitUuid, 'uuid-1');
    });

    test('null-clearing emits the null and writes it to the database',
        () async {
      await repo.createSession(makeSession(notes: 'had notes'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSession(makeSession(notes: null));

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('notes'), isTrue);
      expect(patch['notes'], isNull);

      final row = await dao.getSessionById('s1');
      expect(row!.notes, isNull);
    });

    test(
      'silently no-ops on a tombstoned session (does not emit, '
      'does not resurrect)',
      () async {
        await repo.createSession(makeSession(notes: 'original'));
        await repo.deleteSession('s1');
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateSession(makeSession(notes: 'attempted edit'));

        expect(captured, isEmpty);
        final row = await dao.getSessionById('s1');
        expect(row, isNotNull);
        expect(row!.isDeleted, isTrue);
        expect(row.notes, 'original');
      },
    );

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSession(makeSession(id: 'missing'));

      expect(captured, isEmpty);
      final row = await dao.getSessionById('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      // Even if the domain object reports isDeleted: false (default), the
      // diff helper strips is_deleted unconditionally. The early-return
      // guards an isDeleted: true edge separately. Pin the strip behavior.
      await repo.createSession(makeSession(notes: 'a'));
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateSession(makeSession(notes: 'b'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });

  group('endSession (patch-style emission)', () {
    test('emits only the end-related fields', () async {
      // Create an active session, then end it; the only change should be
      // end_time.
      await repo.createSession(
        makeSession(notes: 'still going', memberId: 'm1'),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final endTime = baseStart.add(const Duration(hours: 2));
      await repo.endSession('s1', endTime);

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'fronting_sessions');
      expect(captured.single.entityId, 's1');
      expect(captured.single.fields.keys.toSet(), {'end_time'});
      expect(
        captured.single.fields['end_time'],
        endTime.toUtc().toIso8601String(),
      );
      // Read-after-write trap regression guard: the prior implementation
      // refetched and re-emitted every column. Pin that none of the
      // unchanged columns leak into the patch.
      expect(captured.single.fields.containsKey('notes'), isFalse);
      expect(captured.single.fields.containsKey('member_id'), isFalse);
      expect(captured.single.fields.containsKey('start_time'), isFalse);
    });

    test(
      'reads pre-write state (no read-after-write trap) — unrelated '
      'columns are NOT in the patch even when they hold non-default values',
      () async {
        // Seed the row with a rich set of non-default values that
        // endSession does not touch. If the implementation refetched
        // *after* the DAO write and diffed against a freshly-derived
        // _sessionFields(domain) round-trip, these columns might still
        // diff false-positive (e.g. enum index round-trip, UTC string
        // round-trip). Pin that they don't.
        await db
            .into(db.frontingSessions)
            .insert(
              FrontingSessionsCompanion.insert(
                id: 's-end-pre-write',
                sessionType: const Value(0),
                startTime: baseStart,
                memberId: const Value('m1'),
                notes: const Value('lots of notes'),
                confidence: Value(domain.FrontConfidence.certain.index),
                pluralkitUuid: const Value('pk-uuid-xyz'),
                pkImportSource: const Value('pk-source'),
                pkFileSwitchId: const Value('pk-switch-id'),
                isHealthKitImport: const Value(true),
              ),
            );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        final endTime = baseStart.add(const Duration(hours: 3));
        await repo.endSession('s-end-pre-write', endTime);

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.keys.toSet(), {'end_time'});
        // Explicit pins on the columns the old code would have re-emitted.
        expect(patch.containsKey('notes'), isFalse);
        expect(patch.containsKey('member_id'), isFalse);
        expect(patch.containsKey('confidence'), isFalse);
        expect(patch.containsKey('pluralkit_uuid'), isFalse);
        expect(patch.containsKey('pk_import_source'), isFalse);
        expect(patch.containsKey('pk_file_switch_id'), isFalse);
        expect(patch.containsKey('is_health_kit_import'), isFalse);
        expect(patch.containsKey('session_type'), isFalse);
        expect(patch.containsKey('start_time'), isFalse);
        expect(patch.containsKey('is_deleted'), isFalse);

        // And the DB still carries those other columns after the write.
        final row = await dao.getSessionById('s-end-pre-write');
        expect(row, isNotNull);
        // Drift stores DateTime as Unix seconds and reads back as local;
        // compare absolute moments.
        expect(row!.endTime!.toUtc(), endTime.toUtc());
        expect(row.notes, 'lots of notes');
        expect(row.memberId, 'm1');
        expect(row.confidence, domain.FrontConfidence.certain.index);
        expect(row.pluralkitUuid, 'pk-uuid-xyz');
        expect(row.isHealthKitImport, isTrue);
      },
    );
  });
}
