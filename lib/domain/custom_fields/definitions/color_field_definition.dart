import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — color uses ColorConfig.
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
// Value parser/encoder — color stores an optional hex string (e.g. '#ff00aa').
// ---------------------------------------------------------------------------

TypedFieldValue _colorParser(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return const TypedFieldValue.color();
  return TypedFieldValue.color(hex: trimmed);
}

String _colorEncoder(TypedFieldValue value) {
  if (value is ColorFieldValue) return value.hex ?? '';
  return '';
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart.
// ---------------------------------------------------------------------------

final colorFieldDefinition = CustomFieldTypeDefinition(
  id: 'color',
  legacyIntValue: 1,
  labelL10nKey: 'customFieldTypeColor',
  icon: AppIcons.palette,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _colorParser,
  valueEncoder: _colorEncoder,
);
