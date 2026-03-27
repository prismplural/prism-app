import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_value_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_value.dart' as domain;
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
    return _dao
        .watchAllFields()
        .map((rows) => rows.map(CustomFieldMapper.toDomain).toList());
  }

  @override
  Stream<domain.CustomField?> watchFieldById(String id) {
    return _dao.watchFieldById(id).map(
        (row) => row != null ? CustomFieldMapper.toDomain(row) : null);
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
    final companion = CustomFieldMapper.toCompanion(field);
    await _dao.updateField(field.id, companion);
    await syncRecordUpdate(_fieldsTable, field.id, _fieldFields(field));
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
  Stream<List<domain.CustomFieldValue>> watchValuesForMember(
      String memberId) {
    return _dao
        .watchValuesForMember(memberId)
        .map((rows) => rows.map(CustomFieldValueMapper.toDomain).toList());
  }

  @override
  Future<List<domain.CustomFieldValue>> getAllValues() async {
    final rows = await _dao.getAllValues();
    return rows.map(CustomFieldValueMapper.toDomain).toList();
  }

  @override
  Future<domain.CustomFieldValue?> getValueForField(
      String fieldId, String memberId) async {
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
    await _dao.deleteValuesForField(fieldId);
  }

  @override
  Future<void> deleteValuesForMember(String memberId) async {
    await _dao.deleteValuesForMember(memberId);
  }

  // ── Sync field maps ────────────────────────────────────────────────

  Map<String, dynamic> _fieldFields(domain.CustomField f) {
    return {
      'name': f.name,
      'field_type': f.fieldType.index,
      'date_precision': f.datePrecision?.index,
      'display_order': f.displayOrder,
      'created_at': f.createdAt.toIso8601String(),
      'is_deleted': false,
    };
  }

  Map<String, dynamic> _valueFields(domain.CustomFieldValue v) {
    return {
      'custom_field_id': v.customFieldId,
      'member_id': v.memberId,
      'value': v.value,
      'is_deleted': false,
    };
  }
}
