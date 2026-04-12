import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// A styled popup menu with consistent item layout.
///
/// Items are rendered as [ListTile] rows with icon, label, and optional
/// destructive styling. Wraps [PopupMenuButton].
class PrismPopupMenu<T> extends StatelessWidget {
  PrismPopupMenu({
    super.key,
    required this.items,
    this.onSelected,
    IconData? icon,
    this.tooltip,
    this.iconSize = 20.0,
  }) : icon = icon ?? AppIcons.moreVert;

  final List<PrismMenuItem<T>> items;
  final ValueChanged<T>? onSelected;
  final IconData icon;
  final String? tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip ?? context.l10n.moreOptions,
      icon: Icon(icon, size: iconSize),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            child: _MenuItemRow(item: item),
          ),
      ],
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
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

class _MenuItemRow<T> extends StatelessWidget {
  const _MenuItemRow({required this.item});

  final PrismMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.destructive ? theme.colorScheme.error : null;

    return ListTile(
      leading: Icon(item.icon, color: color),
      title: Text(
        item.label,
        style: color != null ? TextStyle(color: color) : null,
      ),
      contentPadding: EdgeInsets.zero,
    );
  }
}
