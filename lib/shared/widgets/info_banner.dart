import 'package:flutter/material.dart';
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
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  /// Defaults to [iconColor] with 0.1 opacity.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? iconColor.withValues(alpha: 0.1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
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
        ],
      ),
    );
  }
}
