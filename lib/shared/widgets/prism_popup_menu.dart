import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Top-bar overflow menu styled to match the rest of Prism.
///
/// Renders a [PrismTopBarAction] anchor that opens a frosted-glass
/// [BlurPopupAnchor] with one [PrismListRow] per [PrismMenuItem].
class PrismPopupMenu<T> extends StatefulWidget {
  const PrismPopupMenu({
    super.key,
    required this.items,
    this.onSelected,
    this.icon,
    this.tooltip,
    this.width = 220,
    this.maxHeight = 320,
    this.preferredDirection = BlurPopupDirection.down,
  });

  final List<PrismMenuItem<T>> items;
  final ValueChanged<T>? onSelected;
  final IconData? icon;
  final String? tooltip;
  final double width;
  final double maxHeight;
  final BlurPopupDirection preferredDirection;

  @override
  State<PrismPopupMenu<T>> createState() => _PrismPopupMenuState<T>();
}

class _PrismPopupMenuState<T> extends State<PrismPopupMenu<T>> {
  final GlobalKey<BlurPopupAnchorState> _popupKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tooltip = widget.tooltip ?? context.l10n.moreOptions;
    return BlurPopupAnchor(
      key: _popupKey,
      trigger: BlurPopupTrigger.manual,
      preferredDirection: widget.preferredDirection,
      width: widget.width,
      maxHeight: widget.maxHeight,
      itemCount: widget.items.length,
      semanticLabel: tooltip,
      itemBuilder: (context, index, close) {
        final item = widget.items[index];
        final theme = Theme.of(context);
        final iconColor = !item.enabled
            ? theme.disabledColor
            : item.destructive
            ? theme.colorScheme.error
            : theme.colorScheme.onSurface;
        return PrismListRow(
          dense: true,
          enabled: item.enabled,
          destructive: item.destructive,
          leading: Icon(item.icon, size: 20, color: iconColor),
          title: Text(item.label),
          onTap: item.enabled
              ? () {
                  close();
                  widget.onSelected?.call(item.value);
                }
              : null,
        );
      },
      child: PrismTopBarAction(
        icon: widget.icon ?? AppIcons.moreVert,
        tooltip: tooltip,
        onPressed: () => _popupKey.currentState?.show(),
        onSecondaryTap: () => _popupKey.currentState?.show(),
      ),
    );
  }
}

/// Describes a single item in a [PrismPopupMenu].
class PrismMenuItem<T> {
  const PrismMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  final bool enabled;
}
