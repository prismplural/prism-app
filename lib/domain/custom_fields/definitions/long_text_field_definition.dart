import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — long_text has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

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
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  valueParser: _longTextParser,
  valueEncoder: _longTextEncoder,
  allowsTextualSwitch: true,
);
