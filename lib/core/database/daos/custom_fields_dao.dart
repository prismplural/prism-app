import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
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
            ..orderBy([
              (f) => OrderingTerm.asc(f.displayOrder),
              (f) => OrderingTerm.asc(f.createdAt),
              (f) => OrderingTerm.asc(f.id),
            ]))
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
      (select(customFields)..where((f) => f.id.equals(id))).getSingleOrNull();

  Future<int> createField(CustomFieldsCompanion companion) =>
      into(customFields).insert(companion);

  /// Inserts at the end of [parentFieldId]'s order scope, including tombstones.
  Future<int> createFieldAtEnd(
    CustomFieldsCompanion companion, {
    required String? parentFieldId,
  }) async {
    return transaction(() async {
      final nextOrder = await nextDisplayOrderIncludingDeleted(parentFieldId);
      await into(
        customFields,
      ).insert(companion.copyWith(displayOrder: Value(nextOrder)));
      return nextOrder;
    });
  }

  Future<int> nextDisplayOrderIncludingDeleted(String? parentFieldId) async {
    final sql = parentFieldId == null
        ? 'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM custom_fields WHERE parent_field_id IS NULL'
        : 'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM custom_fields WHERE parent_field_id = ?';
    final rows = await customSelect(
      sql,
      variables: parentFieldId != null
          ? [Variable.withString(parentFieldId)]
          : [],
      readsFrom: {customFields},
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('next');
  }

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
  ) async {
    // Tolerant of >1 active row for one (field, member): two devices refilling a
    // burned id mint different fresh ids, so both can coexist until the apply
    // adapter's dedup collapses them. Order by id and take the first — never
    // throw (getSingleOrNull would), and reads agree on the same survivor.
    final rows =
        await (select(customFieldValues)
              ..where(
                (v) =>
                    v.customFieldId.equals(fieldId) &
                    v.memberId.equals(memberId) &
                    v.isDeleted.equals(false),
              )
              ..orderBy([(v) => OrderingTerm.asc(v.id)]))
            .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Upserts a value for `(customFieldId, memberId)` and returns the row id it
  /// actually wrote. The returned id differs from `companion.id` only in the
  /// burned-id case (see below), so the caller MUST emit its create/update sync
  /// op against the RETURNED id, not the companion's.
  ///
  /// Burned-id mint: a value row id is the deterministic UUIDv5 of
  /// `(field, member)`, and `is_deleted` is absorbing fleet-wide — once a peer
  /// tombstones that id, no `is_deleted=false` op ever revives it. So when there
  /// is no ACTIVE logical row but a TOMBSTONED row already sits at the target id,
  /// writing into it would resurrect a burned id locally that can never
  /// propagate (data-loss / Rust-Dart divergence). Instead we insert a FRESH id
  /// row; the apply-adapter's logical dedup re-converges peers by
  /// `(field, member)`. [mintFreshId] supplies that id (default: a random v4,
  /// which no peer can hold a tombstone for); tests inject it for determinism.
  Future<String> upsertValue(
    CustomFieldValuesCompanion companion, {
    String Function()? mintFreshId,
  }) {
    final id = companion.id.value;
    final customFieldId = companion.customFieldId.value;
    final memberId = companion.memberId.value;
    final mint = mintFreshId ?? () => const Uuid().v4();

    return transaction(() async {
      final activeLogical = await getValueForField(customFieldId, memberId);
      if (activeLogical != null) {
        // Active-row lookup wins: write the live logical row, never the derived
        // id (which may be a stale tombstone).
        await (update(customFieldValues)
              ..where((v) => v.id.equals(activeLogical.id)))
            .write(companion.copyWith(id: Value(activeLogical.id)));
        return activeLogical.id;
      }

      final existing = await (select(
        customFieldValues,
      )..where((v) => v.id.equals(id))).getSingleOrNull();
      if (existing == null) {
        // First-ever fill: keep the deterministic id so paired devices dedup
        // a concurrent first-fill on the same (field, member).
        await into(customFieldValues).insert(companion);
        return id;
      }
      if (!existing.isDeleted) {
        // Live row at the target id (no logical row means this id IS the row);
        // plain update.
        await (update(
          customFieldValues,
        )..where((v) => v.id.equals(id))).write(companion);
        return id;
      }
      // Burned id: mint a fresh row rather than reviving the tombstone.
      final freshId = mint();
      await into(customFieldValues).insert(
        companion.copyWith(id: Value(freshId), isDeleted: const Value(false)),
      );
      return freshId;
    });
  }

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

  // ── Bulk reset helpers ──────────────────────────────────────────────────────

  Future<List<String>> getNonDeletedFieldIds() =>
      (selectOnly(customFields)
            ..addColumns([customFields.id])
            ..where(customFields.isDeleted.equals(false)))
          .map((row) => row.read(customFields.id)!)
          .get();

  Future<List<String>> getNonDeletedValueIds() =>
      (selectOnly(customFieldValues)
            ..addColumns([customFieldValues.id])
            ..where(customFieldValues.isDeleted.equals(false)))
          .map((row) => row.read(customFieldValues.id)!)
          .get();

  /// Captures the IDs that transition to tombstoned inside the same
  /// transaction as the update so the caller can emit CRDT sync ops without
  /// a snapshot/write race. Returns empty lists when there's nothing active.
  Future<({List<String> fieldIds, List<String> valueIds})>
  softDeleteAllCustomFieldData() async {
    return transaction(() async {
      final fieldIds =
          await (selectOnly(customFields)
                ..addColumns([customFields.id])
                ..where(customFields.isDeleted.equals(false)))
              .map((row) => row.read(customFields.id)!)
              .get();
      final valueIds =
          await (selectOnly(customFieldValues)
                ..addColumns([customFieldValues.id])
                ..where(customFieldValues.isDeleted.equals(false)))
              .map((row) => row.read(customFieldValues.id)!)
              .get();
      await (update(customFields)..where((f) => f.isDeleted.equals(false)))
          .write(const CustomFieldsCompanion(isDeleted: Value(true)));
      await (update(customFieldValues)..where((v) => v.isDeleted.equals(false)))
          .write(const CustomFieldValuesCompanion(isDeleted: Value(true)));
      return (fieldIds: fieldIds, valueIds: valueIds);
    });
  }
}
