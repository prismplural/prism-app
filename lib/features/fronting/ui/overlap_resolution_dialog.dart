import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Shows a dialog with options for resolving overlapping sessions.
///
/// Returns the chosen [OverlapResolution], or `null` if dismissed.
///
/// When [canCoFront] is false (e.g. the overlap crosses fronting/sleep
/// boundaries), the co-front option is hidden and only trim + cancel remain.
Future<OverlapResolution?> showOverlapResolutionDialog(
  BuildContext context, {
  required int overlapCount,
  bool wouldDeleteConflicting = false,
  bool canCoFront = true,
}) async {
  final resolution = await PrismDialog.show<OverlapResolution>(
    context: context,
    title: context.l10n.frontingOverlapTitle(overlapCount),
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrismListRow(
            padding: EdgeInsets.zero,
            leading: Icon(AppIcons.contentCut),
            title: Text(ctx.l10n.frontingOverlapTrimOption),
            subtitle: Text(ctx.l10n.frontingOverlapTrimSubtitle),
            onTap: () => Navigator.of(ctx).pop(OverlapResolution.trim),
          ),
          if (canCoFront)
            PrismListRow(
              padding: EdgeInsets.zero,
              leading: Icon(AppIcons.group),
              title: Text(ctx.l10n.frontingOverlapCoFrontOption),
              subtitle: Text(ctx.l10n.frontingOverlapCoFrontSubtitle),
              onTap: () =>
                  Navigator.of(ctx).pop(OverlapResolution.makeCoFronting),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: PrismButton(
              label: ctx.l10n.cancel,
              tone: PrismButtonTone.subtle,
              onPressed: () =>
                  Navigator.of(ctx).pop(OverlapResolution.cancel),
            ),
          ),
        ],
      );
    },
  );

  // If trim was chosen and it would delete a session entirely, confirm.
  if (resolution == OverlapResolution.trim &&
      wouldDeleteConflicting &&
      context.mounted) {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: context.l10n.frontingOverlapRemoveSessionTitle,
      message: context.l10n.frontingOverlapRemoveSessionMessage,
      confirmLabel: context.l10n.frontingOverlapContinue,
      destructive: true,
    );
    if (!confirmed) return null;
  }

  return resolution;
}
