import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';

/// Shows the app's standard color picker dialog and returns the chosen color
/// as an uppercase `#RRGGBB` hex string, or null when cancelled/dismissed.
///
/// Shared color selector for custom-field color controls: choice options (field
/// config sheet + member value editor) and the color-type field input all route
/// through here so the picker UX stays identical. Slider gradient anchors still
/// use their own inline dialog (_ColorPickerRow) — not yet migrated.
Future<String?> showPrismColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  String? title,
}) async {
  var picked = initialColor;
  final confirmed = await PrismDialog.show<bool>(
    context: context,
    title: title ?? context.l10n.customFieldColorPickerTitle,
    builder: (dialogContext) {
      return ColorPicker(
        pickerColor: initialColor,
        onColorChanged: (color) => picked = color,
        enableAlpha: false,
        hexInputBar: true,
        labelTypes: const [],
        portraitOnly: true,
        pickerAreaHeightPercent: 0.7,
      );
    },
    actions: [
      PrismButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
        label: context.l10n.cancel,
      ),
      PrismButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
        label: context.l10n.save,
        tone: PrismButtonTone.filled,
      ),
    ],
  );
  if (confirmed != true) return null;
  final value = picked.toARGB32();
  return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
