import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Placeholder shown when a media attachment has expired or is no longer
/// available on the relay.
class ExpiredMediaPlaceholder extends StatelessWidget {
  const ExpiredMediaPlaceholder({super.key});

  static const _borderRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Semantics(
      label: 'Media no longer available',
      child: TintedGlassSurface(
        borderRadius: BorderRadius.circular(_borderRadius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.imageOutlined,
              size: 20,
              color: mutedColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Media no longer available',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: mutedColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
