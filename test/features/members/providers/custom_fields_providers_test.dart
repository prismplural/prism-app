import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';

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
}
