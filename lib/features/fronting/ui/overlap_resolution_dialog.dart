import 'package:flutter/material.dart';

import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Shows a dialog with options for resolving overlapping sessions.
///
/// Returns the chosen [OverlapResolution], or `null` if dismissed.
Future<OverlapResolution?> showOverlapResolutionDialog(
  BuildContext context, {
  required int overlapCount,
  bool wouldDeleteConflicting = false,
}) async {
  final resolution = await PrismDialog.show<OverlapResolution>(
    context: context,
    title: 'Overlap with $overlapCount '
        '${overlapCount == 1 ? 'session' : 'sessions'}',
    builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(AppIcons.contentCut),
            title: const Text('Trim overlapping sessions'),
            subtitle: const Text(
              'Shorten or remove sessions that conflict with your edit.',
            ),
            onTap: () => Navigator.of(ctx).pop(OverlapResolution.trim),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(AppIcons.group),
            title: const Text('Create co-fronting session'),
            subtitle: const Text(
              'Split the overlapping time into shared co-fronting segments.',
            ),
            onTap: () =>
                Navigator.of(ctx).pop(OverlapResolution.makeCoFronting),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(OverlapResolution.cancel),
              child: const Text('Cancel'),
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
      title: 'Remove Session',
      message: 'This would remove a session entirely. Continue?',
      confirmLabel: 'Continue',
      destructive: true,
    );
    if (!confirmed) return null;
  }

  return resolution;
}
