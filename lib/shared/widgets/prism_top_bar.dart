import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/embedded_pane_marker.dart';
import 'package:prism_plurality/shared/widgets/list_detail_layout.dart';
import 'package:prism_plurality/shared/widgets/modal_side_sheet_marker.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Shared top-bar layout for standard Prism pages.
///
/// The title is centered on screen (not between leading/trailing) when
/// [centerTitle] is true; `NavigationToolbar` measures the real action widths
/// and only moves the title when centering it would run underneath them. Use
/// [actions] for multiple trailing buttons — they are automatically spaced.
///
/// The bar is [height] tall whenever its content fits there, and grows with the
/// ambient text scale when it does not: the title is always laid out at the size
/// the user asked for (one line, ellipsised, with the full string in its
/// semantics) instead of being shrunk to fit.
///
/// Two heights exist and they are not interchangeable:
///  * [preferredSize] is a constant minimum ([height], 66dp by default). It is
///    what a `PreferredSizeWidget` getter can report without a `BuildContext`.
///  * [preferredHeightFor] is the height this bar actually needs at the ambient
///    text scale (content height, excluding the safe-area top).
///
/// A parent that reserves an extent must use the second one: [SliverPinnedTopBar]
/// (and therefore every [PrismPageScaffold] screen) asks it while building, and a
/// fixed slot such as `Scaffold.appBar` needs
/// `prismScaledPreferredSize(context, bar)`. Mounting this widget directly in
/// `Scaffold.appBar` reserves only the minimum and clips at large text — that is
/// the limitation the adapter exists for, not something a getter can fix.
class PrismTopBar extends StatelessWidget
    implements PreferredSizeWidget, PrismScaledHeight {
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

  /// Multiple trailing action widgets, automatically spaced.
  final List<Widget>? actions;

  /// Optional override for the title text style.
  final TextStyle? titleStyle;

  /// Minimum bar height. Preserved exactly whenever the content fits here.
  final double height;
  final EdgeInsets horizontalPadding;
  final bool centerTitle;

  /// When true and [leading] is null, auto-inserts a route-pop action. It
  /// renders as a back button on pushed pages and a close button inside modal
  /// side sheets.
  final bool showBackButton;

  /// Space above and below the title block once the bar has to grow past
  /// [height]. It also absorbs sub-pixel differences between the measured line
  /// box and the painted one, so the bar never clamps its own title.
  static const double _grownVerticalPadding = 12;

  @override
  Size get preferredSize => Size.fromHeight(height);

  TextStyle _resolvedTitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= PrismTokens.desktopBreakpoint;
    return titleStyle ??
        theme.textTheme.headlineLarge?.copyWith(
          fontSize: isDesktop ? 18 : 22,
          height: 1,
        ) ??
        const TextStyle();
  }

  TextStyle _resolvedSubtitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
          fontWeight: FontWeight.w500,
          fontSize: 11,
          height: 1,
        ) ??
        const TextStyle();
  }

  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) {
    // Measure the strings this bar will really paint: a title resolved to a
    // fallback face (emoji, CJK, Arabic) can have a taller line box than the
    // primary face, and reserving less would clip it.
    final titleLine = prismLineHeight(
      context,
      _resolvedTitleStyle(context),
      text: title,
    );
    final subtitleLine = subtitle == null
        ? 0.0
        : 3 +
              prismLineHeight(
                context,
                _resolvedSubtitleStyle(context),
                text: subtitle!,
              );
    // Width does not enter: the title is a single ellipsised line, so its height
    // depends only on the scaler and the style.
    // Fallback faces (emoji, CJK, Arabic) can paint outside their line box; the
    // bars reserve that measured escape above and below instead of shrinking the
    // text or clipping it. Ordinary Latin text escapes by nothing, so the 12dp
    // default breathing is what applies then.
    final inkEscape = math.max(
      prismTextInkEscape(context, _resolvedTitleStyle(context), text: title),
      subtitle == null
          ? 0.0
          : prismTextInkEscape(
              context,
              _resolvedSubtitleStyle(context),
              text: subtitle!,
            ),
    );
    final breathing = math.max(_grownVerticalPadding, inkEscape * 2 + 2);
    return math.max(
      height,
      math.max(
        PrismTokens.topBarActionSize,
        titleLine + subtitleLine + breathing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Embedded panes close the selection instead of popping a route.
    final isEmbeddedPane = EmbeddedPaneMarker.of(context);
    final paneControls = ListDetailPaneControls.maybeOf(context);
    final clearPaneSelection = paneControls?.clearSelection;
    final showPaneClose = isEmbeddedPane && clearPaneSelection != null;
    final showAutoBack = showBackButton && !isEmbeddedPane;
    final inModalSideSheet = ModalSideSheetMarker.of(context);
    final effectiveLeading =
        leading ??
        (showPaneClose
            ? PrismTopBarAction(
                icon: AppIcons.close,
                tooltip: context.l10n.close,
                onPressed: () =>
                    closeDetailSurface(context, routeBacked: false),
              )
            : showAutoBack
            ? PrismTopBarAction(
                icon: inModalSideSheet ? AppIcons.close : AppIcons.arrowBack,
                tooltip: inModalSideSheet
                    ? context.l10n.close
                    : context.l10n.back,
                onPressed: () => closeDetailSurface(context),
              )
            : null);

    final effectiveTrailing = trailing ?? _buildActions();
    final barHeight = preferredHeightFor(context);

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: barHeight,
        child: Padding(
          padding: horizontalPadding,
          child: NavigationToolbar(
            centerMiddle: centerTitle,
            leading: effectiveLeading == null
                ? null
                : _slot(effectiveLeading, barHeight),
            middle: _TitleBlock(
              title: title,
              subtitle: subtitle,
              centerTitle: centerTitle,
              titleStyle: _resolvedTitleStyle(context),
              subtitleStyle: _resolvedSubtitleStyle(context),
            ),
            trailing: effectiveTrailing == null
                ? null
                : _slot(effectiveTrailing, barHeight),
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

  /// A toolbar slot: as wide as [child], as tall as the bar, child centered.
  ///
  /// `NavigationToolbar` lays its leading child out with the bar's exact height;
  /// the inner `Center` keeps the 44dp action at its real size and vertically
  /// centered, which is where it has always been.
  Widget _slot(Widget child, double barHeight) {
    return SizedBox(
      height: barHeight,
      child: Center(widthFactor: 1, child: child),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.subtitle,
    required this.centerTitle,
    required this.titleStyle,
    required this.subtitleStyle,
  });

  final String title;
  final String? subtitle;
  final bool centerTitle;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final alignment = centerTitle ? TextAlign.center : TextAlign.left;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: centerTitle
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        // Full size, one line, ellipsised: the paragraph keeps the whole string
        // in its semantics, and nothing scales the user's text size down.
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment,
          style: titleStyle,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignment,
            style: subtitleStyle,
          ),
        ],
      ],
    );
  }
}
