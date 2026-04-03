import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Reusable row primitive for navigation, metadata, and grouped list content.
class PrismListRow extends StatelessWidget {
  const PrismListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.enabled = true,
    this.destructive = false,
    this.dense = false,
    this.showChevron = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsets padding;
  final bool enabled;
  final bool destructive;
  final bool dense;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPress = enabled && onTap != null;
    final baseColor = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    final foregroundColor = enabled
        ? baseColor.withValues(alpha: 0.9)
        : theme.disabledColor;
    final subtitleColor = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.disabledColor;

    final child = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(
              width: dense ? 36 : 40,
              child: Center(child: leading),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTheme(
                  data: theme.iconTheme.copyWith(color: foregroundColor),
                  child: DefaultTextStyle(
                    style:
                        theme.textTheme.bodyLarge?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w600,
                        ) ??
                        TextStyle(color: foregroundColor),
                    child: title,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: dense ? 2 : 4),
                  DefaultTextStyle(
                    style:
                        theme.textTheme.bodySmall?.copyWith(
                          color: subtitleColor.withValues(alpha: 0.9),
                          height: 1.25,
                        ) ??
                        TextStyle(color: subtitleColor),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ] else if (showChevron) ...[
            const SizedBox(width: 12),
            Icon(
              AppIcons.chevronRightRounded,
              color: subtitleColor.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );

    if (!canPress && onLongPress == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canPress ? onTap : null,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(PrismTokens.radiusMedium),
        child: child,
      ),
    );
  }
}
