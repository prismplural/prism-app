import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Reusable row primitive for navigation, metadata, and grouped list content.
class PrismListRow extends StatefulWidget {
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
  State<PrismListRow> createState() => _PrismListRowState();
}

class _PrismListRowState extends State<PrismListRow> {
  bool _pressed = false;

  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPress = widget.enabled && widget.onTap != null;
    final baseColor = widget.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    final foregroundColor = widget.enabled
        ? baseColor.withValues(alpha: 0.9)
        : theme.disabledColor;
    final subtitleColor = widget.enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.disabledColor;

    final child = Padding(
      padding: widget.padding,
      child: Row(
        children: [
          if (widget.leading != null) ...[
            SizedBox(
              width: widget.dense ? 36 : 40,
              child: Center(child: widget.leading),
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
                    child: widget.title,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  SizedBox(height: widget.dense ? 2 : 4),
                  DefaultTextStyle(
                    style:
                        theme.textTheme.bodySmall?.copyWith(
                          color: subtitleColor.withValues(alpha: 0.9),
                          height: 1.25,
                        ) ??
                        TextStyle(color: subtitleColor),
                    child: widget.subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 12),
            widget.trailing!,
          ] else if (widget.showChevron) ...[
            const SizedBox(width: 12),
            Icon(
              AppIcons.chevronRightRounded,
              color: subtitleColor.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );

    if (!canPress && widget.onLongPress == null) {
      return child;
    }

    final useOpacity = _isApple;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canPress ? widget.onTap : null,
        onLongPress: widget.onLongPress,
        onHighlightChanged: useOpacity
            ? (value) {
                if (_pressed != value) {
                  setState(() => _pressed = value);
                }
              }
            : null,
        borderRadius: BorderRadius.circular(PrismTokens.radiusMedium),
        child: child,
      ),
    );

    if (useOpacity) {
      row = AnimatedOpacity(
        opacity: _pressed ? 0.85 : 1.0,
        duration: reduceMotion
            ? Duration.zero
            : Duration(milliseconds: _pressed ? 0 : 150),
        child: row,
      );
    }

    return Semantics(
      button: true,
      enabled: widget.enabled,
      hint: widget.destructive ? context.l10n.destructiveAction : null,
      child: row,
    );
  }
}
