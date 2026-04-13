import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A toggle row with consistent Prism styling.
///
/// Uses [PrismListRow] with [Switch.adaptive] for platform-correct toggle
/// appearance (CupertinoSwitch on iOS, Material Switch on Android).
class PrismSwitchRow extends StatelessWidget {
  const PrismSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional icon shown in a tinted glass circle on the leading edge.
  final IconData? icon;

  /// Tint color for the icon circle. Defaults to [ColorScheme.primary].
  final Color? iconColor;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: PrismListRow(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        leading: icon != null ? _IconCircle(icon: icon!, color: iconColor, enabled: enabled) : null,
        trailing: Switch.adaptive(
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
        onTap: enabled ? () => onChanged(!value) : null,
        enabled: enabled,
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, this.color, this.enabled = true});

  final IconData icon;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.primary;
    return TintedGlassSurface.circle(
      size: 40,
      tint: resolvedColor,
      child: Icon(
        icon,
        size: 20,
        color: enabled
            ? AppColors.warmWhite.withValues(alpha: 0.85)
            : Theme.of(context).disabledColor.withValues(alpha: 0.5),
      ),
    );
  }
}
