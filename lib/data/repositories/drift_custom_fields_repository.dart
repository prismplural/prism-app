import 'dart:convert';

import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_value_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
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
    return _dao.watchAllFields().map((rows) {
      final fields = rows.map(CustomFieldMapper.toDomain).toList();
      // Orphan-on-read promotion: the DAO filters isDeleted==false, so every
      // id in this list is an active field. A child whose parent is absent
      // from this list (missing or soft-deleted) renders at top level.
      // This is an IN-MEMORY transformation only — the DB row keeps its
      // parent_field_id so the child re-attaches naturally on the next
      // stream emission if the parent comes back via sync.
      final activeIds = fields.map((f) => f.id).toSet();
      return fields.map((f) {
        final parentId = f.parentFieldId;
        if (parentId == null) return f;
        if (!activeIds.contains(parentId)) {
          // Orphaned: parent missing or soft-deleted → render at top level.
          return f.copyWith(parentFieldId: null);
        }
        return f;
      }).toList();
    });
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
    await _validateDepth(field);
    final companion = CustomFieldMapper.toCompanion(field);
    await _dao.createField(companion);
    await syncRecordCreate(_fieldsTable, field.id, _fieldFields(field));
  }

  @override
  Future<void> updateField(domain.CustomField field) async {
    await _validateDepth(field);
    final companion = CustomFieldMapper.toCompanion(field);
    await _dao.updateField(field.id, companion);
    await syncRecordUpdate(_fieldsTable, field.id, _fieldFields(field));
  }

  /// Validates the depth-1 cap: a field may have a parent, but that parent
  /// must not itself have a parent (no groups inside groups).
  Future<void> _validateDepth(domain.CustomField field) async {
    final parentId = field.parentFieldId;
    if (parentId == null) return;
    final parent = await getFieldById(parentId);
    if (parent != null && parent.parentFieldId != null) {
      throw DepthLimitExceededException(field.id, parentId);
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

    if (field.fieldTypeId == 'group') {
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
        for (final child in children) {
          await updateField(child.copyWith(parentFieldId: null));
        }
      }
    }

    await _softDeleteField(id);
  }

  /// Fetch all active (non-deleted) fields once (no stream subscription).
  Future<List<domain.CustomField>> _allFieldsOnce() async {
    final rows = await _dao.watchAllFields().first;
    return rows.map(CustomFieldMapper.toDomain).toList();
  }

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
    if (field != null && field.fieldTypeId == 'group') {
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
      typeConfigJson =
          jsonEncode(CustomFieldTypeConfigCodec.toJson(f.typeConfig!));
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
    final existing = await getFieldById(fieldId);
    if (existing == null) {
      throw StateError('Cannot write config for missing field $fieldId');
    }
    final updated = existing.copyWith(typeConfig: newConfig);
    await updateField(updated);
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
