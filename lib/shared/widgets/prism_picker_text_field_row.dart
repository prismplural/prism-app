import 'package:flutter/material.dart';

/// Lays out a labeled picker beside a labeled field so both controls share the
/// same top alignment inside a single row.
class PrismPickerTextFieldRow extends StatelessWidget {
  const PrismPickerTextFieldRow({
    super.key,
    required this.pickerLabel,
    required this.picker,
    required this.field,
    this.spacing = 12,
    this.pickerSemanticLabel,
  });

  final String pickerLabel;
  final Widget picker;
  final Widget field;
  final double spacing;
  final String? pickerSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.titleSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Text(pickerLabel, style: labelStyle)),
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: pickerSemanticLabel ?? pickerLabel,
              child: picker,
            ),
          ],
        ),
        SizedBox(width: spacing),
        Expanded(child: field),
      ],
    );
  }
}
