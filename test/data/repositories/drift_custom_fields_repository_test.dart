import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';

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
}
