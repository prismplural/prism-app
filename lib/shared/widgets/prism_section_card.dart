import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// Grouped content container for related controls or rows.
class PrismSectionCard extends StatelessWidget {
  const PrismSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.margin = EdgeInsets.zero,
    this.tone = PrismSurfaceTone.subtle,
    this.accentColor,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final PrismSurfaceTone tone;
  final Color? accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return PrismSurface(
      padding: padding,
      margin: margin,
      tone: tone,
      accentColor: accentColor,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
