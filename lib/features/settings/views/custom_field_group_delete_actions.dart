import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

List<Widget> buildCustomFieldGroupDeleteActions(BuildContext context) {
  return [
    Builder(
      builder: (dialogContext) => PrismButton(
        label: context.l10n.cancel,
        tone: PrismButtonTone.outlined,
        onPressed: () => Navigator.of(dialogContext).pop(null),
      ),
    ),
    Builder(
      builder: (dialogContext) => PrismButton(
        label: context.l10n.customFieldGroupDeleteChildren,
        tone: PrismButtonTone.destructive,
        onPressed: () => Navigator.of(dialogContext).pop(true),
      ),
    ),
    Builder(
      builder: (dialogContext) => PrismButton(
        label: context.l10n.customFieldGroupPromoteChildren,
        tone: PrismButtonTone.filled,
        onPressed: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  ];
}
