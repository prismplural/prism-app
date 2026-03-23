import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_value.dart' as domain;

abstract class CustomFieldsRepository {
  Stream<List<domain.CustomField>> watchAllFields();
  Stream<domain.CustomField?> watchFieldById(String id);
  Future<domain.CustomField?> getFieldById(String id);
  Future<void> createField(domain.CustomField field);
  Future<void> updateField(domain.CustomField field);
  Future<void> deleteField(String id);

  Stream<List<domain.CustomFieldValue>> watchValuesForMember(String memberId);
  Future<domain.CustomFieldValue?> getValueForField(
      String fieldId, String memberId);
  Future<void> upsertValue(domain.CustomFieldValue value);
  Future<void> deleteValue(String id);
  Future<void> deleteValuesForField(String fieldId);
  Future<void> deleteValuesForMember(String memberId);
}
