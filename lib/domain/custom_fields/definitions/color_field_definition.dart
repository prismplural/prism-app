import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — color has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

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
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  valueParser: _colorParser,
  valueEncoder: _colorEncoder,
);
