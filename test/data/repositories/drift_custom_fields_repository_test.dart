import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;

class _RecordingCustomFieldsRepository extends DriftCustomFieldsRepository {
  _RecordingCustomFieldsRepository(CustomFieldsDao dao) : super(dao, null);

  final deletes = <({String table, String entityId})>[];

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    deletes.add((table: table, entityId: entityId));
  }
}

void main() {
  late db.AppDatabase database;
  late _RecordingCustomFieldsRepository repo;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = _RecordingCustomFieldsRepository(database.customFieldsDao);
  });

  tearDown(() async {
    await database.close();
  });

  test('deleteValuesForMember emits sync deletes for active values', () async {
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'value-1',
        customFieldId: 'field-1',
        memberId: 'member-1',
        value: 'one',
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'value-2',
        customFieldId: 'field-2',
        memberId: 'member-1',
        value: 'two',
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'other-member-value',
        customFieldId: 'field-1',
        memberId: 'member-2',
        value: 'other',
      ),
    );

    await repo.deleteValuesForMember('member-1');

    final activeValues = await database.customFieldsDao.getAllValues();
    expect(activeValues.map((value) => value.id), ['other-member-value']);
    expect(
      repo.deletes,
      unorderedEquals([
        (table: 'custom_field_values', entityId: 'value-1'),
        (table: 'custom_field_values', entityId: 'value-2'),
      ]),
    );
  });

  test('deleteValuesForField emits sync deletes for active values', () async {
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'value-1',
        customFieldId: 'field-1',
        memberId: 'member-1',
        value: 'one',
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'value-2',
        customFieldId: 'field-1',
        memberId: 'member-2',
        value: 'two',
      ),
    );
    await database.customFieldsDao.upsertValue(
      db.CustomFieldValuesCompanion.insert(
        id: 'other-field-value',
        customFieldId: 'field-2',
        memberId: 'member-1',
        value: 'other',
      ),
    );

    await repo.deleteValuesForField('field-1');

    final activeValues = await database.customFieldsDao.getAllValues();
    expect(activeValues.map((value) => value.id), ['other-field-value']);
    expect(
      repo.deletes,
      unorderedEquals([
        (table: 'custom_field_values', entityId: 'value-1'),
        (table: 'custom_field_values', entityId: 'value-2'),
      ]),
    );
  });

  group('updateField (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    domain.CustomField makeField({
      String id = 'f1',
      String name = 'Original name',
      domain.CustomFieldType fieldType = domain.CustomFieldType.text,
      domain.DatePrecision? datePrecision,
      int displayOrder = 0,
      DateTime? createdAt,
    }) {
      return domain.CustomField(
        id: id,
        name: name,
        fieldType: fieldType,
        datePrecision: datePrecision,
        displayOrder: displayOrder,
        createdAt: createdAt ?? baseTime,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createField(makeField());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateField(makeField(name: 'Updated name'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'custom_fields');
      expect(captured.single.entityId, 'f1');
      expect(captured.single.fields.keys.toSet(), {'name'});
      expect(captured.single.fields['name'], 'Updated name');
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test('emits nothing when domain matches stored row', () async {
      await repo.createField(makeField());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateField(makeField());

      expect(captured, isEmpty);
    });

    test('preserves untouched columns in the database', () async {
      await repo.createField(
        makeField(
          name: 'Birthday',
          fieldType: domain.CustomFieldType.date,
          datePrecision: domain.DatePrecision.monthDay,
          displayOrder: 3,
        ),
      );

      await repo.updateField(
        makeField(
          name: 'Birthday renamed',
          fieldType: domain.CustomFieldType.date,
          datePrecision: domain.DatePrecision.monthDay,
          displayOrder: 3,
        ),
      );

      final row = await database.customFieldsDao.getFieldById('f1');
      expect(row, isNotNull);
      expect(row!.name, 'Birthday renamed');
      expect(row.fieldType, domain.CustomFieldType.date.index);
      expect(row.datePrecision, domain.DatePrecision.monthDay.index);
      expect(row.displayOrder, 3);
    });

    test('null-clearing emits the null patch (datePrecision: value → null)',
        () async {
      await repo.createField(
        makeField(
          fieldType: domain.CustomFieldType.date,
          datePrecision: domain.DatePrecision.full,
        ),
      );
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateField(
        makeField(fieldType: domain.CustomFieldType.date),
      );

      expect(captured, hasLength(1));
      final patch = captured.single.fields;
      expect(patch.containsKey('date_precision'), isTrue);
      expect(patch['date_precision'], isNull);

      final row = await database.customFieldsDao.getFieldById('f1');
      expect(row!.datePrecision, isNull);
    });

    test('silently no-ops on a tombstoned row', () async {
      await repo.createField(makeField());
      await repo.deleteField('f1');
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateField(makeField(name: 'Attempted resurrection'));

      expect(captured, isEmpty);
    });

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateField(makeField(id: 'missing'));

      expect(captured, isEmpty);
      final row = await database.customFieldsDao.getFieldById('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      await repo.createField(makeField());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Change something to force an emission so we can inspect its keys.
      await repo.updateField(makeField(name: 'Another name'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test('reorderFields still emits one display_order patch per changed field',
        () async {
      await repo.createField(makeField(id: 'a', displayOrder: 0));
      await repo.createField(makeField(id: 'b', displayOrder: 1));
      await repo.createField(makeField(id: 'c', displayOrder: 2));

      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Reorder: c, a, b (positions 0, 1, 2). All three change order.
      await repo.reorderFields([
        makeField(id: 'c', displayOrder: 2),
        makeField(id: 'a', displayOrder: 0),
        makeField(id: 'b', displayOrder: 1),
      ]);

      expect(captured, hasLength(3));
      for (final op in captured) {
        expect(op.opType, SyncRecordOpType.update);
        expect(op.table, 'custom_fields');
        expect(op.fields.keys.toSet(), {'display_order'});
      }
      final emittedByEntity = {
        for (final op in captured) op.entityId: op.fields['display_order'],
      };
      expect(emittedByEntity, {'c': 0, 'a': 1, 'b': 2});
    });
  });
}
