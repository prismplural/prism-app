import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;

class CustomFieldMapper {
  CustomFieldMapper._();

  static domain.CustomField toDomain(CustomFieldRow row) {
    return domain.CustomField(
      id: row.id,
      name: row.name,
      fieldType: row.fieldType < domain.CustomFieldType.values.length
          ? domain.CustomFieldType.values[row.fieldType]
          : domain.CustomFieldType.text,
      datePrecision: row.datePrecision != null &&
              row.datePrecision! < domain.DatePrecision.values.length
          ? domain.DatePrecision.values[row.datePrecision!]
          : null,
      displayOrder: row.displayOrder,
      createdAt: row.createdAt,
    );
  }

  static CustomFieldsCompanion toCompanion(domain.CustomField model) {
    return CustomFieldsCompanion(
      id: Value(model.id),
      name: Value(model.name),
      fieldType: Value(model.fieldType.index),
      datePrecision: Value(model.datePrecision?.index),
      displayOrder: Value(model.displayOrder),
      createdAt: Value(model.createdAt),
    );
  }
}
