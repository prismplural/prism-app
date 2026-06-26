import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/data/repositories/drift_app_preference_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/preferences/preference_codec.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';

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

  test(
    'getStored returns null for missing, deleted, and invalid rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = PreferenceValuesDao(db);
      final repo = DriftAppPreferenceRepository(dao, null);
      const preference = memberNamePresentationPreference;

      Future<void> seedRaw({
        required String valueType,
        required String? valueJson,
        bool isDeleted = false,
      }) {
        return dao.upsertAppValue(
          AppPreferenceValuesCompanion.insert(
            key: preference.key,
            valueType: valueType,
            valueJson: Value(valueJson),
            isDeleted: Value(isDeleted),
          ),
        );
      }

      expect(await repo.getStored(preference), isNull);

      await repo.set(preference, 'full_name_with_name');
      expect(await repo.getStored(preference), 'full_name_with_name');

      await repo.reset(preference);
      expect(await repo.getStored(preference), isNull);

      await seedRaw(valueType: 'bool', valueJson: '"name"');
      expect(await repo.getStored(preference), isNull);

      await seedRaw(
        valueType: preference.codec.valueType,
        valueJson: '"bogus"',
      );
      expect(await repo.getStored(preference), isNull);

      await seedRaw(valueType: preference.codec.valueType, valueJson: null);
      expect(await repo.getStored(preference), isNull);

      await seedRaw(
        valueType: preference.codec.valueType,
        valueJson: 'not json',
      );
      expect(await repo.getStored(preference), isNull);
    },
  );

  test('watchStored emits active values and null for tombstones', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftAppPreferenceRepository(PreferenceValuesDao(db), null);
    const preference = memberNamePresentationPreference;

    final expectedValues = expectLater(
      repo.watchStored(preference).take(3),
      emitsInOrder([isNull, 'full_name_with_name', isNull]),
    );

    await repo.set(preference, 'full_name_with_name');
    await repo.reset(preference);

    await expectedValues;
  });
}
