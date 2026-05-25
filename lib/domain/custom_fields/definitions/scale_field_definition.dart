import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — scale uses ScaleConfig.
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
// Value parser/encoder — scale stores an integer 1..N as a string.
// Per-member value: Integer 1..N as a string, e.g. "4". Empty = unset.
// ---------------------------------------------------------------------------

TypedFieldValue _parse(String? raw) {
  if (raw == null || raw.isEmpty) return const ScaleFieldValue();
  final n = int.tryParse(raw.trim());
  if (n == null) return const ScaleFieldValue(); // malformed → empty
  if (n <= 0) return const ScaleFieldValue(); // out of range (1..N) → empty
  return ScaleFieldValue(step: n);
}

String _encode(TypedFieldValue value) {
  if (value is! ScaleFieldValue) return '';
  final step = value.step;
  if (step == null || step < 1) return '';
  return step.toString();
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart
// (added in Task 12).
// ---------------------------------------------------------------------------

final scaleFieldDefinition = CustomFieldTypeDefinition(
  id: 'scale',
  legacyIntValue: 6,
  labelL10nKey: 'customFieldTypeScale',
  // starOutline (PhosphorIcons.star()) is the best semantic fit for a
  // rating/intensity scale type.
  icon: AppIcons.starOutline,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _parse,
  valueEncoder: _encode,
);
