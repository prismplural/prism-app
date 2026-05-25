import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — long_text has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

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
  allowsTextualSwitch: true,
);
