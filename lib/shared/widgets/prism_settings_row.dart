import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Settings-oriented row wrapper with icon treatment and optional chevron.
class PrismSettingsRow extends StatelessWidget {
  const PrismSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.showChevron = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedIconColor =
        iconColor ??
        (destructive ? theme.colorScheme.error : theme.colorScheme.primary);

    return PrismListRow(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      onTap: onTap,
      enabled: enabled,
      destructive: destructive,
      showChevron: showChevron,
      trailing: trailing,
      leading: TintedGlassSurface(
        width: 40,
        height: 40,
        borderRadius: BorderRadius.zero,
        tint: resolvedIconColor,
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? AppColors.warmWhite.withValues(alpha: 0.85)
              : theme.disabledColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
