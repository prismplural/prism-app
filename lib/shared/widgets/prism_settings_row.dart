import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Settings-oriented row wrapper with icon treatment and optional chevron.
class PrismSettingsRow extends StatelessWidget {
  const PrismSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.enabled = true,
    this.showChevron = true,
    this.destructive = false,
  }) : assert(
         subtitle == null || subtitleWidget == null,
         'Use either subtitle or subtitleWidget, not both.',
       );

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool enabled;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedIconColor =
        iconColor ??
        (destructive ? theme.colorScheme.error : theme.colorScheme.primary);
    final foregroundColor = enabled
        ? theme.colorScheme.onSurface.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.85 : 0.82,
          )
        : theme.disabledColor.withValues(alpha: 0.5);

    return PrismListRow(
      title: Text(title),
      subtitle: subtitleWidget ?? (subtitle != null ? Text(subtitle!) : null),
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      enabled: enabled,
      destructive: destructive,
      showChevron: showChevron,
      trailing: trailing,
      leading: PrismShapes.of(context).cornerStyle == CornerStyle.angular
          ? TintedGlassSurface(
              width: 40,
              height: 40,
              borderRadius: BorderRadius.zero,
              tint: resolvedIconColor,
              child: Icon(icon, size: 20, color: foregroundColor),
            )
          : TintedGlassSurface.circle(
              size: 40,
              tint: resolvedIconColor,
              child: Icon(icon, size: 20, color: foregroundColor),
            ),
    );
  }
}
