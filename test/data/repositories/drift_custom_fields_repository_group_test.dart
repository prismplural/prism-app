import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Subclass that suppresses sync-record calls so tests don't need a Rust
/// FFI handle.
class _SilentRepo extends DriftCustomFieldsRepository {
  _SilentRepo(CustomFieldsDao dao) : super(dao, null);

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {}

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CustomField _field({
  required String id,
  String? parentFieldId,
  String fieldTypeId = 'text',
}) {
  return CustomField(
    id: id,
    name: 'Field $id',
    fieldType: CustomFieldType.text,
    displayOrder: 0,
    createdAt: DateTime(2024),
    fieldTypeId: fieldTypeId,
    parentFieldId: parentFieldId,
  );
}

CustomField _groupField({required String id, String? parentFieldId}) =>
    _field(id: id, fieldTypeId: 'group', parentFieldId: parentFieldId);

CustomFieldValue _value({required String id, required String customFieldId}) {
  return CustomFieldValue(
    id: id,
    customFieldId: customFieldId,
    memberId: 'member-1',
    value: 'test',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late db.AppDatabase database;
  late _SilentRepo repo;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = _SilentRepo(database.customFieldsDao);
  });

  tearDown(() async {
    await database.close();
  });

  // ── 1. Depth-1 enforcement on createField ────────────────────────────────

  test(
    'createField throws DepthLimitExceededException when grandchild depth would exceed 1',
    () async {
      final fieldA = _groupField(id: 'A');
      final fieldB = _field(id: 'B', parentFieldId: 'A');
      final fieldC = _field(id: 'C', parentFieldId: 'B');

      await repo.createField(fieldA);
      await repo.createField(fieldB);

      expect(
        () => repo.createField(fieldC),
        throwsA(isA<DepthLimitExceededException>()),
      );
    },
  );

  test('createField succeeds when parent has no parent (depth-1 is ok)', () async {
    final fieldA = _groupField(id: 'A');
    final fieldB = _field(id: 'B', parentFieldId: 'A');

    await repo.createField(fieldA);
    // Must not throw.
    await repo.createField(fieldB);

    final found = await repo.getFieldById('B');
    expect(found?.parentFieldId, 'A');
  });

  // ── 2. Depth-1 enforcement on updateField ───────────────────────────────

  test(
    'updateField throws DepthLimitExceededException when re-parenting would exceed depth 1',
    () async {
      final fieldA = _groupField(id: 'A');
      final fieldB = _field(id: 'B', parentFieldId: 'A');
      final fieldC = _field(id: 'C');

      await repo.createField(fieldA);
      await repo.createField(fieldB);
      await repo.createField(fieldC);

      // Attempt to make C a child of B (B already has parent A → depth 2).
      final cWithBAsParent = fieldC.copyWith(parentFieldId: 'B');
      expect(
        () => repo.updateField(cWithBAsParent),
        throwsA(isA<DepthLimitExceededException>()),
      );
    },
  );

  // ── 3. upsertValue rejected for group-typed fields ───────────────────────

  test(
    'upsertValue throws InvalidFieldTypeException for group-typed fields',
    () async {
      final groupF = _groupField(id: 'group-1');
      await repo.createField(groupF);

      expect(
        () => repo.upsertValue(_value(id: 'v1', customFieldId: 'group-1')),
        throwsA(isA<InvalidFieldTypeException>()),
      );
    },
  );

  test('upsertValue succeeds for non-group fields', () async {
    final textF = _field(id: 'text-1');
    await repo.createField(textF);

    // Must not throw.
    await repo.upsertValue(_value(id: 'v1', customFieldId: 'text-1'));

    final stored = await repo.getValueForField('text-1', 'member-1');
    expect(stored?.value, 'test');
  });

  // ── 4. Orphan-on-read promotion (soft-deleted parent) ────────────────────

  test(
    'watchAllFields promotes child to top level when its parent is soft-deleted',
    () async {
      final groupG = _groupField(id: 'G');
      final childC = _field(id: 'C', parentFieldId: 'G');

      await repo.createField(groupG);
      await repo.createField(childC);

      // Soft-delete G using the DAO directly (bypassing the group deleteField
      // logic so we can test orphan promotion in isolation).
      await database.customFieldsDao.deleteField('G');

      final fields = await repo.watchAllFields().first;

      // G is deleted; only C appears.
      expect(fields.map((f) => f.id), isNot(contains('G')));
      final c = fields.firstWhere((f) => f.id == 'C');
      // C should be promoted: parentFieldId cleared in-memory.
      expect(c.parentFieldId, isNull);
    },
  );

  // ── 5. Orphan-on-read when parent was never inserted ─────────────────────

  test(
    'watchAllFields promotes child to top level when parent id is nonexistent',
    () async {
      // Insert C with a parent that does not exist in the DB.
      final childC = _field(id: 'C', parentFieldId: 'nonexistent');
      await repo.createField(childC);

      final fields = await repo.watchAllFields().first;
      final c = fields.firstWhere((f) => f.id == 'C');
      expect(c.parentFieldId, isNull);
    },
  );

  // ── 6. deleteField group with deleteChildren=false (promote) ─────────────

  test(
    'deleteField with deleteChildren=false promotes children to top level',
    () async {
      final groupG = _groupField(id: 'G');
      final child1 = _field(id: 'C1', parentFieldId: 'G');
      final child2 = _field(id: 'C2', parentFieldId: 'G');

      await repo.createField(groupG);
      await repo.createField(child1);
      await repo.createField(child2);

      // Default: deleteChildren = false → promote.
      await repo.deleteField('G');

      // G should be soft-deleted (not found by getFieldById).
      final g = await repo.getFieldById('G');
      expect(g, isNull);

      // C1 and C2 should still be active with parentFieldId cleared.
      final c1 = await repo.getFieldById('C1');
      final c2 = await repo.getFieldById('C2');
      expect(c1, isNotNull);
      expect(c1!.parentFieldId, isNull);
      expect(c2, isNotNull);
      expect(c2!.parentFieldId, isNull);
    },
  );

  // ── 7. deleteField group with deleteChildren=true ────────────────────────

  test(
    'deleteField with deleteChildren=true soft-deletes group and all children',
    () async {
      final groupG = _groupField(id: 'G');
      final child1 = _field(id: 'C1', parentFieldId: 'G');
      final child2 = _field(id: 'C2', parentFieldId: 'G');

      await repo.createField(groupG);
      await repo.createField(child1);
      await repo.createField(child2);

      await repo.deleteField('G', deleteChildren: true);

      // All three should be soft-deleted.
      expect(await repo.getFieldById('G'), isNull);
      expect(await repo.getFieldById('C1'), isNull);
      expect(await repo.getFieldById('C2'), isNull);
    },
  );

  // ── 8. deleteField for non-group field is unchanged ──────────────────────

  test(
    'deleteField on non-group field soft-deletes it regardless of deleteChildren',
    () async {
      final textF = _field(id: 'text-1');
      await repo.createField(textF);

      await repo.deleteField('text-1', deleteChildren: false);

      expect(await repo.getFieldById('text-1'), isNull);
    },
  );

  test(
    'deleteField is idempotent for missing fields',
    () async {
      // Should not throw for an unknown id.
      await repo.deleteField('nonexistent-id');
    },
  );
}
