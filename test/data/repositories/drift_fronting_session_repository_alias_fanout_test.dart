import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// F23 EMITTER FAN-OUT (fronting_sessions): deleting a session that other
/// devices know by additional legacy entity ids must emit a delete for the row
/// id AND each recorded alias id; importer-artifact tombstones (which clear the
/// PK link before deleting) must fan out NOTHING.
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

  Future<void> insertSession(
    String id, {
    String? pkUuid,
    String memberId = 'm1',
  }) {
    return dao.insertSession(
      FrontingSessionsCompanion.insert(
        id: id,
        startTime: DateTime.utc(2026, 6, 1, 8),
        memberId: Value(memberId),
        pluralkitUuid: Value(pkUuid),
      ),
    );
  }

  List<String> deletesFrom(List<CapturedSyncOp> captured) => captured
      .where(
        (op) =>
            op.table == 'fronting_sessions' &&
            op.opType == SyncRecordOpType.delete,
      )
      .map((op) => op.entityId)
      .toList();

  test('deleteSession emits delete for the row id and each recorded alias id',
      () async {
    await insertSession('rowY', pkUuid: 'SW');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'fronting_sessions',
      legacyEntityId: 'alias-1',
      pkUuid: 'SW',
      memberId: 'm1',
      targetRowId: 'rowY',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'fronting_sessions',
      legacyEntityId: 'alias-2',
      pkUuid: 'SW',
      memberId: 'm1',
      targetRowId: 'rowY',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.deleteSession('rowY');

    final deletes = deletesFrom(captured);
    expect(deletes, containsAll(<String>['rowY', 'alias-1', 'alias-2']));
    expect(deletes, hasLength(3));
  });

  test('deleteSession skips an alias id that is an active local row', () async {
    await insertSession('rowY', pkUuid: 'SW');
    await insertSession('alias-active', pkUuid: 'SW2');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'fronting_sessions',
      legacyEntityId: 'alias-active',
      pkUuid: 'SW',
      memberId: 'm1',
      targetRowId: 'rowY',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'fronting_sessions',
      legacyEntityId: 'alias-loser',
      pkUuid: 'SW',
      memberId: 'm1',
      targetRowId: 'rowY',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.deleteSession('rowY');

    final deletes = deletesFrom(captured);
    expect(deletes, containsAll(<String>['rowY', 'alias-loser']));
    expect(deletes, isNot(contains('alias-active')));
    expect(deletes, hasLength(2));
  });

  test('importer-artifact tombstone (link cleared before delete) fans out '
      'no alias deletes', () async {
    await insertSession('rowY', pkUuid: 'SW');
    // An alias is recorded for this session's identity, but the importer clears
    // the PK link first — by the time deleteSession runs the row carries no
    // uuid, so the identity query comes up empty and nothing is fanned out.
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'fronting_sessions',
      legacyEntityId: 'alias-1',
      pkUuid: 'SW',
      memberId: 'm1',
      targetRowId: 'rowY',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    // Mirror _tombstoneImporterArtifact: clearPluralKitLink then deleteSession.
    await repo.clearPluralKitLink('rowY');
    await repo.deleteSession('rowY');

    final deletes = deletesFrom(captured);
    expect(deletes, <String>['rowY'], reason: 'no alias fan-out for artifact');
  });

  test('deleteSession of a session with no PK link emits only the row delete',
      () async {
    await insertSession('rowZ');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'fronting_sessions',
      legacyEntityId: 'unrelated',
      pkUuid: 'OTHER',
      memberId: 'm9',
      targetRowId: 'somewhere',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.deleteSession('rowZ');

    expect(deletesFrom(captured), <String>['rowZ']);
  });
}
