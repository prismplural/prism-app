import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

/// F23 EMITTER FAN-OUT: deleting a member that other devices know by additional
/// legacy entity ids (recorded in pk_identity_sync_aliases) must emit a delete
/// for the row id AND each legacy alias id, skipping any alias id that is an
/// active local row.
void main() {
  late AppDatabase db;
  late MembersDao dao;
  late DriftMemberRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.membersDao;
    repo = DriftMemberRepository(dao, null);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertMember(
    String id, {
    String? pkUuid,
    String? pkId,
  }) {
    return dao.insertMember(
      MembersCompanion.insert(
        id: id,
        name: 'M-$id',
        createdAt: DateTime.utc(2026, 6),
        pluralkitUuid: Value(pkUuid),
        pluralkitId: Value(pkId),
      ),
    );
  }

  test('deleteMember emits delete for the row id and each recorded alias id',
      () async {
    await insertMember('rowY', pkUuid: 'U', pkId: 'abcde');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'alias-1',
      pkUuid: 'U',
      pkId: 'abcde',
      targetRowId: 'rowY',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'alias-2',
      pkUuid: 'U',
      pkId: 'abcde',
      targetRowId: 'rowY',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.deleteMember('rowY');

    final deletes = captured
        .where(
          (op) =>
              op.table == 'members' && op.opType == SyncRecordOpType.delete,
        )
        .map((op) => op.entityId)
        .toList();
    expect(deletes, containsAll(<String>['rowY', 'alias-1', 'alias-2']));
    expect(deletes, hasLength(3));
  });

  test('deleteMember skips an alias id that is an active local row', () async {
    await insertMember('rowY', pkUuid: 'U', pkId: 'abcde');
    // alias-active is itself an active local member row — fanning a delete out
    // for it would hard-delete a live row, so it must be skipped.
    await insertMember('alias-active', pkUuid: 'U2');
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'alias-active',
      pkUuid: 'U',
      pkId: 'abcde',
      targetRowId: 'rowY',
    );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'alias-loser',
      pkUuid: 'U',
      pkId: 'abcde',
      targetRowId: 'rowY',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.deleteMember('rowY');

    final deletes = captured
        .where(
          (op) =>
              op.table == 'members' && op.opType == SyncRecordOpType.delete,
        )
        .map((op) => op.entityId)
        .toList();
    expect(deletes, containsAll(<String>['rowY', 'alias-loser']));
    expect(deletes, isNot(contains('alias-active')));
    expect(deletes, hasLength(2));
  });

  test('deleteMember of a member with no PK identity emits only the row delete',
      () async {
    await insertMember('rowZ');
    // A stray alias keyed on a different identity must not be fanned out.
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'unrelated',
      pkUuid: 'OTHER',
      targetRowId: 'somewhere',
    );

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.deleteMember('rowZ');

    final deletes = captured
        .where(
          (op) =>
              op.table == 'members' && op.opType == SyncRecordOpType.delete,
        )
        .map((op) => op.entityId)
        .toList();
    expect(deletes, <String>['rowZ']);
  });
}
