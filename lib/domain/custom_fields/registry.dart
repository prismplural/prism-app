import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/color_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/date_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/group_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/long_text_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/scale_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/slider_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/text_field_definition.dart';

/// The global registry of all registered custom field types.
///
/// Legacy types (text, color, date, long_text) are registered here with their
/// int back-compat values matching the [CustomFieldType] enum ordinals.
///
/// Future types are added by appending to this list — no schema or dispatch
/// site changes required (Tasks 7, 9, 11, 13):
final customFieldTypeRegistry = CustomFieldTypeRegistry([
  textFieldDefinition,
  colorFieldDefinition,
  dateFieldDefinition,
  longTextFieldDefinition,
  choiceFieldDefinition, // Task 7
  groupFieldDefinition, // Task 9
  scaleFieldDefinition, // Task 11
  sliderFieldDefinition, // Task 13
]);
