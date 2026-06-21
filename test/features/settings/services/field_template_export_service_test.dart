import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/settings/services/field_template_export_service.dart';

// Stub out sync emissions — tests don't run with a real FFI handle.
class _NoSyncRepo extends DriftCustomFieldsRepository {
  _NoSyncRepo(CustomFieldsDao dao) : super(dao, null);
}

void main() {
  late db.AppDatabase database;
  late _NoSyncRepo repo;
  late FieldTemplateExportService service;

  final baseTime = DateTime.utc(2026, 6, 1, 10);

  CustomField makeField({
    required String id,
    required String name,
    String fieldTypeId = 'text',
    String? parentFieldId,
    int displayOrder = 0,
  }) {
    return CustomField(
      id: id,
      name: name,
      fieldType: CustomFieldType.text,
      fieldTypeId: fieldTypeId,
      parentFieldId: parentFieldId,
      displayOrder: displayOrder,
      createdAt: baseTime,
    );
  }

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = _NoSyncRepo(database.customFieldsDao);
    service = FieldTemplateExportService(repo);
  });

  tearDown(() async {
    await database.close();
  });

  // ── Seed helpers ────────────────────────────────────────────────────

  // Seeds: group G (displayOrder 0) + 3 children (displayOrder 0,1,2) +
  // unrelated top-level field X (displayOrder 1).
  Future<void> seedStandardFixture() async {
    // Group field
    await repo.createField(makeField(
      id: 'G',
      name: 'Group G',
      fieldTypeId: 'group',
      displayOrder: 0,
    ));
    // Children — created with real parentFieldId so the repo keeps them
    // raw (no orphan-promotion). Use createFieldFromImport to bypass the
    // UI-flow depth check; it preserves parentFieldId verbatim.
    await repo.createFieldFromImport(makeField(
      id: 'C1',
      name: 'Child 1',
      parentFieldId: 'G',
      displayOrder: 0,
    ));
    await repo.createFieldFromImport(makeField(
      id: 'C2',
      name: 'Child 2',
      parentFieldId: 'G',
      displayOrder: 1,
    ));
    await repo.createFieldFromImport(makeField(
      id: 'C3',
      name: 'Child 3',
      parentFieldId: 'G',
      displayOrder: 2,
    ));
    // Unrelated top-level field
    await repo.createField(makeField(
      id: 'X',
      name: 'Unrelated',
      displayOrder: 1,
    ));
  }

  // ── buildTemplateForGroup ────────────────────────────────────────────

  test('buildTemplateForGroup: 4 entries — group + 3 children, not X',
      () async {
    await seedStandardFixture();

    final tmpl = await service.buildTemplateForGroup('G');

    expect(tmpl.entries, hasLength(4));
    final names = tmpl.entries.map((e) => e.name).toList();
    expect(names, contains('Group G'));
    expect(names, contains('Child 1'));
    expect(names, contains('Child 2'));
    expect(names, contains('Child 3'));
    expect(names, isNot(contains('Unrelated')));
  });

  test('buildTemplateForGroup: group is first entry', () async {
    await seedStandardFixture();

    final tmpl = await service.buildTemplateForGroup('G');

    expect(tmpl.entries.first.name, 'Group G');
  });

  test('buildTemplateForGroup: children parentIndex points at group (index 0)',
      () async {
    await seedStandardFixture();

    final tmpl = await service.buildTemplateForGroup('G');

    // Entry 0 is the group (parentIndex null). Entries 1..3 are children.
    expect(tmpl.entries[0].parentIndex, isNull);
    for (final entry in tmpl.entries.skip(1)) {
      expect(entry.parentIndex, 0,
          reason: 'child ${entry.name} must point at index 0 (the group)');
    }
  });

  test('buildTemplateForGroup: children ordered by displayOrder', () async {
    await seedStandardFixture();

    final tmpl = await service.buildTemplateForGroup('G');

    final childNames = tmpl.entries.skip(1).map((e) => e.name).toList();
    expect(childNames, ['Child 1', 'Child 2', 'Child 3']);
  });

  // ── buildTemplateForField ────────────────────────────────────────────

  test('buildTemplateForField: single field, no parentIndex', () async {
    await seedStandardFixture();

    final tmpl = await service.buildTemplateForField('X');

    expect(tmpl.entries, hasLength(1));
    expect(tmpl.entries.single.name, 'Unrelated');
    expect(tmpl.entries.single.parentIndex, isNull);
  });

  // ── Edge: empty group ────────────────────────────────────────────────

  test('buildTemplateForGroup: empty group yields 1 entry', () async {
    // Only the group, no children.
    await repo.createField(makeField(
      id: 'EmptyG',
      name: 'Empty Group',
      fieldTypeId: 'group',
      displayOrder: 0,
    ));

    final tmpl = await service.buildTemplateForGroup('EmptyG');

    expect(tmpl.entries, hasLength(1));
    expect(tmpl.entries.single.name, 'Empty Group');
    expect(tmpl.entries.single.parentIndex, isNull);
  });
}
