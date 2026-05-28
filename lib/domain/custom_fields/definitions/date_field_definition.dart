import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — date uses DateConfig.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _configFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  try {
    return CustomFieldTypeConfigCodec.fromJson(json);
  } catch (_) {
    // Malformed / missing discriminator (e.g. "{}") → no typed config.
    // The mapper preserves the raw bytes via unknownTypeConfigRaw separately.
    return null;
  }
}

Map<String, dynamic>? _configToJson(CustomFieldTypeConfig? config) {
  if (config == null) return null;
  return CustomFieldTypeConfigCodec.toJson(config);
}

// ---------------------------------------------------------------------------
// Value parser/encoder — date stores an ISO 8601 string; absent/malformed → null.
// ---------------------------------------------------------------------------

TypedFieldValue _dateParser(String? raw) {
  if (raw == null || raw.isEmpty) return const TypedFieldValue.date();
  try {
    return TypedFieldValue.date(value: DateTime.parse(raw));
  } catch (_) {
    return const TypedFieldValue.date();
  }
}

String _dateEncoder(TypedFieldValue value) {
  if (value is DateFieldValue) return value.value?.toIso8601String() ?? '';
  return '';
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart.
// ---------------------------------------------------------------------------

final dateFieldDefinition = CustomFieldTypeDefinition(
  id: 'date',
  legacyIntValue: 2,
  labelL10nKey: 'customFieldTypeDate',
  icon: AppIcons.calendarToday,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _dateParser,
  valueEncoder: _dateEncoder,
);
