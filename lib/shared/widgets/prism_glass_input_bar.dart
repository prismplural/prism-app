import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A rounded glass container for composer, search, and inline input rows.
class PrismGlassInputBar extends StatelessWidget {
  const PrismGlassInputBar({
    super.key,
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.fromLTRB(8, 7, 8, 7),
    this.borderRadius = 30,
    this.minHeight,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final Color? tint;
  final EdgeInsets padding;
  final double borderRadius;
  final double? minHeight;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    Widget content = Align(alignment: alignment, child: child);
    if (minHeight != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight!),
        child: content,
      );
    }

    return TintedGlassSurface(
      borderRadius: BorderRadius.circular(borderRadius),
      tint: tint,
      padding: padding,
      child: content,
    );
  }
}
