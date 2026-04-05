import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// A fully pill-shaped selectable chip.
///
/// Use [PrismChip] anywhere a [ChoiceChip] or [FilterChip] would appear —
/// member selection rows, filter bars, option pickers.
///
/// [selected] drives the visual state. [onTap] fires on press.
/// [avatar] is optional; typically a [Text] emoji, [Icon], or [MemberAvatar].
/// [selectedColor] overrides the accent when the member has a custom color.
class PrismChip extends StatelessWidget {
  const PrismChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatar,
    this.selectedColor,
    this.tintColor,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Optional leading widget — emoji text, icon, or avatar.
  final Widget? avatar;

  /// Overrides the theme's primary color for the selected state.
  final Color? selectedColor;

  /// Always-on tint regardless of [selected] — for non-togglable chips
  /// (e.g. group tags) that show a fixed accent color.
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = tintColor ?? selectedColor ?? theme.colorScheme.primary;

    final bgColor = tintColor != null
        ? tintColor!.withValues(alpha: 0.15)
        : selected
            ? accent.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest;

    final borderColor = tintColor != null
        ? tintColor!.withValues(alpha: 0.5)
        : selected
            ? accent
            : theme.colorScheme.outline.withValues(alpha: 0.4);

    final labelColor = tintColor != null
        ? tintColor!
        : selected
            ? accent
            : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1.0),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PrismTokens.radiusPill),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                avatar != null ? 8 : 14,
                6,
                14,
                6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (avatar != null) ...[
                    avatar!,
                    const SizedBox(width: 6),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    style: (theme.textTheme.labelMedium ?? const TextStyle())
                        .copyWith(
                      color: labelColor,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
