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

  // Regression: sync-inbound applyFields wrote `parent_field_id`
  // verbatim, letting a buggy or malicious peer plant self-cycles or
  // depth-2 (grandchild) rows into local storage that then re-emit on
  // the next sync. The write-side `createField` / `moveFieldToParent`
  // helpers enforce depth-1 and reject self-loops;
  // `promoteOrphansForRender` hides the corruption from the UI but the
  // bad rows still propagate. applyFields now normalizes
  // `parent_field_id` to null on those two cases.
  group('custom_fields applyFields — parent_field_id validation', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('self-cycle (parent_field_id == id) is normalized to null',
        () async {
      final entity = buildSyncAdapterWithCompletion(db)
          .adapter
          .entities
          .singleWhere((e) => e.tableName == 'custom_fields');

      await entity.applyFields('self-cycle-id', <String, dynamic>{
        'name': 'Self-Cycle',
        'field_type': 0,
        'field_type_id': 'text',
        'parent_field_id': 'self-cycle-id',
        'type_config_json': null,
        'date_precision': null,
        'display_order': 0,
        'created_at': DateTime.utc(2026, 5, 25).toIso8601String(),
        'is_deleted': false,
      });

      final stored = await (db.select(db.customFields)
            ..where((t) => t.id.equals('self-cycle-id')))
          .getSingleOrNull();
      expect(stored, isNotNull);
      expect(
        stored!.parentFieldId,
        isNull,
        reason:
            'self-cycle parent_field_id must be normalized to null so it '
            'does not re-emit cycles to other peers via per-field LWW',
      );
    });

    test('depth-2 (parent has its own parent) is normalized to null',
        () async {
      final entity = buildSyncAdapterWithCompletion(db)
          .adapter
          .entities
          .singleWhere((e) => e.tableName == 'custom_fields');

      // Seed a depth-1 chain: root-group → mid (a child of root-group).
      await db.into(db.customFields).insert(
        CustomFieldsCompanion.insert(
          id: 'root-group',
          name: 'Root Group',
          fieldType: 0,
          fieldTypeId: const Value('group'),
          createdAt: DateTime.utc(2026, 5, 25),
        ),
      );
      await db.into(db.customFields).insert(
        CustomFieldsCompanion.insert(
          id: 'mid',
          name: 'Mid',
          fieldType: 0,
          fieldTypeId: const Value('group'),
          parentFieldId: const Value('root-group'),
          createdAt: DateTime.utc(2026, 5, 25),
        ),
      );

      // Sync arrives asserting `grandchild.parent_field_id = 'mid'`,
      // which would create a depth-2 row.
      await entity.applyFields('grandchild', <String, dynamic>{
        'name': 'Grandchild',
        'field_type': 0,
        'field_type_id': 'text',
        'parent_field_id': 'mid',
        'type_config_json': null,
        'date_precision': null,
        'display_order': 0,
        'created_at': DateTime.utc(2026, 5, 25).toIso8601String(),
        'is_deleted': false,
      });

      final stored = await (db.select(db.customFields)
            ..where((t) => t.id.equals('grandchild')))
          .getSingleOrNull();
      expect(stored, isNotNull);
      expect(
        stored!.parentFieldId,
        isNull,
        reason:
            'depth-2 parent_field_id must be normalized to null so the '
            'row does not propagate grandchild corruption to other peers',
      );
    });

    test('valid depth-1 parent is preserved verbatim', () async {
      final entity = buildSyncAdapterWithCompletion(db)
          .adapter
          .entities
          .singleWhere((e) => e.tableName == 'custom_fields');

      // Seed a top-level group.
      await db.into(db.customFields).insert(
        CustomFieldsCompanion.insert(
          id: 'top-group',
          name: 'Top Group',
          fieldType: 0,
          fieldTypeId: const Value('group'),
          createdAt: DateTime.utc(2026, 5, 25),
        ),
      );

      await entity.applyFields('child', <String, dynamic>{
        'name': 'Child',
        'field_type': 0,
        'field_type_id': 'text',
        'parent_field_id': 'top-group',
        'type_config_json': null,
        'date_precision': null,
        'display_order': 0,
        'created_at': DateTime.utc(2026, 5, 25).toIso8601String(),
        'is_deleted': false,
      });

      final stored = await (db.select(db.customFields)
            ..where((t) => t.id.equals('child')))
          .getSingleOrNull();
      expect(stored, isNotNull);
      expect(stored!.parentFieldId, 'top-group');
    });

    test('missing-parent reference is tolerated verbatim (sync ordering)',
        () async {
      // Sync apply order is non-deterministic. The parent row may not
      // exist locally yet; render-time promotion handles the gap and the
      // child re-attaches naturally once the parent arrives.
      final entity = buildSyncAdapterWithCompletion(db)
          .adapter
          .entities
          .singleWhere((e) => e.tableName == 'custom_fields');

      await entity.applyFields('child-missing-parent', <String, dynamic>{
        'name': 'Child',
        'field_type': 0,
        'field_type_id': 'text',
        'parent_field_id': 'not-yet-synced-parent',
        'type_config_json': null,
        'date_precision': null,
        'display_order': 0,
        'created_at': DateTime.utc(2026, 5, 25).toIso8601String(),
        'is_deleted': false,
      });

      final stored = await (db.select(db.customFields)
            ..where((t) => t.id.equals('child-missing-parent')))
          .getSingleOrNull();
      expect(stored, isNotNull);
      expect(stored!.parentFieldId, 'not-yet-synced-parent');
    });
  });
}
