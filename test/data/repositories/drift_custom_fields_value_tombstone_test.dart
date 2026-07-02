// Regression contract for the custom-field VALUE burned-id data-loss.
//
// A value row id is the deterministic UUIDv5 of (field, member), and the sync
// engine's `is_deleted` is absorbing fleet-wide. Clearing a field tombstones
// that id; a naive refill wrote user text back into the tombstoned row, which
// stays invisible to every (isDeleted=false) read AND can never propagate (the
// id is burned network-wide). The fix mints a FRESH row on refill and emits the
// create against the minted id. These tests fail on the pre-fix behavior and
// pass with the fix.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;

void main() {
  late db.AppDatabase database;
  late DriftCustomFieldsRepository repo;

  const fieldId = 'field-1';
  const memberId = 'member-1';
  final deterministicId = deriveCustomFieldValueId(
    customFieldId: fieldId,
    memberId: memberId,
  );

  domain.CustomFieldValue value(String v) => domain.CustomFieldValue(
    id: deterministicId,
    customFieldId: fieldId,
    memberId: memberId,
    value: v,
  );

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = DriftCustomFieldsRepository(database.customFieldsDao, null);
  });

  tearDown(() async {
    await database.close();
  });

  test('fill → clear → refill: value is visible again and the new create op '
      'targets a fresh id, not the burned deterministic id', () async {
    await repo.upsertValue(value('first'));
    // Clear via the repo tombstone path (what the widget does on empty).
    await repo.deleteValue(deterministicId);
    expect(await repo.getValueForField(fieldId, memberId), isNull);

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.upsertValue(value('refilled'));

    // Visible again via both read paths.
    final read = await repo.getValueForField(fieldId, memberId);
    expect(read, isNotNull);
    expect(read!.value, 'refilled');
    final watched = await repo.watchValuesForMember(memberId).first;
    expect(watched.map((v) => v.value), ['refilled']);

    // The refill emitted a create against a MINTED id, not the burned one.
    final create = captured.singleWhere(
      (op) => op.opType == SyncRecordOpType.create,
    );
    expect(create.table, 'custom_field_values');
    expect(create.entityId, isNot(deterministicId));
    expect(read.id, create.entityId);
    // The burned row is still tombstoned on disk (not resurrected).
    final burned = await (database.select(
      database.customFieldValues,
    )..where((v) => v.id.equals(deterministicId))).getSingle();
    expect(burned.isDeleted, isTrue);
  });

  test('refill after clear twice: second clear tombstones the minted id, '
      'a third fill still works', () async {
    await repo.upsertValue(value('first'));
    await repo.deleteValue(deterministicId);
    await repo.upsertValue(value('second'));

    final mintedId = (await repo.getValueForField(fieldId, memberId))!.id;
    expect(mintedId, isNot(deterministicId));

    // Clear the MINTED id this time.
    await repo.deleteValue(mintedId);
    expect(await repo.getValueForField(fieldId, memberId), isNull);

    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.upsertValue(value('third'));

    final read = await repo.getValueForField(fieldId, memberId);
    expect(read, isNotNull);
    expect(read!.value, 'third');
    final create = captured.singleWhere(
      (op) => op.opType == SyncRecordOpType.create,
    );
    // A fresh id again — neither the deterministic nor the previously minted id.
    expect(create.entityId, isNot(deterministicId));
    expect(create.entityId, isNot(mintedId));
    expect(read.id, create.entityId);
  });

  test('legitimate clear still soft-deletes and emits a delete for the active '
      'row id — deterministic on first fill, minted after a refill', () async {
    // First-fill clear emits the deterministic id.
    await repo.upsertValue(value('first'));
    final firstDeletes = <String>[];
    SyncRecordMixin.installCaptureSinkForTesting((op) {
      if (op.opType == SyncRecordOpType.delete) firstDeletes.add(op.entityId);
    });
    await repo.deleteValue(deterministicId);
    SyncRecordMixin.removeCaptureSinkForTesting();
    expect(firstDeletes, [deterministicId]);

    // Refill mints, then clearing the active (minted) row emits the minted id.
    await repo.upsertValue(value('second'));
    final mintedId = (await repo.getValueForField(fieldId, memberId))!.id;
    final secondDeletes = <String>[];
    SyncRecordMixin.installCaptureSinkForTesting((op) {
      if (op.opType == SyncRecordOpType.delete) secondDeletes.add(op.entityId);
    });
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);
    await repo.deleteValue(mintedId);
    expect(secondDeletes, [mintedId]);
    expect(await repo.getValueForField(fieldId, memberId), isNull);
  });

  test(
    'first-ever fill keeps the deterministic id (cross-device dedup)',
    () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.upsertValue(value('first'));

      final read = await repo.getValueForField(fieldId, memberId);
      expect(read!.id, deterministicId);
      final create = captured.singleWhere(
        (op) => op.opType == SyncRecordOpType.create,
      );
      expect(create.entityId, deterministicId);
    },
  );
}
