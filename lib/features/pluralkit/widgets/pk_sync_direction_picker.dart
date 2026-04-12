import 'package:flutter/material.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
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
        PrismSegment(value: PkSyncDirection.pullOnly, label: context.l10n.pluralkitPull),
        PrismSegment(value: PkSyncDirection.bidirectional, label: context.l10n.pluralkitBoth),
        PrismSegment(value: PkSyncDirection.pushOnly, label: context.l10n.pluralkitPush),
      ],
      selected: selected,
      onChanged: onChanged,
    );
  }
}
