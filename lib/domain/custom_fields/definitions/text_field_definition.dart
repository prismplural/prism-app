import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — text has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

// ---------------------------------------------------------------------------
// Editor builder
// ---------------------------------------------------------------------------

Widget _buildTextEditor(
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

Widget _buildTextDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldInlineMarkdownText(value.value);
}

Widget _buildTextCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldInlineMarkdownText(value.value);
}

// ---------------------------------------------------------------------------
// Definition constant
// ---------------------------------------------------------------------------

final textFieldDefinition = CustomFieldTypeDefinition(
  id: 'text',
  legacyIntValue: 0,
  labelL10nKey: 'customFieldTypeShortText',
  icon: AppIcons.textFields,
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  editorBuilder: _buildTextEditor,
  displayBuilder: _buildTextDisplay,
  compactBuilder: _buildTextCompact,
  allowsTextualSwitch: true,
);
