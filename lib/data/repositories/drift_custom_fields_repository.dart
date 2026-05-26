import 'package:drift/drift.dart' show Value;
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_value_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
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
    return _dao.watchAllFields().map(
      (rows) => rows.map(CustomFieldMapper.toDomain).toList(),
    );
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
    final companion = CustomFieldMapper.toCompanion(field);
    await _dao.createField(companion);
    await syncRecordCreate(_fieldsTable, field.id, _fieldFields(field));
  }

  @override
  Future<void> updateField(domain.CustomField field) async {
    // Residual risk (out of scope of this migration): the read-side
    // orphan-promotion transform in
    // `lib/data/mappers/custom_field_mapper.dart` (line 10) coerces unknown
    // `fieldType` integers to `text`. If a peer writes a fieldType this
    // device doesn't know yet, this device will silently emit a "change" to
    // text via the diff below. Both whole-row and diff paths emit the
    // promoted value identically under per-field LWW; fix tracked separately.
    final existingRow = await _dao.getFieldById(field.id);
    if (existingRow == null || existingRow.isDeleted) return;

    final changedFields = diffSyncFields(
      _fieldFieldsFromRow(existingRow),
      _fieldFields(field),
    );
    if (changedFields.isEmpty) return;

    final companion = _partialFieldCompanion(changedFields);
    await _dao.updateField(field.id, companion);
    await syncRecordUpdate(_fieldsTable, field.id, changedFields);
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
  Future<void> deleteField(String id) async {
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

  CustomFieldsCompanion _partialFieldCompanion(Map<String, dynamic> fields) {
    return CustomFieldsCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      fieldType: fields.containsKey('field_type')
          ? Value(fields['field_type'] as int)
          : const Value.absent(),
      datePrecision: fields.containsKey('date_precision')
          ? Value(fields['date_precision'] as int?)
          : const Value.absent(),
      displayOrder: fields.containsKey('display_order')
          ? Value(fields['display_order'] as int)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
    );
  }

  Map<String, dynamic> _fieldFieldsFromRow(CustomFieldRow row) {
    return {
      'name': row.name,
      'field_type': row.fieldType,
      'date_precision': row.datePrecision,
      'display_order': row.displayOrder,
      'created_at': toSyncUtc(row.createdAt),
      'is_deleted': row.isDeleted,
    };
  }

  Map<String, dynamic> _fieldFields(domain.CustomField f) => fieldFields(f);

  /// Field-map builder for custom-field sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createField()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> fieldFields(domain.CustomField f) {
    return {
      'name': f.name,
      'field_type': f.fieldType.index,
      'date_precision': f.datePrecision?.index,
      'display_order': f.displayOrder,
      'created_at': f.createdAt.toUtc().toIso8601String(),
      'is_deleted': false,
    };
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
