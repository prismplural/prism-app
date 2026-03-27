import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/custom_fields_table.dart';
import 'package:prism_plurality/core/database/tables/custom_field_values_table.dart';

part 'custom_fields_dao.g.dart';

@DriftAccessor(tables: [CustomFields, CustomFieldValues])
class CustomFieldsDao extends DatabaseAccessor<AppDatabase>
    with _$CustomFieldsDaoMixin {
  CustomFieldsDao(super.db);

  // ── Fields ─────────────────────────────────────────────────────────

  Stream<List<CustomFieldRow>> watchAllFields() =>
      (select(customFields)
            ..where((f) => f.isDeleted.equals(false))
            ..orderBy([(f) => OrderingTerm.asc(f.displayOrder)]))
          .watch();

  Stream<CustomFieldRow?> watchFieldById(String id) =>
      (select(customFields)
            ..where((f) => f.id.equals(id) & f.isDeleted.equals(false)))
          .watchSingleOrNull();

  Future<CustomFieldRow?> getFieldById(String id) =>
      (select(customFields)
            ..where((f) => f.id.equals(id) & f.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<int> createField(CustomFieldsCompanion companion) =>
      into(customFields).insert(companion);

  Future<void> updateField(String id, CustomFieldsCompanion companion) =>
      (update(customFields)..where((f) => f.id.equals(id))).write(companion);

  Future<void> deleteField(String id) async {
    // Soft-delete all values for this field
    await (update(customFieldValues)
          ..where((v) => v.customFieldId.equals(id)))
        .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));
    // Soft-delete the field itself
    await (update(customFields)..where((f) => f.id.equals(id)))
        .write(const CustomFieldsCompanion(isDeleted: Value(true)));
  }

  // ── Values ─────────────────────────────────────────────────────────

  Future<List<CustomFieldValueRow>> getAllValues() =>
      (select(customFieldValues)..where((v) => v.isDeleted.equals(false)))
          .get();

  Stream<List<CustomFieldValueRow>> watchValuesForMember(String memberId) =>
      (select(customFieldValues)
            ..where((v) =>
                v.memberId.equals(memberId) & v.isDeleted.equals(false)))
          .watch();

  Stream<List<CustomFieldValueRow>> watchValuesForField(String fieldId) =>
      (select(customFieldValues)
            ..where((v) =>
                v.customFieldId.equals(fieldId) & v.isDeleted.equals(false)))
          .watch();

  Future<CustomFieldValueRow?> getValueForField(
    String fieldId,
    String memberId,
  ) =>
      (select(customFieldValues)
            ..where((v) =>
                v.customFieldId.equals(fieldId) &
                v.memberId.equals(memberId) &
                v.isDeleted.equals(false)))
          .getSingleOrNull();

  Future<int> upsertValue(CustomFieldValuesCompanion companion) =>
      into(customFieldValues).insertOnConflictUpdate(companion);

  Future<void> deleteValue(String id) =>
      (update(customFieldValues)..where((v) => v.id.equals(id)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));

  Future<void> deleteValuesForField(String fieldId) =>
      (update(customFieldValues)
            ..where((v) => v.customFieldId.equals(fieldId)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));

  Future<void> deleteValuesForMember(String memberId) =>
      (update(customFieldValues)
            ..where((v) => v.memberId.equals(memberId)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));
}
