import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Shared top-bar layout for standard Prism pages.
///
/// The title is always centered on screen (not between leading/trailing) when
/// [centerTitle] is true. Use [actions] for multiple trailing buttons — they
/// are automatically spaced.
class PrismTopBar extends StatelessWidget implements PreferredSizeWidget {
  const PrismTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.actions,
    this.titleStyle,
    this.height = PrismTokens.topBarHeight,
    this.horizontalPadding = PrismTokens.topBarPadding,
    this.centerTitle = true,
    this.showBackButton = false,
  }) : assert(
          trailing == null || actions == null,
          'Use either trailing or actions, not both',
        );

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Single trailing widget. For multiple actions prefer [actions].
  final Widget? trailing;

  /// Multiple trailing action widgets, automatically spaced 8px apart.
  final List<Widget>? actions;

  /// Optional override for the title text style.
  final TextStyle? titleStyle;

  final double height;
  final EdgeInsets horizontalPadding;
  final bool centerTitle;

  /// When true and [leading] is null, auto-inserts a back button that pops
  /// the current route.
  final bool showBackButton;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final effectiveLeading = leading ??
        (showBackButton
            ? PrismTopBarAction(
                icon: AppIcons.arrowBack,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);

    final effectiveTrailing = trailing ?? _buildActions();

    final titleBlock = _TitleBlock(
      title: title,
      subtitle: subtitle,
      centerTitle: centerTitle,
      titleStyle: titleStyle,
    );

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: horizontalPadding,
          child: centerTitle
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    // Title centered on the full bar width.
                    titleBlock,
                    // Leading and trailing positioned at edges.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (effectiveLeading != null)
                          effectiveLeading
                        else
                          _slot(null),
                        const Spacer(),
                        if (effectiveTrailing != null)
                          effectiveTrailing
                        else
                          _slot(null),
                      ],
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _slot(effectiveLeading),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: titleBlock,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (effectiveTrailing != null)
                      effectiveTrailing
                    else
                      _slot(null),
                  ],
                ),
        ),
      ),
    );
  }

  Widget? _buildActions() {
    if (actions == null || actions!.isEmpty) return null;
    if (actions!.length == 1) return actions!.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < actions!.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          actions![i],
        ],
      ],
    );
  }

  Widget _slot(Widget? child) {
    return SizedBox.square(
      dimension: PrismTokens.topBarActionSize,
      child: child ?? const SizedBox.shrink(),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.subtitle,
    required this.centerTitle,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final bool centerTitle;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alignment = centerTitle ? TextAlign.center : TextAlign.left;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= PrismTokens.desktopBreakpoint;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: centerTitle
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignment,
            style: titleStyle ?? theme.textTheme.headlineLarge?.copyWith(
              fontSize: isDesktop ? 18 : 22,
              height: 1,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignment,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
              fontWeight: FontWeight.w500,
              fontSize: 11,
              height: 1,
            ),
          ),
        ],
      ],
    );
  }
}
