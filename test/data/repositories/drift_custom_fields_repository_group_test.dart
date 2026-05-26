import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/custom_fields/orphan_promotion.dart';
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
    'moveFieldToParent throws DepthLimitExceededException when target itself is nested',
    () async {
      // Validation lives only in moveFieldToParent (user-intent moves).
      // updateField tolerates invalid parents because importers replay
      // historical state. This test exercises the explicit move path.
      final fieldA = _groupField(id: 'A');
      final fieldB = _field(id: 'B', parentFieldId: 'A');
      final fieldC = _field(id: 'C');

      await repo.createField(fieldA);
      await repo.createField(fieldB);
      await repo.createField(fieldC);

      // Attempt to make C a child of B (B already has parent A → depth 2).
      expect(
        () => repo.moveFieldToParent('C', 'B'),
        throwsA(isA<DepthLimitExceededException>()),
      );
    },
  );

  test(
    'updateField tolerates parent-state changes (importer replay) without throwing',
    () async {
      // updateField is the importer/replay full-row path. It must not throw
      // on a nested-parent payload; render-layer orphan promotion handles
      // display when the structure is invalid.
      final fieldA = _groupField(id: 'A');
      final fieldB = _field(id: 'B', parentFieldId: 'A');
      final fieldC = _field(id: 'C');

      await repo.createField(fieldA);
      await repo.createField(fieldB);
      await repo.createField(fieldC);

      // Replay would-be-invalid: C points at B which itself has a parent.
      final cWithBAsParent = fieldC.copyWith(parentFieldId: 'B');
      // Should complete without throwing — the importer/replay surface is
      // tolerant of historical/peer state.
      await repo.updateField(cWithBAsParent);

      final stored = await repo.getFieldById('C');
      expect(stored?.parentFieldId, 'B');
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

  // ── 4. Raw stream + render-layer promotion (soft-deleted parent) ─────────
  //
  // The repo stream exposes the raw on-disk view; `promoteOrphansForRender`
  // (driven by `topLevelCustomFieldsProvider`) is what applies the
  // parent-clearing transform for display.

  test(
    'watchAllFields preserves raw parentFieldId when parent is soft-deleted; '
    'promoteOrphansForRender promotes the child',
    () async {
      final groupG = _groupField(id: 'G');
      final childC = _field(id: 'C', parentFieldId: 'G');

      await repo.createField(groupG);
      await repo.createField(childC);

      // Soft-delete G using the DAO directly (bypassing the group deleteField
      // logic so we can test the read-side contract in isolation).
      await database.customFieldsDao.deleteField('G');

      final raw = await repo.watchAllFields().first;
      // G is filtered out by the DAO (isDeleted = true).
      expect(raw.map((f) => f.id), isNot(contains('G')));
      final rawC = raw.firstWhere((f) => f.id == 'C');
      // Raw view preserves on-disk parent_field_id — important for write paths
      // and group editors that filter by exact parent match.
      expect(rawC.parentFieldId, 'G');

      // Render-layer projection promotes orphans for display.
      final projected = promoteOrphansForRender(raw);
      final projectedC = projected.firstWhere((f) => f.id == 'C');
      expect(projectedC.parentFieldId, isNull);
    },
  );

  // ── 5. Same contract for nonexistent parent ──────────────────────────────

  test(
    'watchAllFields preserves raw parentFieldId when parent id is nonexistent; '
    'promoteOrphansForRender promotes the child',
    () async {
      // Insert C with a parent that does not exist in the DB.
      final childC = _field(id: 'C', parentFieldId: 'nonexistent');
      await repo.createField(childC);

      final raw = await repo.watchAllFields().first;
      final rawC = raw.firstWhere((f) => f.id == 'C');
      expect(rawC.parentFieldId, 'nonexistent');

      final projected = promoteOrphansForRender(raw);
      final projectedC = projected.firstWhere((f) => f.id == 'C');
      expect(projectedC.parentFieldId, isNull);
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
