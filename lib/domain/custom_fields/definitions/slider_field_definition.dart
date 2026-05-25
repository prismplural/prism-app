import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — slider uses SliderConfig.
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
// Value parser/encoder — slider stores a double as a string.
// Labeled mode stores an int 0..100; numeric mode stores the domain value.
// Mode is on the field config, not the value — we parse as double regardless.
// Empty = unset.
// ---------------------------------------------------------------------------

TypedFieldValue _parse(String? raw) {
  if (raw == null || raw.isEmpty) return const SliderFieldValue();
  final d = double.tryParse(raw.trim());
  if (d == null) return const SliderFieldValue();
  return SliderFieldValue(value: d);
}

String _encode(TypedFieldValue value) {
  if (value is! SliderFieldValue) return '';
  final v = value.value;
  if (v == null) return '';
  // For integer-valued doubles, emit without decimal point.
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart
// (added in Task 14).
// ---------------------------------------------------------------------------

final sliderFieldDefinition = CustomFieldTypeDefinition(
  id: 'slider',
  legacyIntValue: 7,
  labelL10nKey: 'customFieldTypeSlider',
  // tuneOutlined (PhosphorIcons.sliders) is the best semantic fit for a
  // slider/spectrum field type.
  icon: AppIcons.tuneOutlined,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _parse,
  valueEncoder: _encode,
);
