import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A toggle row with consistent Prism styling.
///
/// Wraps [SwitchListTile] with optional icon container treatment matching
/// the settings screen pattern.
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

  /// Optional icon shown in a tinted circle on the leading edge.
  final IconData? icon;

  /// Color for the icon circle. Defaults to [ColorScheme.primary].
  final Color? iconColor;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: enabled ? onChanged : null,
      secondary: icon != null ? _IconCircle(icon: icon!, color: iconColor) : null,
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.primary;
    return TintedGlassSurface.circle(
      size: 40,
      tint: resolvedColor,
      child: Icon(icon, size: 20, color: resolvedColor),
    );
  }
}
