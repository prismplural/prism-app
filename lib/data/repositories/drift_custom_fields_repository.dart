import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_value_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';

class DriftCustomFieldsRepository
    with SyncRecordMixin
    implements CustomFieldsRepository {
  final CustomFieldsDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _fieldsTable = 'custom_fields';
  static const _valuesTable = 'custom_field_values';

  DriftCustomFieldsRepository(this._dao, this._syncHandle);

  // ── Fields ─────────────────────────────────────────────────────────

  @override
  Stream<List<domain.CustomField>> watchAllFields() {
    // Raw on-disk view — no orphan-promotion transform here. Render-layer
    // promotion lives in `lib/domain/custom_fields/orphan_promotion.dart`
    // and is applied via `topLevelCustomFieldsProvider`. Keeping the repo
    // stream raw means:
    //   - the group editor can filter by exact `parentFieldId == groupId`
    //   - write paths never see a promoted (parent-cleared) snapshot, which
    //     would otherwise risk propagating the cleared parent back to disk.
    return _dao.watchAllFields().map(
      (rows) => rows.map(CustomFieldMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.CustomField>> getAllFields() async {
    final rows = await _dao.watchAllFields().first;
    return rows.map(CustomFieldMapper.toDomain).toList();
  }

  @override
  Stream<domain.CustomField?> watchFieldById(String id) {
    return _dao
        .watchFieldById(id)
        .map((row) => row != null ? CustomFieldMapper.toDomain(row) : null);
  }

  @override
  Future<domain.CustomField?> getFieldById(String id) async {
    final row = await _dao.getFieldById(id);
    return row != null ? CustomFieldMapper.toDomain(row) : null;
  }

  @override
  Future<void> createField(domain.CustomField field) async {
    // UI-flow creation. Validates parent (must exist, be a group, not nested)
    // so invalid setup fails loudly at the call site. Importer/restore paths
    // that legitimately replay historical state — including bad parent
    // references from older builds — must use [createFieldFromImport] instead.
    await _validateDepth(field);
    final companion = CustomFieldMapper.toCompanion(field);
    await _dao.createField(companion);
    await syncRecordCreate(_fieldsTable, field.id, _fieldFields(field));
  }

  /// Creates a field at the end of its order scope.
  Future<void> createFieldAtEnd(domain.CustomField field) async {
    await _validateDepth(field);
    final companion = CustomFieldMapper.toCompanion(field);
    final displayOrder = await _dao.createFieldAtEnd(
      companion,
      parentFieldId: field.parentFieldId,
    );
    final createdField = field.copyWith(displayOrder: displayOrder);
    await syncRecordCreate(
      _fieldsTable,
      createdField.id,
      _fieldFields(createdField),
    );
  }

  @override
  Future<void> createFieldFromImport(domain.CustomField field) async {
    // Restore bypass: tolerates non-group / nested / soft-deleted parents
    // that a backup may carry. The on-disk parent_field_id is preserved
    // verbatim; render-layer promotion handles display until the parent
    // returns via sync.
    //
    // If the id already exists (including as a tombstone from a prior local
    // deletion), resurrect via UPDATE rather than INSERT — a bare INSERT
    // would hit the PK UNIQUE constraint and roll back the whole import
    // transaction. Emit as a create so peers that applied the prior
    // tombstone re-materialize the row.
    final existing = await _dao.getFieldByIdIncludingDeleted(field.id);
    final companion = CustomFieldMapper.toCompanion(field);
    if (existing == null) {
      await _dao.createField(companion);
    } else {
      await _dao.resurrectField(
        field.id,
        companion.copyWith(isDeleted: const Value(false)),
      );
    }
    await syncRecordCreate(_fieldsTable, field.id, _fieldFields(field));
  }

  @override
  Future<void> updateField(domain.CustomField field) async {
    // Importer/replay path. Diff against current DB so the wire only carries
    // changed fields — stale values in the incoming snapshot can't clobber a
    // peer's concurrent edits. Mirrors drift_habit_repository.dart.
    //
    // No parent validation here: importers legitimately replay historical
    // state including invalid parents. Render-layer promotion handles
    // display; validation lives in [createField] and [moveFieldToParent].
    final existingRow = await _dao.getFieldById(field.id);
    if (existingRow == null) return;
    final prev = fieldFieldsFromRow(existingRow);
    final next = _fieldFields(field);
    final changed = diffSyncFields(prev, next);
    if (changed.isEmpty) return;
    final companion = _partialCustomFieldCompanion(changed);
    final affected = await _dao.updateField(field.id, companion);
    if (affected != 1) return;
    await syncRecordUpdate(_fieldsTable, field.id, changed);
  }

  // ── Patch methods ──────────────────────────────────────────────────
  //
  // Each constructs a one-key change set and routes through [_writePartial].
  // The partial companion is Value.absent() for every other column, so
  // on-disk values are preserved and the sync emit covers only the changed
  // key — peers' concurrent edits to other columns aren't overwritten.

  @override
  Future<void> renameField(String fieldId, String newName) =>
      _writePartial(fieldId, {'name': newName});

  @override
  Future<void> moveFieldToParent(String fieldId, String? newParentId) async {
    if (newParentId != null) {
      // User-intent move: validate target before writing. createField's
      // _validateDepth covers UI-flow creation; updateField (importer/replay)
      // intentionally skips depth validation so historical replay tolerates
      // any parent state. This branch is the only place that throws on
      // invalid moves — surfaced as a toast in the move call sites.
      final parent = await getFieldById(newParentId);
      if (parent == null) {
        throw InvalidFieldTypeException(
          newParentId,
          'parent field $newParentId does not exist',
        );
      }
      if (parent.parentFieldId != null) {
        throw DepthLimitExceededException(fieldId, newParentId);
      }
      if (parent.fieldTypeId != kGroupFieldTypeId) {
        throw InvalidFieldTypeException(
          newParentId,
          'parent field $newParentId is not a group — child fields can only be nested under group-typed fields',
        );
      }
    }
    await _writePartial(fieldId, {'parent_field_id': newParentId});
  }

  @override
  Future<void> setFieldDatePrecision(
    String fieldId,
    domain.DatePrecision? newPrecision,
  ) => _writePartial(fieldId, {'date_precision': newPrecision?.index});

  @override
  Future<void> setFieldDisplayOrder(String fieldId, int newOrder) =>
      _writePartial(fieldId, {'display_order': newOrder});

  /// Sparse write: builds a partial companion from [changes] (Value.absent
  /// for every other column), writes the row, and emits a sync op with only
  /// the keys in [changes]. CRDT-safe — stale fields in memory cannot leak
  /// into the write because they're not in the map.
  ///
  /// Bails (no DB write emitted, no sync op) when the underlying row is
  /// missing or soft-deleted (`affected != 1`). Prevents phantom sync
  /// updates from a stale UI that patches a row already deleted on disk.
  /// Matches the habit-repo template at drift_habit_repository.dart:80.
  ///
  /// Also short-circuits on no-op writes (every key in [changes] already
  /// equals what's on disk). The DAO `updateField` returns `affected == 1`
  /// whenever the row exists, so without this guard rename-to-same-name,
  /// move-to-current-parent, etc. would stamp a fresh per-field HLC and
  /// clobber a peer's concurrent edit via LWW. Mirrors the diff-then-bail
  /// shape used by `drift_member_repository.updateMemberFields`.
  Future<void> _writePartial(
    String fieldId,
    Map<String, dynamic> changes,
  ) async {
    if (changes.isEmpty) return;
    final existingRow = await _dao.getFieldById(fieldId);
    if (existingRow == null) return;
    // Compare the patch keys against the on-disk values directly via
    // `fieldFieldsFromRow` — going through the domain mapper would
    // re-encode `type_config_json` through the codec and could surface
    // ordering deltas that aren't real edits. `diffSyncFields` strips
    // `is_deleted`; callers must not put that key in [changes] anyway.
    final existingFields = fieldFieldsFromRow(existingRow);
    final effective = diffSyncFields(existingFields, changes);
    if (effective.isEmpty) return;
    final companion = _partialCustomFieldCompanion(effective);
    final affected = await _dao.updateField(fieldId, companion);
    if (affected != 1) return;
    await syncRecordUpdate(_fieldsTable, fieldId, effective);
  }

  /// Validates the depth-1 cap: a field may have a parent, but that parent
  /// must not itself have a parent (no groups inside groups), and the parent
  /// must be a group-typed field.
  Future<void> _validateDepth(domain.CustomField field) async {
    final parentId = field.parentFieldId;
    if (parentId == null) return;
    final parent = await getFieldById(parentId);
    if (parent == null) {
      // Orphan-promotion handles missing parents on read.
      return;
    }
    if (parent.parentFieldId != null) {
      throw DepthLimitExceededException(field.id, parentId);
    }
    if (parent.fieldTypeId != kGroupFieldTypeId) {
      throw InvalidFieldTypeException(
        parentId,
        'parent field $parentId is not a group — child fields can only be nested under group-typed fields',
      );
    }
  }

  @override
  Future<void> reorderFields(List<domain.CustomField> fields) async {
    final displayOrders = <String, int>{};
    final changedIds = <String>[];

    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      if (field.displayOrder == i) continue;
      displayOrders[field.id] = i;
      changedIds.add(field.id);
    }

    if (displayOrders.isEmpty) return;

    await _dao.bulkUpdateDisplayOrders(displayOrders);
    for (final id in changedIds) {
      await syncRecordUpdate(_fieldsTable, id, {
        'display_order': displayOrders[id],
      });
    }
  }

  @override
  Future<void> deleteField(String id, {bool deleteChildren = false}) async {
    final field = await getFieldById(id);
    if (field == null) return; // idempotent

    if (field.fieldTypeId == kGroupFieldTypeId) {
      // Fetch all active (non-deleted) fields to find children.
      final allFields = await _allFieldsOnce();
      final children = allFields.where((f) => f.parentFieldId == id).toList();

      if (deleteChildren) {
        // Soft-delete each child individually so each emits its own sync op.
        for (final child in children) {
          await _softDeleteField(child.id);
        }
      } else {
        // Promote children to top level by clearing parent_field_id.
        // Use the patch path: emits only parent_field_id (not the full row),
        // so any concurrent edits from peers to name/typeConfig/etc. are
        // preserved. `moveFieldToParent(id, null)` skips parent validation
        // (validation only fires for non-null targets), so this cascade is
        // safe to use for internal bookkeeping.
        for (final child in children) {
          await moveFieldToParent(child.id, null);
        }
      }
    }

    await _softDeleteField(id);
  }

  /// Fetch all active (non-deleted) fields once (no stream subscription).
  Future<List<domain.CustomField>> _allFieldsOnce() => getAllFields();

  /// Soft-delete a single field and its values, emitting sync ops for each.
  Future<void> _softDeleteField(String id) async {
    // Fetch values before bulk soft-delete so we can emit sync ops for each.
    final values = await _dao.watchValuesForField(id).first;
    await _dao.deleteField(id);
    for (final value in values) {
      await syncRecordDelete(_valuesTable, value.id);
    }
    await syncRecordDelete(_fieldsTable, id);
  }

  @override
  Future<void> deleteAllFields() async {
    final captured = await _dao.softDeleteAllCustomFieldData();
    // FFI emissions live outside the transaction (can't be rolled back).
    // Value tombstones first so peers see child deletes before parents — the
    // two calls stay ordered (values get earlier HLCs than fields).
    await syncRecordDeleteMulti(_valuesTable, captured.valueIds.toList());
    await syncRecordDeleteMulti(_fieldsTable, captured.fieldIds.toList());
  }

  // ── Values ─────────────────────────────────────────────────────────

  @override
  Stream<List<domain.CustomFieldValue>> watchValuesForMember(String memberId) {
    return _dao
        .watchValuesForMember(memberId)
        .map((rows) => rows.map(CustomFieldValueMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.CustomFieldValue>> watchValuesForField(String fieldId) {
    return _dao
        .watchValuesForField(fieldId)
        .map((rows) => rows.map(CustomFieldValueMapper.toDomain).toList());
  }

  @override
  Future<List<domain.CustomFieldValue>> getAllValues() async {
    final rows = await _dao.getAllValues();
    return rows.map(CustomFieldValueMapper.toDomain).toList();
  }

  @override
  Future<domain.CustomFieldValue?> getValueForField(
    String fieldId,
    String memberId,
  ) async {
    final row = await _dao.getValueForField(fieldId, memberId);
    return row != null ? CustomFieldValueMapper.toDomain(row) : null;
  }

  @override
  Future<void> upsertValue(domain.CustomFieldValue value) async {
    final field = await getFieldById(value.customFieldId);
    if (field != null && field.fieldTypeId == kGroupFieldTypeId) {
      throw InvalidFieldTypeException(
        value.customFieldId,
        'group-typed fields cannot have per-member values',
      );
    }
    final companion = CustomFieldValueMapper.toCompanion(value);
    await _dao.upsertValue(companion);
    await syncRecordCreate(_valuesTable, value.id, _valueFields(value));
  }

  @override
  Future<void> deleteValue(String id) async {
    await _dao.deleteValue(id);
    await syncRecordDelete(_valuesTable, id);
  }

  @override
  Future<void> deleteValuesForField(String fieldId) async {
    final values = await _dao.watchValuesForField(fieldId).first;
    await _dao.deleteValuesForField(fieldId);
    for (final value in values) {
      await syncRecordDelete(_valuesTable, value.id);
    }
  }

  @override
  Future<void> deleteValuesForMember(String memberId) async {
    final values = await _dao.watchValuesForMember(memberId).first;
    await _dao.deleteValuesForMember(memberId);
    for (final value in values) {
      await syncRecordDelete(_valuesTable, value.id);
    }
  }

  // ── Sync field maps ────────────────────────────────────────────────

  Map<String, dynamic> _fieldFields(domain.CustomField f) => fieldFields(f);

  /// Field-map builder for custom-field sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createField()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> fieldFields(domain.CustomField f) {
    String? typeConfigJson;
    if (f.typeConfig != null) {
      typeConfigJson = jsonEncode(
        CustomFieldTypeConfigCodec.toJson(f.typeConfig!),
      );
    } else if (f.unknownTypeConfigRaw != null) {
      // Preserve raw bytes for fully unrecognized future variants.
      typeConfigJson = f.unknownTypeConfigRaw;
    }
    return {
      'name': f.name,
      'field_type': f.fieldType.index,
      'field_type_id': f.fieldTypeId,
      'parent_field_id': f.parentFieldId,
      'type_config_json': typeConfigJson,
      'date_precision': f.datePrecision?.index,
      'display_order': f.displayOrder,
      'created_at': f.createdAt.toUtc().toIso8601String(),
      'is_deleted': false,
    };
  }

  /// Companion to [fieldFields] that reads from a raw Drift row instead of
  /// the domain object. Used by [updateField] to compute the prev field map
  /// for `diffSyncFields`. Mirror the column order/types of [fieldFields].
  static Map<String, dynamic> fieldFieldsFromRow(db.CustomFieldRow r) {
    return {
      'name': r.name,
      'field_type': r.fieldType,
      'field_type_id': r.fieldTypeId,
      'parent_field_id': r.parentFieldId,
      'type_config_json': r.typeConfigJson,
      'date_precision': r.datePrecision,
      'display_order': r.displayOrder,
      'created_at': r.createdAt.toUtc().toIso8601String(),
      'is_deleted': r.isDeleted,
    };
  }

  /// Builds a partial [db.CustomFieldsCompanion] containing only the
  /// columns named in [fields]. Every other column is `Value.absent()`,
  /// which Drift leaves untouched on `update().write()`. Critical for
  /// CRDT correctness: stale fields in any in-memory snapshot cannot
  /// leak into the on-disk row.
  db.CustomFieldsCompanion _partialCustomFieldCompanion(
    Map<String, dynamic> fields,
  ) {
    return db.CustomFieldsCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      fieldType: fields.containsKey('field_type')
          ? Value(fields['field_type'] as int)
          : const Value.absent(),
      fieldTypeId: fields.containsKey('field_type_id')
          ? Value(fields['field_type_id'] as String?)
          : const Value.absent(),
      parentFieldId: fields.containsKey('parent_field_id')
          ? Value(fields['parent_field_id'] as String?)
          : const Value.absent(),
      typeConfigJson: fields.containsKey('type_config_json')
          ? Value(fields['type_config_json'] as String?)
          : const Value.absent(),
      datePrecision: fields.containsKey('date_precision')
          ? Value(fields['date_precision'] as int?)
          : const Value.absent(),
      displayOrder: fields.containsKey('display_order')
          ? Value(fields['display_order'] as int)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(DateTime.parse(fields['created_at'] as String))
          : const Value.absent(),
      isDeleted: fields.containsKey('is_deleted')
          ? Value(fields['is_deleted'] as bool)
          : const Value.absent(),
    );
  }

  /// Single write path for typeConfig mutations.
  ///
  /// Whole-config LWW invariant: any config mutation writes the entire blob.
  /// No field-level merge inside the JSON. CRDT convergence depends on this.
  ///
  /// Part of the public [CustomFieldsRepository] interface so BATCH 2+
  /// choice-config UI can use the whole-config LWW write path directly.
  @override
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  ) async {
    // Patch-style: writes only type_config_json. Other columns untouched
    // on disk; sync emits only the config key. Stale parent/name/etc. in
    // any concurrent UI snapshot cannot leak into the write.
    final json = jsonEncode(CustomFieldTypeConfigCodec.toJson(newConfig));
    await _writePartial(fieldId, {'type_config_json': json});
  }

  @override
  Future<void> clearTypedConfig(String fieldId) async {
    // Patch-style null write — mirrors setFieldDatePrecision(null). The
    // no-op short-circuit in _writePartial means clearing an already-null
    // config emits nothing.
    await _writePartial(fieldId, {'type_config_json': null});
  }

  Map<String, dynamic> _valueFields(domain.CustomFieldValue v) =>
      valueFields(v);

  /// Field-map builder for custom-field-value sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `upsertValue()` for the bulk insert.
  static Map<String, dynamic> valueFields(domain.CustomFieldValue v) {
    return {
      'custom_field_id': v.customFieldId,
      'member_id': v.memberId,
      'value': v.value,
      'is_deleted': false,
    };
  }
}
