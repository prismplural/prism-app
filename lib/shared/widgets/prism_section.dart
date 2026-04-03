import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Shared section shell with optional description and footer content.
class PrismSection extends StatelessWidget {
  const PrismSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.footer,
    this.padding = PrismTokens.sectionPadding,
    this.spacing = PrismTokens.sectionSpacingCompact,
  });

  final String title;
  final Widget child;
  final String? description;
  final Widget? footer;
  final EdgeInsets padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontFamily: 'Unbounded',
                fontWeight: FontWeight.w700,
              ),
            ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          SizedBox(height: spacing),
          child,
          if (footer != null) ...[
            SizedBox(height: spacing),
            DefaultTextStyle(
              style:
                  theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ) ??
                  const TextStyle(),
              child: footer!,
            ),
          ],
        ],
      ),
    );
  }
}
