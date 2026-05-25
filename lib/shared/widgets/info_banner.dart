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
    this.dismissLabel,
    this.actionsBelow = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  /// Defaults to [iconColor] with 0.1 opacity.
  final Color? backgroundColor;

  /// If provided, a dismiss control is shown; tapping invokes this callback.
  final VoidCallback? onDismiss;
  final String? dismissTooltip;

  /// Label for the dismiss button in the stacked layout. Ignored when
  /// [actionsBelow] is false (dismiss renders as an icon there).
  final String? dismissLabel;

  /// When true, actions move to a row below the text instead of sharing the
  /// title row. Use for banners whose text needs room to wrap.
  final bool actionsBelow;

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
      child: actionsBelow
          ? _buildStacked(context, theme)
          : _buildInline(theme),
    );
  }

  Widget _buildInline(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(child: _textBlock(theme)),
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
    );
  }

  Widget _buildStacked(BuildContext context, ThemeData theme) {
    final hasPrimaryAction = buttonText != null && onButtonPressed != null;
    final hasDismiss = onDismiss != null;
    assert(
      !hasDismiss || dismissLabel != null || dismissTooltip != null,
      'InfoBanner with actionsBelow: true and onDismiss should provide '
      'dismissLabel (or at least dismissTooltip as a fallback).',
    );
    final resolvedDismissLabel = dismissLabel ??
        dismissTooltip ??
        MaterialLocalizations.of(context).closeButtonTooltip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(child: _textBlock(theme)),
          ],
        ),
        if (hasPrimaryAction || hasDismiss) ...[
          const SizedBox(height: 12),
          OverflowBar(
            spacing: 8,
            overflowSpacing: 8,
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              if (hasDismiss)
                PrismButton(
                  label: resolvedDismissLabel,
                  onPressed: onDismiss!,
                  tone: PrismButtonTone.subtle,
                ),
              if (hasPrimaryAction)
                PrismButton(
                  label: buttonText!,
                  onPressed: onButtonPressed!,
                  tone: PrismButtonTone.subtle,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _textBlock(ThemeData theme) {
    return Column(
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
    );
  }
}
