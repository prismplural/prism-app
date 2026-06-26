import 'package:drift/drift.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/data/repositories/preference_value_decoding.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';
import 'package:prism_plurality/domain/repositories/app_preference_repository.dart';

class DriftAppPreferenceRepository
    with SyncRecordMixin
    implements AppPreferenceRepository {
  DriftAppPreferenceRepository(
    this._dao,
    this._syncHandle, {
    PreferenceCapabilityGate? capabilityGate,
  }) : _capabilityGate = capabilityGate;

  final PreferenceValuesDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;
  final PreferenceCapabilityGate? _capabilityGate;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'app_preference_values';

  @override
  Stream<T> watch<T>(PreferenceDefinition<T> definition) {
    _assertScope(definition);
    final key = PreferenceEntityId.app(definition.key);
    return _dao
        .watchAppValue(key)
        .map(
          (row) => row == null
              ? definition.defaultValue
              : decodePreferenceValue(
                  definition: definition,
                  valueType: row.valueType,
                  valueJson: row.valueJson,
                  isDeleted: row.isDeleted,
                ),
        );
  }

  @override
  Stream<T?> watchStored<T>(PreferenceDefinition<T> definition) {
    _assertScope(definition);
    final key = PreferenceEntityId.app(definition.key);
    return _dao
        .watchAppValue(key)
        .map(
          (row) => row == null
              ? null
              : decodeStoredPreferenceValue(
                  definition: definition,
                  valueType: row.valueType,
                  valueJson: row.valueJson,
                  isDeleted: row.isDeleted,
                ),
        );
  }

  @override
  Future<T> get<T>(PreferenceDefinition<T> definition) async {
    _assertScope(definition);
    final key = PreferenceEntityId.app(definition.key);
    final row = await _dao.getAppValue(key);
    if (row == null) return definition.defaultValue;
    return decodePreferenceValue(
      definition: definition,
      valueType: row.valueType,
      valueJson: row.valueJson,
      isDeleted: row.isDeleted,
    );
  }

  @override
  Future<T?> getStored<T>(PreferenceDefinition<T> definition) async {
    _assertScope(definition);
    final key = PreferenceEntityId.app(definition.key);
    final row = await _dao.getAppValue(key);
    if (row == null) return null;
    return decodeStoredPreferenceValue(
      definition: definition,
      valueType: row.valueType,
      valueJson: row.valueJson,
      isDeleted: row.isDeleted,
    );
  }

  @override
  Future<void> set<T>(PreferenceDefinition<T> definition, T value) async {
    _assertScope(definition);
    _assertCanWrite(definition);
    final key = PreferenceEntityId.app(definition.key);
    final valueJson = encodePreferenceValue(definition, value);
    final existing = await _dao.getAppValue(key);
    await _dao.upsertAppValue(
      AppPreferenceValuesCompanion.insert(
        key: key,
        valueType: definition.codec.valueType,
        valueJson: Value(valueJson),
        isDeleted: const Value(false),
      ),
    );
    final fields = _appPreferenceValueFields(
      valueType: definition.codec.valueType,
      valueJson: valueJson,
      isDeleted: false,
    );
    if (existing == null || existing.isDeleted) {
      await syncRecordCreate(_table, key, fields);
    } else {
      final previousFields = _appPreferenceValueFields(
        valueType: existing.valueType,
        valueJson: existing.valueJson,
        isDeleted: existing.isDeleted,
      );
      final changedFields = diffSyncFields(previousFields, fields);
      if (changedFields.isNotEmpty) {
        await syncRecordUpdate(_table, key, changedFields);
      }
    }
  }

  @override
  Future<void> reset<T>(PreferenceDefinition<T> definition) async {
    _assertScope(definition);
    _assertCanWrite(definition);
    final key = PreferenceEntityId.app(definition.key);
    await _dao.upsertAppValue(
      AppPreferenceValuesCompanion.insert(
        key: key,
        valueType: definition.codec.valueType,
        valueJson: const Value(null),
        isDeleted: const Value(true),
      ),
    );
    await syncRecordDelete(_table, key);
  }

  static Map<String, dynamic> appPreferenceValueFields({
    required String valueType,
    required String? valueJson,
    required bool isDeleted,
  }) {
    return {
      'value_type': valueType,
      'value_json': valueJson,
      'is_deleted': isDeleted,
    };
  }

  Map<String, dynamic> _appPreferenceValueFields({
    required String valueType,
    required String? valueJson,
    required bool isDeleted,
  }) {
    return {
      'value_type': valueType,
      'value_json': valueJson,
      'is_deleted': isDeleted,
    };
  }

  void _assertScope(PreferenceDefinition<dynamic> definition) {
    if (definition.scope != PreferenceScope.appSynced) {
      throw StateError('Preference ${definition.key} is not app-scoped.');
    }
  }

  void _assertCanWrite(PreferenceDefinition<dynamic> definition) {
    final capability = definition.minReaderCapability;
    if (capability == null) return;
    final gate = _capabilityGate;
    if (gate != null && gate.canWrite(definition)) return;
    throw PreferenceCapabilityException(definition.key, capability);
  }
}
