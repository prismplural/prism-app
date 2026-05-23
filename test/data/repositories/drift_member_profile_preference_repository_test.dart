import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_profile_preference_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/preferences/preference_codec.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';

const _headerVisible = PreferenceDefinition<bool>(
  key: 'profile.header_visible',
  scope: PreferenceScope.memberProfileSynced,
  defaultValue: true,
  codec: BoolPreferenceCodec(),
  introducedInAppVersion: '0.0.0-test',
  introducedInSchemaVersion: 27,
);

void main() {
  test('member profile preferences require an existing member', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftMemberProfilePreferenceRepository(
      PreferenceValuesDao(db),
      null,
    );

    await expectLater(
      repo.set('missing', _headerVisible, false),
      throwsA(isA<StateError>()),
    );
  });

  test('set, reset, and set again clears tombstone', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'm1',
            name: 'Sky',
            createdAt: DateTime.utc(2026),
            emoji: const Value('✨'),
          ),
        );
    final dao = PreferenceValuesDao(db);
    final repo = DriftMemberProfilePreferenceRepository(dao, null);

    await repo.set('m1', _headerVisible, false);
    expect(await repo.get('m1', _headerVisible), isFalse);

    await repo.reset('m1', _headerVisible);
    expect(await repo.get('m1', _headerVisible), isTrue);

    await repo.set('m1', _headerVisible, false);
    expect(await repo.get('m1', _headerVisible), isFalse);

    final rows = await dao.allMemberProfileValuesForMember('m1');
    expect(rows, hasLength(1));
    expect(rows.single.isDeleted, isFalse);
  });

  test('emits create, delete, create when setting after reset', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'm1',
            name: 'Sky',
            createdAt: DateTime.utc(2026),
          ),
        );
    final repo = DriftMemberProfilePreferenceRepository(
      PreferenceValuesDao(db),
      null,
    );
    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.set('m1', _headerVisible, false);
    await repo.reset('m1', _headerVisible);
    await repo.set('m1', _headerVisible, false);

    expect(captured.map((op) => op.opType).toList(), [
      SyncRecordOpType.create,
      SyncRecordOpType.delete,
      SyncRecordOpType.create,
    ]);
    expect(captured.first.table, 'member_profile_preference_values');
    expect(captured.first.fields['is_deleted'], isFalse);
    expect(captured.last.fields['is_deleted'], isFalse);
  });

  test('active updates do not emit isDeleted as a field update', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'm1',
            name: 'Sky',
            createdAt: DateTime.utc(2026),
          ),
        );
    final repo = DriftMemberProfilePreferenceRepository(
      PreferenceValuesDao(db),
      null,
    );
    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.set('m1', _headerVisible, false);
    await repo.set('m1', _headerVisible, true);

    expect(captured.map((op) => op.opType).toList(), [
      SyncRecordOpType.create,
      SyncRecordOpType.update,
    ]);
    expect(captured.last.fields, {'value_json': 'true'});
  });

  test('resetAllForMember tombstones rows and clears stored values', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'm1',
            name: 'Sky',
            createdAt: DateTime.utc(2026),
          ),
        );
    final dao = PreferenceValuesDao(db);
    final repo = DriftMemberProfilePreferenceRepository(dao, null);

    await repo.set('m1', _headerVisible, false);
    await repo.resetAllForMember('m1');

    final rows = await dao.allMemberProfileValuesForMember('m1');
    expect(rows, hasLength(1));
    expect(rows.single.isDeleted, isTrue);
    expect(rows.single.valueJson, null);
  });
}
