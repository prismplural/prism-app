import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/shared/icons/phosphor_icon_catalog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/text_presentation.dart';

class CustomFieldHeaderIconView extends StatelessWidget {
  const CustomFieldHeaderIconView({
    super.key,
    required this.field,
    this.size = 20,
    this.color,
  });

  final CustomField field;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = effectiveHeaderIcon(field.typeConfig);
    final emoji = icon?.emoji;
    if (emoji != null && emoji.trim().isNotEmpty) {
      return SizedBox.square(
        dimension: size,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            emoji,
            textAlign: TextAlign.center,
            style: textStyleForTextPresentation(
              const TextStyle(fontSize: 64),
              emoji,
            ),
          ),
        ),
      );
    }

    final phosphorName = icon?.phosphorName;
    return Icon(
      phosphorName == null
          ? fallbackCustomFieldIcon(field)
          : PhosphorIconCatalog.iconFor(phosphorName) ??
                fallbackCustomFieldIcon(field),
      size: size,
      color: color,
    );
  }
}

class CustomFieldHeaderLabel extends StatelessWidget {
  const CustomFieldHeaderLabel({
    super.key,
    required this.field,
    this.style,
    this.iconSize = 16,
    this.iconColor,
    this.spacing = 8,
    this.showFallbackIcon = false,
    this.maxLines,
    this.overflow,
  });

  final CustomField field;
  final TextStyle? style;
  final double iconSize;
  final Color? iconColor;
  final double spacing;
  final bool showFallbackIcon;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final hasExplicitIcon = effectiveHeaderIcon(field.typeConfig) != null;
    if (!hasExplicitIcon && !showFallbackIcon) {
      return Text(
        field.name,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return Row(
      children: [
        CustomFieldHeaderIconView(
          field: field,
          size: iconSize,
          color: iconColor,
        ),
        SizedBox(width: spacing),
        Expanded(
          child: Text(
            field.name,
            style: style,
            maxLines: maxLines,
            overflow: overflow,
          ),
        ),
      ],
    );
  }
}

IconData fallbackCustomFieldIcon(CustomField field) {
  final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
  if (def != null) return def.icon;

  return switch (field.fieldType) {
    CustomFieldType.text => AppIcons.textFields,
    CustomFieldType.longText => AppIcons.notes,
    CustomFieldType.color => AppIcons.palette,
    CustomFieldType.date => AppIcons.calendarToday,
    CustomFieldType.choice => AppIcons.checkBoxOutlined,
  };
}
