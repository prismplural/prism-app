import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

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

enum PrismTermChoiceGridDensity { standard, compact }

class PrismTermChoiceGrid<T> extends StatelessWidget {
  const PrismTermChoiceGrid({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
    this.crossAxisCount = 2,
    this.childAspectRatio = 3.3,
    this.density = PrismTermChoiceGridDensity.standard,
  });

  final List<PrismTermChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;
  final int crossAxisCount;
  final double childAspectRatio;
  final PrismTermChoiceGridDensity density;

  @override
  Widget build(BuildContext context) {
    final useCompact =
        density == PrismTermChoiceGridDensity.compact &&
        MediaQuery.sizeOf(context).width >= PrismTokens.desktopBreakpoint;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveCrossAxisCount =
            useCompact && constraints.maxWidth >= 720 && choices.length >= 3
            ? 3
            : crossAxisCount;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: choices.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveCrossAxisCount,
            mainAxisSpacing: useCompact ? 6 : 8,
            crossAxisSpacing: useCompact ? 6 : 8,
            childAspectRatio: childAspectRatio,
            mainAxisExtent: useCompact ? 52 : null,
          ),
          itemBuilder: (context, index) {
            final choice = choices[index];
            return _TermChoiceTile<T>(
              choice: choice,
              selected: choice.value == selected,
              compact: useCompact,
              onTap: () => onSelected(choice.value),
            );
          },
        );
      },
    );
  }
}

class _TermChoiceTile<T> extends StatelessWidget {
  const _TermChoiceTile({
    required this.choice,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final PrismTermChoice<T> choice;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final foreground = selected
        ? primary
        : onSurface.withValues(alpha: isDark ? 0.8 : 0.82);
    final supporting = selected
        ? primary.withValues(alpha: 0.78)
        : onSurface.withValues(alpha: isDark ? 0.52 : 0.50);

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
                ? onSurface.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(10),
            ),
            border: selected
                ? Border.all(color: primary.withValues(alpha: 0.42))
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 8,
              vertical: compact ? 6 : 0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  choice.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? theme.textTheme.labelMedium
                              : theme.textTheme.labelLarge)
                          ?.copyWith(
                            color: foreground,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
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
