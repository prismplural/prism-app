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
    'setValue updates the existing field/member row in place when the stream '
    'is stale (active logical row wins over the derived id)',
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

      // The active logical row is updated in place — never re-homed onto the
      // derived id (which may be a burned tombstone). Still exactly one row, no
      // tombstone churn.
      final values = await database.customFieldsDao.getAllValues();
      expect(values, hasLength(1));
      expect(values.single.id, 'existing-value');
      expect(values.single.value, 'new');

      final rawRows = await database.select(database.customFieldValues).get();
      expect(rawRows, hasLength(1));
      expect(rawRows.single.id, 'existing-value');
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

  test(
    'custom field stream uses creation time to break duplicate order ties',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);

      CustomField field(
        String id, {
        required DateTime createdAt,
        String? parentFieldId,
        String fieldTypeId = 'text',
      }) => CustomField(
        id: id,
        name: id,
        fieldType: CustomFieldType.text,
        displayOrder: 0,
        createdAt: createdAt,
        fieldTypeId: fieldTypeId,
        parentFieldId: parentFieldId,
      );

      await repo.createField(
        field(
          'group-a',
          createdAt: DateTime.utc(2026, 5, 31, 12),
          fieldTypeId: 'group',
        ),
      );
      // Simulate legacy duplicate display_order rows replayed out of order.
      await repo.createField(
        field(
          'child-fourth',
          createdAt: DateTime.utc(2026, 5, 31, 12, 4),
          parentFieldId: 'group-a',
        ),
      );
      await repo.createField(
        field(
          'child-first',
          createdAt: DateTime.utc(2026, 5, 31, 12, 1),
          parentFieldId: 'group-a',
        ),
      );
      await repo.createField(
        field(
          'child-second',
          createdAt: DateTime.utc(2026, 5, 31, 12, 2),
          parentFieldId: 'group-a',
        ),
      );
      await repo.createField(
        field(
          'child-third',
          createdAt: DateTime.utc(2026, 5, 31, 12, 3),
          parentFieldId: 'group-a',
        ),
      );

      final fields = await repo.watchAllFields().first;
      final childIds = fields
          .where((field) => field.parentFieldId == 'group-a')
          .map((field) => field.id);

      expect(childIds, [
        'child-first',
        'child-second',
        'child-third',
        'child-fourth',
      ]);
    },
  );

  test(
    'custom field notifier appends a new child within its parent order scope',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);

      CustomField field(
        String id,
        int order, {
        String? parentFieldId,
        String fieldTypeId = 'text',
      }) => CustomField(
        id: id,
        name: id,
        fieldType: CustomFieldType.text,
        displayOrder: order,
        createdAt: DateTime(2024, 1, 1),
        fieldTypeId: fieldTypeId,
        parentFieldId: parentFieldId,
      );

      await repo.createField(field('top-level', 40));
      await repo.createField(field('group', 0, fieldTypeId: 'group'));
      await repo.createField(field('child-a', 0, parentFieldId: 'group'));
      await repo.createField(field('child-b', 1, parentFieldId: 'group'));

      final container = ProviderContainer(
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final failure = await container
          .read(customFieldNotifierProvider.notifier)
          .createField(
            name: 'New child',
            fieldType: CustomFieldType.text,
            fieldTypeId: 'text',
            parentFieldId: 'group',
          );

      expect(failure, isNull);

      final created = (await repo.getAllFields()).singleWhere(
        (field) => field.name == 'New child',
      );
      expect(created.parentFieldId, 'group');
      expect(created.displayOrder, 2);
    },
  );

  test(
    'custom field notifier appends a new top-level field within the top-level scope',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);

      CustomField field(
        String id,
        int order, {
        String? parentFieldId,
        String fieldTypeId = 'text',
      }) => CustomField(
        id: id,
        name: id,
        fieldType: CustomFieldType.text,
        displayOrder: order,
        createdAt: DateTime(2024, 1, 1),
        fieldTypeId: fieldTypeId,
        parentFieldId: parentFieldId,
      );

      await repo.createField(field('roles', 0));
      await repo.createField(field('layer', 1));
      await repo.createField(field('note', 40));
      await repo.createField(field('group', 2, fieldTypeId: 'group'));
      await repo.createField(field('child-a', 0, parentFieldId: 'group'));
      await repo.createField(field('child-b', 1, parentFieldId: 'group'));

      final container = ProviderContainer(
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final failure = await container
          .read(customFieldNotifierProvider.notifier)
          .createField(
            name: 'New top level',
            fieldType: CustomFieldType.text,
            fieldTypeId: 'text',
          );

      expect(failure, isNull);

      final created = (await repo.getAllFields()).singleWhere(
        (field) => field.name == 'New top level',
      );
      expect(created.parentFieldId, isNull);
      expect(created.displayOrder, 41);
    },
  );

  test(
    'custom field notifier preserves an explicit zero display order',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);
      await repo.createField(
        CustomField(
          id: 'existing',
          name: 'existing',
          fieldType: CustomFieldType.text,
          displayOrder: 12,
          createdAt: DateTime(2024, 1, 1),
          fieldTypeId: 'text',
        ),
      );

      final container = ProviderContainer(
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final failure = await container
          .read(customFieldNotifierProvider.notifier)
          .createField(
            name: 'Pinned zero',
            fieldType: CustomFieldType.text,
            displayOrder: 0,
            fieldTypeId: 'text',
          );

      expect(failure, isNull);

      final created = (await repo.getAllFields()).singleWhere(
        (field) => field.name == 'Pinned zero',
      );
      expect(created.displayOrder, 0);
    },
  );

  test(
    'custom field notifier appends after soft-deleted display orders',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);

      CustomField field(String id, int order) => CustomField(
        id: id,
        name: id,
        fieldType: CustomFieldType.text,
        displayOrder: order,
        createdAt: DateTime(2024, 1, 1),
        fieldTypeId: 'text',
      );

      await repo.createField(field('visible', 0));
      await repo.createField(field('deleted-high', 9));
      await repo.deleteField('deleted-high');

      final container = ProviderContainer(
        overrides: [customFieldsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final failure = await container
          .read(customFieldNotifierProvider.notifier)
          .createField(
            name: 'After tombstone',
            fieldType: CustomFieldType.text,
            fieldTypeId: 'text',
          );

      expect(failure, isNull);

      final created = (await repo.getAllFields()).singleWhere(
        (field) => field.name == 'After tombstone',
      );
      expect(created.displayOrder, 10);
    },
  );

  test(
    'custom field append-at-end assigns unique overlapping orders',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repo = DriftCustomFieldsRepository(database.customFieldsDao, null);

      await Future.wait(
        List.generate(5, (index) {
          return repo.createFieldAtEnd(
            CustomField(
              id: 'field-$index',
              name: 'Field $index',
              fieldType: CustomFieldType.text,
              createdAt: DateTime(2024, 1, 1),
              fieldTypeId: 'text',
            ),
          );
        }),
      );

      final fields = await repo.getAllFields();
      expect(fields.map((field) => field.displayOrder), [0, 1, 2, 3, 4]);
    },
  );
}
