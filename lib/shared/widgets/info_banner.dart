import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

/// Reusable banner widget for displaying informational messages.
///
/// Shows an icon, title, optional message, and an optional action button
/// in a rounded container with a tinted background.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.buttonText,
    this.onButtonPressed,
    this.backgroundColor,
    this.onDismiss,
    this.dismissTooltip,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  /// Defaults to [iconColor] with 0.1 opacity.
  final Color? backgroundColor;

  /// If provided, a small close icon is shown; tapping invokes this callback.
  final VoidCallback? onDismiss;
  final String? dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? iconColor.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (buttonText != null && onButtonPressed != null) ...[
            const SizedBox(width: 8),
            PrismButton(
              label: buttonText!,
              onPressed: onButtonPressed!,
              tone: PrismButtonTone.subtle,
              density: PrismControlDensity.compact,
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: theme.colorScheme.onSurfaceVariant,
              tooltip: dismissTooltip,
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
