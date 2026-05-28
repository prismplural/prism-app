import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';

class _RecordingCustomFieldsDao extends CustomFieldsDao {
  _RecordingCustomFieldsDao(super.db);

  var bulkUpdateCalls = 0;
  var rowUpdateCalls = 0;

  @override
  Future<void> bulkUpdateDisplayOrders(Map<String, int> displayOrders) async {
    bulkUpdateCalls++;
    await super.bulkUpdateDisplayOrders(displayOrders);
  }

  @override
  Future<int> updateField(String id, db.CustomFieldsCompanion companion) {
    rowUpdateCalls++;
    return super.updateField(id, companion);
  }
}

void main() {
  test(
    'setValue updates the existing field/member row when stream is stale',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);
      const existing = CustomFieldValue(
        id: 'existing-value',
        customFieldId: 'field-1',
        memberId: 'member-1',
        value: 'old',
      );
      await repo.upsertValue(existing);
      final container = ProviderContainer(
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container
          .read(customFieldValueNotifierProvider.notifier)
          .setValue(
            customFieldId: 'field-1',
            memberId: 'member-1',
            value: 'new',
          );

      final values = await database.customFieldsDao.getAllValues();
      expect(values, hasLength(1));
      expect(values.single.id, 'existing-value');
      expect(values.single.value, 'new');
    },
  );

  test(
    'custom field notifier reorders via a bulk display-order update path',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final dao = _RecordingCustomFieldsDao(database);
      final repo = DriftCustomFieldsRepository(dao, null);

      CustomField field(String id, int order) => CustomField(
        id: id,
        name: id,
        fieldType: CustomFieldType.text,
        displayOrder: order,
        createdAt: DateTime(2024, 1, 1),
      );

      await repo.createField(field('a', 0));
      await repo.createField(field('b', 1));
      await repo.createField(field('c', 2));

      final container = ProviderContainer(
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final initial = await repo.watchAllFields().first;
      final reordered = [initial[2], initial[0], initial[1]];

      await container
          .read(customFieldNotifierProvider.notifier)
          .reorderFields(reordered);

      expect(dao.bulkUpdateCalls, 1);
      expect(dao.rowUpdateCalls, 0);

      final updated = await repo.watchAllFields().first;
      expect(updated.map((f) => f.id), ['c', 'a', 'b']);
      expect(updated.map((f) => f.displayOrder), [0, 1, 2]);
    },
  );
}
