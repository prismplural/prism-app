import 'package:flutter/material.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// A segmented button widget for picking the PluralKit sync direction.
class PkSyncDirectionPicker extends StatelessWidget {
  final PkSyncDirection selected;
  final ValueChanged<PkSyncDirection> onChanged;

  const PkSyncDirectionPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PkSyncDirection>(
      segments: [
        ButtonSegment(
          value: PkSyncDirection.pullOnly,
          label: Text('Pull'),
          icon: Icon(AppIcons.download, size: 18),
        ),
        ButtonSegment(
          value: PkSyncDirection.bidirectional,
          label: Text('Both'),
          icon: Icon(AppIcons.sync, size: 18),
        ),
        ButtonSegment(
          value: PkSyncDirection.pushOnly,
          label: Text('Push'),
          icon: Icon(AppIcons.upload, size: 18),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onChanged(selection.first);
        }
      },
      showSelectedIcon: false,
    );
  }
}
