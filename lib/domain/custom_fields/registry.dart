import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/color_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/date_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/group_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/long_text_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/member_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/scale_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/slider_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/text_field_definition.dart';

/// Registry ID for the group field type.
///
/// Use this constant anywhere code needs to check whether a field is a group
/// (e.g. parent-is-group validation, orphan-on-render promotion, value-write
/// rejection). Keeping the literal `'group'` here as the single source of
/// truth avoids drift between the definition's `id` and consumer code.
const kGroupFieldTypeId = 'group';

/// The global registry of all registered custom field types.
///
/// Legacy types (text, color, date, long_text) are registered here with their
/// int back-compat values matching the [CustomFieldType] enum ordinals.
///
/// Future types are added by appending to this list — no schema or dispatch
/// site changes required.
final customFieldTypeRegistry = CustomFieldTypeRegistry([
  textFieldDefinition,
  colorFieldDefinition,
  dateFieldDefinition,
  longTextFieldDefinition,
  choiceFieldDefinition,
  groupFieldDefinition,
  scaleFieldDefinition,
  sliderFieldDefinition,
  memberFieldDefinition,
]);
