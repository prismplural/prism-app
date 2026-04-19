import 'package:flutter/material.dart';
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

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
          PrismShapes.of(context).radius(PrismTokens.radiusPill),
        ),
        border: Border.all(color: baseColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: baseColor.withValues(alpha: 0.84)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: baseColor.withValues(alpha: 0.84),
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
