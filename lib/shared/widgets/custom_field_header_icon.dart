import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/shared/icons/phosphor_icon_catalog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

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
    if (emoji != null) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: MemberAvatar.centeredEmoji(emoji, fontSize: size * 0.88),
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
