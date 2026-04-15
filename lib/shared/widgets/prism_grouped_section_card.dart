import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

/// A grouped-content container intended for stacked rows (e.g. settings rows).
///
/// Unlike [PrismSectionCard], this defaults to **no internal padding** so
/// row widgets can control their own spacing without double-padding.
class PrismGroupedSectionCard extends StatelessWidget {
  const PrismGroupedSectionCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
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

