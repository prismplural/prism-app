import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

enum PrismPillTone { neutral, accent, destructive }

/// Compact metadata pill used for counts, tags, and lightweight status text.
class PrismPill extends StatelessWidget {
  const PrismPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = PrismPillTone.neutral,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  final String label;
  final IconData? icon;
  final PrismPillTone tone;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor =
        color ??
        switch (tone) {
          PrismPillTone.neutral => theme.colorScheme.onSurface,
          PrismPillTone.accent => theme.colorScheme.primary,
          PrismPillTone.destructive => theme.colorScheme.error,
        };
    final colors = resolveTintedControlColors(
      theme,
      accent: baseColor,
      fillAlpha: 0.10,
      foregroundAccentWeight: 0.38,
      borderAlpha: 0.16,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(PrismTokens.radiusPill),
        ),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
