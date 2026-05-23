import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/data/repositories/drift_app_preference_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/preferences/preference_codec.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';

const _density = PreferenceDefinition<String>(
  key: 'appearance.sidebar_density',
  scope: PreferenceScope.appSynced,
  defaultValue: 'comfortable',
  codec: StringPreferenceCodec(allowedValues: {'compact', 'comfortable'}),
  introducedInAppVersion: '0.0.0-test',
  introducedInSchemaVersion: 27,
);

void main() {
  test('set, reset, and set again clears tombstone', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftAppPreferenceRepository(PreferenceValuesDao(db), null);

    await repo.set(_density, 'compact');
    expect(await repo.get(_density), 'compact');

    await repo.reset(_density);
    expect(await repo.get(_density), 'comfortable');

    await repo.set(_density, 'compact');
    expect(await repo.get(_density), 'compact');

    final row = await PreferenceValuesDao(db).getAppValue(_density.key);
    expect(row, isNotNull);
    expect(row!.isDeleted, isFalse);
    expect(row.valueJson, '"compact"');
  });

  test('invalid values throw and do not write', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftAppPreferenceRepository(PreferenceValuesDao(db), null);

    await expectLater(
      repo.set(_density, 'tiny'),
      throwsA(isA<PreferenceValidationException>()),
    );
    expect(await PreferenceValuesDao(db).getAppValue(_density.key), isNull);
  });

  test('emits create, delete, create when setting after reset', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftAppPreferenceRepository(PreferenceValuesDao(db), null);
    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.set(_density, 'compact');
    await repo.reset(_density);
    await repo.set(_density, 'comfortable');

    expect(captured.map((op) => op.opType).toList(), [
      SyncRecordOpType.create,
      SyncRecordOpType.delete,
      SyncRecordOpType.create,
    ]);
    expect(captured.first.table, 'app_preference_values');
    expect(captured.first.entityId, _density.key);
    expect(captured.first.fields['is_deleted'], isFalse);
    expect(captured.last.fields['is_deleted'], isFalse);
  });

  test('active updates do not emit isDeleted as a field update', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftAppPreferenceRepository(PreferenceValuesDao(db), null);
    final captured = <CapturedSyncOp>[];
    SyncRecordMixin.installCaptureSinkForTesting(captured.add);
    addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

    await repo.set(_density, 'compact');
    await repo.set(_density, 'comfortable');

    expect(captured.map((op) => op.opType).toList(), [
      SyncRecordOpType.create,
      SyncRecordOpType.update,
    ]);
    expect(captured.last.fields, {'value_json': '"comfortable"'});
  });
}
