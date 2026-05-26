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

  /// Look up a row by id INCLUDING soft-deleted tombstones. Used by
  /// `createFieldFromImport` to detect the tombstone-collision case (where
  /// the backup carries a row whose id matches a row this device previously
  /// deleted) — without this, the INSERT would hit a UNIQUE constraint and
  /// roll back the entire restore transaction.
  Future<CustomFieldRow?> getFieldByIdIncludingDeleted(String id) =>
      (select(customFields)..where((f) => f.id.equals(id)))
          .getSingleOrNull();

  Future<int> createField(CustomFieldsCompanion companion) =>
      into(customFields).insert(companion);

  /// Batch-insert custom fields in a single Drift `batch()` round-trip.
  /// Phase 6 SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
  Future<void> batchInsertFields(List<CustomFieldsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(customFields, rows));
  }

  /// Returns the affected row count. Filters to ACTIVE rows only — soft-deleted
  /// tombstones don't match, so a stale UI patching a deleted row gets
  /// affected=0 and the repository bails before emitting a phantom sync op.
  Future<int> updateField(String id, CustomFieldsCompanion companion) =>
      (update(customFields)
            ..where((f) => f.id.equals(id) & f.isDeleted.equals(false)))
          .write(companion);

  /// Update WITHOUT the isDeleted filter. Used by [createFieldFromImport] to
  /// resurrect soft-deleted tombstones during backup restore. Do NOT use from
  /// general patch paths — they should always go through [updateField] so
  /// stale UI writes don't reach tombstoned rows.
  Future<int> resurrectField(String id, CustomFieldsCompanion companion) =>
      (update(customFields)..where((f) => f.id.equals(id))).write(companion);

  /// Bulk-update field display orders in one SQL statement.
  ///
  /// Per-row updates each emit a fresh `watchAllFields` value, which makes
  /// ReorderableListView snap back to the partial state mid-drag. One write,
  /// one emit — no flicker.
  Future<void> bulkUpdateDisplayOrders(Map<String, int> displayOrders) async {
    if (displayOrders.isEmpty) return;

    final ids = displayOrders.keys.toList(growable: false);
    final whenClauses = ids.map((_) => 'WHEN ? THEN ?').join(' ');
    final wherePlaceholders = List.filled(ids.length, '?').join(', ');
    final variables = <Variable>[];

    for (final entry in displayOrders.entries) {
      variables.add(Variable.withString(entry.key));
      variables.add(Variable.withInt(entry.value));
    }
    variables.addAll(ids.map(Variable.withString));

    await customUpdate(
      '''
      UPDATE custom_fields
      SET display_order = CASE id
        $whenClauses
        ELSE display_order
      END
      WHERE id IN ($wherePlaceholders)
      ''',
      variables: variables,
      updates: {customFields},
    );
  }

  Future<void> deleteField(String id) async {
    // Soft-delete all values for this field
    await (update(customFieldValues)..where((v) => v.customFieldId.equals(id)))
        .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));
    // Soft-delete the field itself
    await (update(customFields)..where((f) => f.id.equals(id))).write(
      const CustomFieldsCompanion(isDeleted: Value(true)),
    );
  }

  // ── Values ─────────────────────────────────────────────────────────

  Future<List<CustomFieldValueRow>> getAllValues() => (select(
    customFieldValues,
  )..where((v) => v.isDeleted.equals(false))).get();

  Stream<List<CustomFieldValueRow>> watchValuesForMember(String memberId) =>
      (select(customFieldValues)..where(
            (v) => v.memberId.equals(memberId) & v.isDeleted.equals(false),
          ))
          .watch();

  Stream<List<CustomFieldValueRow>> watchValuesForField(String fieldId) =>
      (select(customFieldValues)..where(
            (v) => v.customFieldId.equals(fieldId) & v.isDeleted.equals(false),
          ))
          .watch();

  Future<CustomFieldValueRow?> getValueForField(
    String fieldId,
    String memberId,
  ) =>
      (select(customFieldValues)..where(
            (v) =>
                v.customFieldId.equals(fieldId) &
                v.memberId.equals(memberId) &
                v.isDeleted.equals(false),
          ))
          .getSingleOrNull();

  Future<int> upsertValue(CustomFieldValuesCompanion companion) =>
      into(customFieldValues).insertOnConflictUpdate(companion);

  /// Batch-upsert custom-field values in a single Drift `batch()` round-trip.
  /// Mirrors the single-row [upsertValue]'s `insertOnConflictUpdate` policy so
  /// re-imports overwrite stale values per the live-edit semantics. Phase 6
  /// SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
  Future<void> batchUpsertValues(List<CustomFieldValuesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(customFieldValues, rows));
  }

  Future<void> deleteValue(String id) =>
      (update(customFieldValues)..where((v) => v.id.equals(id))).write(
        const CustomFieldValuesCompanion(isDeleted: Value(true)),
      );

  Future<void> deleteValuesForField(String fieldId) =>
      (update(customFieldValues)..where((v) => v.customFieldId.equals(fieldId)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));

  Future<void> deleteValuesForMember(String memberId) =>
      (update(customFieldValues)..where((v) => v.memberId.equals(memberId)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));
}
