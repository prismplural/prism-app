import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Placeholder shown when a media attachment has expired or is no longer
/// available (e.g. relay TTL exceeded, deleted from server).
class ExpiredMedia extends StatelessWidget {
  const ExpiredMedia({
    super.key,
    this.width,
    this.height,
  });

  /// Display width constraint. Defaults to 200.
  final double? width;

  /// Display height constraint. Defaults to 80.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveWidth = width ?? 200.0;
    final effectiveHeight = height ?? 80.0;

    return Semantics(
      label: 'Media no longer available',
      child: TintedGlassSurface(
        borderRadius: BorderRadius.circular(12),
        width: effectiveWidth,
        height: effectiveHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.imageBroken,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Text(
              'Media no longer available',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
