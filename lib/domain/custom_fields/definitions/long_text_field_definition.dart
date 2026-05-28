import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — long_text uses LongTextConfig.
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
// Value parser/encoder — long_text stores a plain string (same shape as text).
// ---------------------------------------------------------------------------

TypedFieldValue _longTextParser(String? raw) =>
    TypedFieldValue.longText(raw ?? '');

String _longTextEncoder(TypedFieldValue value) {
  if (value is LongTextFieldValue) return value.value;
  return '';
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart.
// ---------------------------------------------------------------------------

final longTextFieldDefinition = CustomFieldTypeDefinition(
  id: 'long_text',
  legacyIntValue: 3,
  labelL10nKey: 'customFieldTypeLongText',
  icon: AppIcons.notes,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _longTextParser,
  valueEncoder: _longTextEncoder,
  allowsTextualSwitch: true,
);
