import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

class CustomFieldMapper {
  CustomFieldMapper._();

  /// Convert a Drift row to a domain CustomField.
  ///
  /// Prefers `field_type_id` over the legacy int when both are present.
  /// Falls back to the int → string registry lookup when `field_type_id`
  /// is null (v27 rows backfilled by the v27→v28 migration set it, but
  /// extra defense doesn't hurt).
  ///
  /// New types written by v28+ also write a real int (4..7) to field_type
  /// for v27 reader graceful-degradation — v27 falls through the existing
  /// out-of-range guard and renders the row as text. The raw value +
  /// typeConfigJson are silently preserved in storage and re-emitted on sync.
  static domain.CustomField toDomain(CustomFieldRow row) {
    final fieldTypeId = row.fieldTypeId ??
        _legacyIntToId(row.fieldType) ??
        'text';

    // Parse typeConfigJson via the codec wrapper so unknown forward-compat
    // keys are preserved in the variant's extra map.
    CustomFieldTypeConfig? typeConfig;
    final rawConfig = row.typeConfigJson;
    if (rawConfig != null && rawConfig.isNotEmpty) {
      try {
        final json = jsonDecode(rawConfig) as Map<String, dynamic>;
        typeConfig = CustomFieldTypeConfigCodec.fromJson(json);
      } catch (_) {
        // Malformed config — leave null. The raw column is still preserved
        // for sync re-emit by readRow elsewhere.
      }
    }

    final domainFieldType =
        row.fieldType < domain.CustomFieldType.values.length
            ? domain.CustomFieldType.values[row.fieldType]
            : domain.CustomFieldType.text;

    return domain.CustomField(
      id: row.id,
      name: row.name,
      fieldType: domainFieldType,
      datePrecision: row.datePrecision != null &&
              row.datePrecision! < domain.DatePrecision.values.length
          ? domain.DatePrecision.values[row.datePrecision!]
          : null,
      displayOrder: row.displayOrder,
      createdAt: row.createdAt,
      fieldTypeId: fieldTypeId,
      parentFieldId: row.parentFieldId,
      typeConfig: typeConfig,
    );
  }

  static CustomFieldsCompanion toCompanion(domain.CustomField model) {
    // Serialize typeConfig through the codec for forward-compat extra-key preservation.
    String? typeConfigJson;
    if (model.typeConfig != null) {
      final jsonMap = CustomFieldTypeConfigCodec.toJson(model.typeConfig!);
      typeConfigJson = jsonEncode(jsonMap);
    }

    return CustomFieldsCompanion(
      id: Value(model.id),
      name: Value(model.name),
      fieldType: Value(model.fieldType.index),
      fieldTypeId: Value(model.fieldTypeId),
      datePrecision: Value(model.datePrecision?.index),
      displayOrder: Value(model.displayOrder),
      createdAt: Value(model.createdAt),
      parentFieldId: Value(model.parentFieldId),
      typeConfigJson: Value(typeConfigJson),
    );
  }

  /// Fallback: map legacy int field_type → stable string ID for pre-migration
  /// rows where field_type_id was not yet stored.
  ///
  /// The v27→v28 migration backfills field_type_id for all rows, so this path
  /// is only hit defensively. Delegates to the registry now that registry.dart
  /// is pure Dart (no widget/provider transitive dependencies after Fix 1).
  static String? _legacyIntToId(int legacyInt) {
    return customFieldTypeRegistry.lookupByLegacyInt(legacyInt)?.id;
  }
}
