import 'package:flutter/material.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — color has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

// ---------------------------------------------------------------------------
// Editor builder
// ---------------------------------------------------------------------------

Widget _buildColorEditor(
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

Widget _buildColorDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldColorDisplay(value: value.value);
}

Widget _buildColorCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldColorDisplay(value: value.value);
}

// ---------------------------------------------------------------------------
// Definition constant
// ---------------------------------------------------------------------------

final colorFieldDefinition = CustomFieldTypeDefinition(
  id: 'color',
  legacyIntValue: 1,
  labelL10nKey: 'customFieldTypeColor',
  icon: AppIcons.palette,
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  editorBuilder: _buildColorEditor,
  displayBuilder: _buildColorDisplay,
  compactBuilder: _buildColorCompact,
);
