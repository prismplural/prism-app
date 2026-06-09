import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/choice_field_widgets.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_widgets.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/features/members/widgets/group_field_widgets.dart';
import 'package:prism_plurality/features/members/widgets/member_field_widgets.dart';
import 'package:prism_plurality/features/members/widgets/scale_field_widgets.dart';
import 'package:prism_plurality/features/members/widgets/slider_field_widgets.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Renderer for one custom field type. The widget layer's counterpart to
/// [CustomFieldTypeDefinition] (which is pure metadata in the domain layer).
///
/// Holds the three builder functions that produce widgets for editor, full
/// display, and compact (list-row) display. Builders are top-level functions
/// defined below, keyed by [CustomFieldTypeDefinition.id].
class CustomFieldRenderer {
  const CustomFieldRenderer({
    required this.editorBuilder,
    required this.displayBuilder,
    required this.compactBuilder,
  });

  /// Build the per-member editor widget. All four legacy types return a
  /// [FieldInputWidget]; future types return their own stateful widget.
  final Widget Function(
    BuildContext context,
    CustomField field,
    CustomFieldValue? value,
    String memberId,
  )
  editorBuilder;

  /// Build the per-member display widget (full detail / card view).
  final Widget Function(
    BuildContext context,
    CustomField field,
    CustomFieldValue value,
  )
  displayBuilder;

  /// Build the compact list-view display widget.
  final Widget Function(
    BuildContext context,
    CustomField field,
    CustomFieldValue value,
  )
  compactBuilder;
}

/// Renderer registry, keyed by [CustomFieldTypeDefinition.id].
///
/// New types added to the type registry MUST also register a renderer here,
/// or they will fall through to the unsupported-type path in display/editor
/// dispatch sites.
final Map<String, CustomFieldRenderer> customFieldRenderers = {
  'text': const CustomFieldRenderer(
    editorBuilder: buildTextEditor,
    displayBuilder: buildTextDisplay,
    compactBuilder: buildTextCompact,
  ),
  'long_text': const CustomFieldRenderer(
    editorBuilder: buildLongTextEditor,
    displayBuilder: buildLongTextDisplay,
    compactBuilder: buildLongTextCompact,
  ),
  'color': const CustomFieldRenderer(
    editorBuilder: buildColorEditor,
    displayBuilder: buildColorDisplay,
    compactBuilder: buildColorCompact,
  ),
  'date': const CustomFieldRenderer(
    editorBuilder: buildDateEditor,
    displayBuilder: buildDateDisplay,
    compactBuilder: buildDateCompact,
  ),
  'choice': const CustomFieldRenderer(
    editorBuilder: buildChoiceEditor,
    displayBuilder: buildChoiceDisplay,
    compactBuilder: buildChoiceCompact,
  ),
  'group': const CustomFieldRenderer(
    editorBuilder: buildGroupEditor,
    displayBuilder: buildGroupDisplay,
    compactBuilder: buildGroupCompact,
  ),
  'scale': const CustomFieldRenderer(
    editorBuilder: buildScaleEditor,
    displayBuilder: buildScaleDisplay,
    compactBuilder: buildScaleCompact,
  ),
  'slider': const CustomFieldRenderer(
    editorBuilder: buildSliderEditor,
    displayBuilder: buildSliderDisplay,
    compactBuilder: buildSliderCompact,
  ),
  'member': const CustomFieldRenderer(
    editorBuilder: buildMemberEditor,
    displayBuilder: buildMemberDisplay,
    compactBuilder: buildMemberCompact,
  ),
};

/// Convenience lookup — returns null for unknown / unregistered types.
CustomFieldRenderer? rendererFor(CustomFieldTypeDefinition? def) {
  if (def == null) return null;
  return customFieldRenderers[def.id];
}

// ─── text ─────────────────────────────────────────────────────────────────

Widget buildTextEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return FieldInputWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

Widget buildTextDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldInlineMarkdownText(value.value);
}

Widget buildTextCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldInlineMarkdownText(value.value);
}

// ─── long_text ─────────────────────────────────────────────────────────────

Widget buildLongTextEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return FieldInputWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

Widget buildLongTextDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldLongTextPreview(title: field.name, data: value.value);
}

Widget buildLongTextCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldLongTextPreview(title: field.name, data: value.value);
}

// ─── color ────────────────────────────────────────────────────────────────

Widget buildColorEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return FieldInputWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

Widget buildColorDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldColorDisplay(value: value.value);
}

Widget buildColorCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return FieldColorDisplay(value: value.value);
}

// ─── date ─────────────────────────────────────────────────────────────────

Widget buildDateEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return FieldInputWidget(
    field: field,
    memberId: memberId,
    existingValue: value,
  );
}

Widget buildDateDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  final displayValue = _formatDateValue(
    context,
    value.value,
    field.datePrecision,
  );
  return Text(displayValue);
}

Widget buildDateCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  final displayValue = _formatDateValue(
    context,
    value.value,
    field.datePrecision,
  );
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
