import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

enum PrismCheckboxAffinity { leading, trailing }

/// A selectable row with Prism styling and a built-in checkbox control.
///
/// Use this for list-based multi-select and confirmation rows instead of
/// pairing [PrismListRow] with a raw [Checkbox] at each call site.
class PrismCheckboxRow extends StatelessWidget {
  const PrismCheckboxRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.dense = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.checkboxAffinity = PrismCheckboxAffinity.trailing,
  }) : assert(
         checkboxAffinity == PrismCheckboxAffinity.trailing || leading == null,
         'Leading checkbox rows cannot also provide a leading widget.',
       );

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool dense;
  final EdgeInsets padding;
  final PrismCheckboxAffinity checkboxAffinity;

  @override
  Widget build(BuildContext context) {
    final checkbox = Checkbox.adaptive(
      value: value,
      onChanged: enabled ? (next) => onChanged(next ?? false) : null,
    );

    Widget? resolvedTrailing = trailing;
    if (checkboxAffinity == PrismCheckboxAffinity.trailing) {
      resolvedTrailing = trailing == null
          ? checkbox
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [trailing!, const SizedBox(width: 8), checkbox],
            );
    }

    return PrismListRow(
      title: title,
      subtitle: subtitle,
      leading: checkboxAffinity == PrismCheckboxAffinity.leading
          ? checkbox
          : leading,
      trailing: resolvedTrailing,
      enabled: enabled,
      dense: dense,
      padding: padding,
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }
}
