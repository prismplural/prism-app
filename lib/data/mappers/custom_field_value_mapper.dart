import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart' as domain;

class CustomFieldValueMapper {
  CustomFieldValueMapper._();

  static domain.CustomFieldValue toDomain(CustomFieldValueRow row) {
    return domain.CustomFieldValue(
      id: row.id,
      customFieldId: row.customFieldId,
      memberId: row.memberId,
      value: row.value,
    );
  }

  static CustomFieldValuesCompanion toCompanion(
      domain.CustomFieldValue model) {
    return CustomFieldValuesCompanion(
      id: Value(model.id),
      customFieldId: Value(model.customFieldId),
      memberId: Value(model.memberId),
      value: Value(model.value),
    );
  }
}
