import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

class PrismTermChoice<T> {
  const PrismTermChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.semanticLabel,
  });

  final T value;
  final String label;
  final String? subtitle;
  final String? semanticLabel;
}

class PrismTermChoiceGrid<T> extends StatelessWidget {
  const PrismTermChoiceGrid({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
    this.crossAxisCount = 2,
    this.childAspectRatio = 3.3,
  });

  final List<PrismTermChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;
  final int crossAxisCount;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: childAspectRatio,
      children: [
        for (final choice in choices)
          _TermChoiceTile<T>(
            choice: choice,
            selected: choice.value == selected,
            onTap: () => onSelected(choice.value),
          ),
      ],
    );
  }
}

class _TermChoiceTile<T> extends StatelessWidget {
  const _TermChoiceTile({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final PrismTermChoice<T> choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final foreground = selected
        ? primary
        : isDark
        ? AppColors.warmWhite.withValues(alpha: 0.8)
        : AppColors.warmBlack.withValues(alpha: 0.82);
    final supporting = selected
        ? primary.withValues(alpha: 0.78)
        : isDark
        ? AppColors.warmWhite.withValues(alpha: 0.52)
        : AppColors.warmBlack.withValues(alpha: 0.50);

    return Semantics(
      button: true,
      selected: selected,
      label: choice.semanticLabel ?? choice.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: isDark ? 0.22 : 0.16)
                : isDark
                ? AppColors.warmWhite.withValues(alpha: 0.1)
                : AppColors.parchmentElevated,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(10),
            ),
            border: selected
                ? Border.all(color: primary.withValues(alpha: 0.42))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  choice.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (choice.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    choice.subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: supporting,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
