import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  group(
    'custom_fields entity — field_type_id, parent_field_id, type_config_json',
    () {
      late AppDatabase db;

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() async {
        await db.close();
      });

      test(
        'round-trips field_type_id, parent_field_id, type_config_json via toSyncFields → applyFields → readRow',
        () async {
          final entity = buildSyncAdapterWithCompletion(db)
              .adapter
              .entities
              .singleWhere((e) => e.tableName == 'custom_fields');

          const typeConfigJson =
              '{"options":[],"allowsMultiple":true,"allowsOther":false}';

          // Insert a row with all three new columns set.
          await db.into(db.customFields).insert(
            CustomFieldsCompanion.insert(
              id: 'test-id',
              name: 'Test Field',
              fieldType: 4,
              fieldTypeId: const Value('choice'),
              parentFieldId: const Value('parent-id'),
              typeConfigJson: const Value(typeConfigJson),
              createdAt: DateTime.utc(2026, 5, 25),
            ),
          );

          // Emit via toSyncFields.
          final row = await (db.select(db.customFields)
                ..where((t) => t.id.equals('test-id')))
              .getSingle();
          final emitted = entity.toSyncFields(row);

          expect(emitted['field_type_id'], 'choice');
          expect(emitted['parent_field_id'], 'parent-id');
          expect(emitted['type_config_json'], typeConfigJson);

          // Apply back to a fresh ID (simulates receiving from a remote peer).
          await entity.applyFields('round-trip-id', emitted);
          final reapplied = await (db.select(db.customFields)
                ..where((t) => t.id.equals('round-trip-id')))
              .getSingle();

          expect(reapplied.fieldTypeId, 'choice');
          expect(reapplied.parentFieldId, 'parent-id');
          expect(reapplied.typeConfigJson, typeConfigJson);

          // readRow — used for retransmits; must also include the new columns.
          final read = await entity.readRow('round-trip-id');
          expect(read, isNotNull);
          expect(read!['field_type_id'], 'choice');
          expect(read['parent_field_id'], 'parent-id');
          expect(read['type_config_json'], typeConfigJson);
        },
      );

      test('null new columns round-trip as null', () async {
        final entity = buildSyncAdapterWithCompletion(db)
            .adapter
            .entities
            .singleWhere((e) => e.tableName == 'custom_fields');

        // Insert without the new optional columns.
        await db.into(db.customFields).insert(
          CustomFieldsCompanion.insert(
            id: 'null-id',
            name: 'Basic Field',
            fieldType: 0,
            createdAt: DateTime.utc(2026, 5, 25),
          ),
        );

        final row = await (db.select(db.customFields)
              ..where((t) => t.id.equals('null-id')))
            .getSingle();
        final emitted = entity.toSyncFields(row);

        expect(emitted['field_type_id'], isNull);
        expect(emitted['parent_field_id'], isNull);
        expect(emitted['type_config_json'], isNull);

        // Apply back — nulls should persist.
        await entity.applyFields('null-rt-id', emitted);
        final reapplied = await (db.select(db.customFields)
              ..where((t) => t.id.equals('null-rt-id')))
            .getSingle();

        expect(reapplied.fieldTypeId, isNull);
        expect(reapplied.parentFieldId, isNull);
        expect(reapplied.typeConfigJson, isNull);

        final read = await entity.readRow('null-rt-id');
        expect(read, isNotNull);
        expect(read!['field_type_id'], isNull);
        expect(read['parent_field_id'], isNull);
        expect(read['type_config_json'], isNull);
      });
    },
  );
}
