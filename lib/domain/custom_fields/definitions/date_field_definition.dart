import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec stubs — date has no type config.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _alwaysNull(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _alwaysNullOut(CustomFieldTypeConfig? config) => null;

// ---------------------------------------------------------------------------
// Editor builder
// ---------------------------------------------------------------------------

Widget _buildDateEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return FieldInputWidget(field: field, memberId: memberId, existingValue: value);
}

// ---------------------------------------------------------------------------
// Display builders — date values are formatted from ISO string to locale string.
// ---------------------------------------------------------------------------

Widget _buildDateDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  final displayValue = _formatDateValue(context, value.value, field.datePrecision);
  return Text(displayValue);
}

Widget _buildDateCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  final displayValue = _formatDateValue(context, value.value, field.datePrecision);
  return Text(displayValue);
}

String _formatDateValue(
  BuildContext context,
  String raw,
  DatePrecision? precision,
) {
  final locale = context.dateLocale;
  try {
    final dt = DateTime.parse(raw);
    return switch (precision ?? DatePrecision.full) {
      DatePrecision.full => DateFormat.yMMMd(locale).format(dt),
      DatePrecision.monthYear => DateFormat.yMMM(locale).format(dt),
      DatePrecision.monthDay => DateFormat.MMMd(locale).format(dt),
      DatePrecision.month => DateFormat.MMMM(locale).format(dt),
      DatePrecision.year => DateFormat.y(locale).format(dt),
      DatePrecision.timestamp =>
        '${DateFormat.yMMMd(locale).format(dt)} ${context.formatTime(dt)}',
    };
  } catch (_) {
    return raw;
  }
}

// ---------------------------------------------------------------------------
// Definition constant
// ---------------------------------------------------------------------------

final dateFieldDefinition = CustomFieldTypeDefinition(
  id: 'date',
  legacyIntValue: 2,
  labelL10nKey: 'customFieldTypeDate',
  icon: AppIcons.calendarToday,
  configFromJson: _alwaysNull,
  configToJson: _alwaysNullOut,
  editorBuilder: _buildDateEditor,
  displayBuilder: _buildDateDisplay,
  compactBuilder: _buildDateCompact,
);
