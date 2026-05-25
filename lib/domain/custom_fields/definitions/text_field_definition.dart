import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — text has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

// ---------------------------------------------------------------------------
// Value parser/encoder — text stores a plain string.
// ---------------------------------------------------------------------------

TypedFieldValue _textParser(String? raw) => TypedFieldValue.text(raw ?? '');

String _textEncoder(TypedFieldValue value) {
  if (value is TextFieldValue) return value.value;
  return '';
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart.
// ---------------------------------------------------------------------------

final textFieldDefinition = CustomFieldTypeDefinition(
  id: 'text',
  legacyIntValue: 0,
  labelL10nKey: 'customFieldTypeShortText',
  icon: AppIcons.textFields,
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  valueParser: _textParser,
  valueEncoder: _textEncoder,
  allowsTextualSwitch: true,
);
