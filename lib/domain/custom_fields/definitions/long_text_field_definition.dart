import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — long_text has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

// ---------------------------------------------------------------------------
// Editor builder
// ---------------------------------------------------------------------------

Widget _buildLongTextEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return FieldInputWidget(field: field, memberId: memberId, existingValue: value);
}

// ---------------------------------------------------------------------------
// Display builders
// ---------------------------------------------------------------------------

Widget _buildLongTextDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldLongTextPreview(title: field.name, data: value.value);
}

Widget _buildLongTextCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldLongTextPreview(title: field.name, data: value.value);
}

// ---------------------------------------------------------------------------
// Definition constant
// ---------------------------------------------------------------------------

final longTextFieldDefinition = CustomFieldTypeDefinition(
  id: 'long_text',
  legacyIntValue: 3,
  labelL10nKey: 'customFieldTypeLongText',
  icon: AppIcons.notes,
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  editorBuilder: _buildLongTextEditor,
  displayBuilder: _buildLongTextDisplay,
  compactBuilder: _buildLongTextCompact,
  allowsTextualSwitch: true,
);
