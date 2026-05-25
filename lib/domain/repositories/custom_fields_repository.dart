import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;

abstract class CustomFieldsRepository {
  Stream<List<domain.CustomField>> watchAllFields();
  Stream<domain.CustomField?> watchFieldById(String id);
  Future<domain.CustomField?> getFieldById(String id);
  Future<void> createField(domain.CustomField field);
  Future<void> updateField(domain.CustomField field);
  Future<void> reorderFields(List<domain.CustomField> fields);
  Future<void> deleteField(String id);

  Stream<List<domain.CustomFieldValue>> watchValuesForMember(String memberId);
  Stream<List<domain.CustomFieldValue>> watchValuesForField(String fieldId);
  Future<List<domain.CustomFieldValue>> getAllValues();
  Future<domain.CustomFieldValue?> getValueForField(
    String fieldId,
    String memberId,
  );
  Future<void> upsertValue(domain.CustomFieldValue value);
  Future<void> deleteValue(String id);
  Future<void> deleteValuesForField(String fieldId);
  Future<void> deleteValuesForMember(String memberId);

  /// Write a whole-config blob for [fieldId] using the LWW (last-write-wins)
  /// invariant: any config mutation writes the entire blob. No field-level
  /// merge inside the JSON. CRDT convergence depends on this contract.
  ///
  /// First callers land in BATCH 2 (choice option mutations) and beyond.
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  );
}
