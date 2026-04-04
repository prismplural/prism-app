import 'package:flutter/material.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

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
    return PrismSegmentedControl<PkSyncDirection>(
      segments: [
        const PrismSegment(value: PkSyncDirection.pullOnly, label: 'Pull'),
        const PrismSegment(value: PkSyncDirection.bidirectional, label: 'Both'),
        const PrismSegment(value: PkSyncDirection.pushOnly, label: 'Push'),
      ],
      selected: selected,
      onChanged: onChanged,
    );
  }
}
