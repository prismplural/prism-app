import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — group uses GroupConfig.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _configFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  return CustomFieldTypeConfigCodec.fromJson(json);
}

Map<String, dynamic>? _configToJson(CustomFieldTypeConfig? config) {
  if (config == null) return null;
  return CustomFieldTypeConfigCodec.toJson(config);
}

// ---------------------------------------------------------------------------
// Value parser/encoder — groups have no per-member value.
// ---------------------------------------------------------------------------

// Group has no per-member value. Defensive parser/encoder.
TypedFieldValue _parse(String? raw) {
  // A value should never be set for a group field, but if one slipped
  // through (race / future-version-feature), surface as Unsupported
  // rather than crash.
  if (raw == null || raw.isEmpty) return const UnsupportedFieldValue('');
  return UnsupportedFieldValue(raw);
}

String _encode(TypedFieldValue value) {
  // No-op — groups don't store per-member values. Repository.upsertValue
  // rejects writes for group-typed fields.
  return '';
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart
// (added in Task 10).
// ---------------------------------------------------------------------------

final groupFieldDefinition = CustomFieldTypeDefinition(
  id: 'group',
  legacyIntValue: 5, // back-compat int for v27 readers; never extends the enum
  labelL10nKey: 'customFieldTypeGroup',
  // folderOutlined (PhosphorIcons.folder) is the best semantic fit for a
  // structural container of child fields.
  icon: AppIcons.folderOutlined,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _parse,
  valueEncoder: _encode,
);
