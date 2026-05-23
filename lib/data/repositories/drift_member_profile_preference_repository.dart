import 'package:drift/drift.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/data/repositories/preference_value_decoding.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/domain/preferences/preference_definition.dart';
import 'package:prism_plurality/domain/preferences/preference_entity_id.dart';
import 'package:prism_plurality/domain/repositories/member_profile_preference_repository.dart';

class DriftMemberProfilePreferenceRepository
    with SyncRecordMixin
    implements MemberProfilePreferenceRepository {
  DriftMemberProfilePreferenceRepository(
    this._dao,
    this._syncHandle, {
    PreferenceCapabilityGate? capabilityGate,
  }) : _capabilityGate = capabilityGate;

  final PreferenceValuesDao _dao;
  final ffi.PrismSyncHandle? _syncHandle;
  final PreferenceCapabilityGate? _capabilityGate;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _table = 'member_profile_preference_values';

  @override
  Stream<T> watch<T>(String memberId, PreferenceDefinition<T> definition) {
    _assertScope(definition);
    final id = PreferenceEntityId.memberProfile(memberId, definition.key);
    return _dao
        .watchMemberProfileValue(id)
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
  Future<T> get<T>(String memberId, PreferenceDefinition<T> definition) async {
    _assertScope(definition);
    final id = PreferenceEntityId.memberProfile(memberId, definition.key);
    final row = await _dao.getMemberProfileValue(id);
    if (row == null) return definition.defaultValue;
    return decodePreferenceValue(
      definition: definition,
      valueType: row.valueType,
      valueJson: row.valueJson,
      isDeleted: row.isDeleted,
    );
  }

  @override
  Future<void> set<T>(
    String memberId,
    PreferenceDefinition<T> definition,
    T value,
  ) async {
    _assertScope(definition);
    _assertCanWrite(definition);
    if (!await _dao.memberExists(memberId)) {
      throw StateError('Cannot write preference for missing member $memberId.');
    }

    final id = PreferenceEntityId.memberProfile(memberId, definition.key);
    final valueJson = encodePreferenceValue(definition, value);
    final existing = await _dao.getMemberProfileValue(id);
    await _dao.upsertMemberProfileValue(
      MemberProfilePreferenceValuesCompanion.insert(
        id: id,
        memberId: memberId,
        key: definition.key,
        valueType: definition.codec.valueType,
        valueJson: Value(valueJson),
        isDeleted: const Value(false),
      ),
    );
    final fields = _memberProfilePreferenceValueFields(
      memberId: memberId,
      key: definition.key,
      valueType: definition.codec.valueType,
      valueJson: valueJson,
      isDeleted: false,
    );
    if (existing == null || existing.isDeleted) {
      await syncRecordCreate(_table, id, fields);
    } else {
      final previousFields = _memberProfilePreferenceValueFields(
        memberId: existing.memberId,
        key: existing.key,
        valueType: existing.valueType,
        valueJson: existing.valueJson,
        isDeleted: existing.isDeleted,
      );
      final changedFields = diffSyncFields(previousFields, fields);
      if (changedFields.isNotEmpty) {
        await syncRecordUpdate(_table, id, changedFields);
      }
    }
  }

  @override
  Future<void> reset<T>(
    String memberId,
    PreferenceDefinition<T> definition,
  ) async {
    _assertScope(definition);
    _assertCanWrite(definition);
    if (!await _dao.memberExists(memberId)) {
      throw StateError('Cannot reset preference for missing member $memberId.');
    }

    final id = PreferenceEntityId.memberProfile(memberId, definition.key);
    await _dao.upsertMemberProfileValue(
      MemberProfilePreferenceValuesCompanion.insert(
        id: id,
        memberId: memberId,
        key: definition.key,
        valueType: definition.codec.valueType,
        valueJson: const Value(null),
        isDeleted: const Value(true),
      ),
    );
    await syncRecordDelete(_table, id);
  }

  @override
  Future<void> resetAllForMember(String memberId) async {
    final rows = await _dao.allMemberProfileValuesForMember(memberId);
    if (rows.isEmpty) return;

    await _dao.tombstoneAllMemberProfileValues(memberId);
    for (final row in rows) {
      await syncRecordDelete(_table, row.id);
    }
  }

  static Map<String, dynamic> memberProfilePreferenceValueFields({
    required String memberId,
    required String key,
    required String valueType,
    required String? valueJson,
    required bool isDeleted,
  }) {
    return {
      'member_id': memberId,
      'key': key,
      'value_type': valueType,
      'value_json': valueJson,
      'is_deleted': isDeleted,
    };
  }

  Map<String, dynamic> _memberProfilePreferenceValueFields({
    required String memberId,
    required String key,
    required String valueType,
    required String? valueJson,
    required bool isDeleted,
  }) {
    return {
      'member_id': memberId,
      'key': key,
      'value_type': valueType,
      'value_json': valueJson,
      'is_deleted': isDeleted,
    };
  }

  void _assertScope(PreferenceDefinition<dynamic> definition) {
    if (definition.scope != PreferenceScope.memberProfileSynced) {
      throw StateError(
        'Preference ${definition.key} is not member-profile-scoped.',
      );
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
