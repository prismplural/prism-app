import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';

/// A styled bottom sheet wrapper with consistent Prism design language.
///
/// Use [PrismSheet.show] to present a bottom sheet with a drag handle, optional
/// title/subtitle, body content, and an action row.
class PrismSheet extends StatelessWidget {
  const PrismSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.actions,
  });

  /// Optional title rendered as `titleLarge`.
  final String? title;

  /// Optional subtitle rendered below the title.
  final String? subtitle;

  /// The main body content of the sheet.
  final Widget child;

  /// Optional action row at the bottom (typically [PrismButton] widgets).
  final List<Widget>? actions;

  /// Show a Prism-styled bottom sheet.
  ///
  /// Wraps [showModalBottomSheet] with consistent styling: rounded top corners,
  /// drag handle, safe area insets, and keyboard-aware padding.
  ///
  /// If [title], [subtitle], or [actions] are provided they are composed into a
  /// [PrismSheet] container around the [builder] output. Otherwise the [builder]
  /// result is used directly.
  ///
  /// Use [minHeightFactor] and [maxHeightFactor] (fractions of screen height,
  /// 0.0–1.0) to bound sheet height for scrollable list-style sheets. When
  /// omitted the sheet sizes to its natural content height.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    String? subtitle,
    List<Widget>? actions,
    bool useRootNavigator = true,
    bool isDismissible = true,
    double? minHeightFactor,
    double? maxHeightFactor,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      // Suppress the stock M3 drag handle — _SheetChrome renders its own.
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PrismTokens.radiusLarge),
        ),
      ),
      builder: (sheetContext) {
        Widget content = builder(sheetContext);

        if (title != null || subtitle != null || actions != null) {
          content = PrismSheet(
            title: title,
            subtitle: subtitle,
            actions: actions,
            child: content,
          );
        }

        content = _SheetChrome(child: content);

        if (minHeightFactor != null || maxHeightFactor != null) {
          final screenHeight = MediaQuery.sizeOf(sheetContext).height;
          content = ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight * (minHeightFactor ?? 0.0),
              maxHeight: screenHeight * (maxHeightFactor ?? 1.0),
            ),
            child: content,
          );
        }

        return content;
      },
    );
  }

  /// Show a full-screen Prism-styled bottom sheet.
  ///
  /// Opens at full height with no drag handle, but still swipeable to dismiss.
  /// The [builder] receives a [ScrollController] — attach it to the primary
  /// scrollable so dragging the list can also dismiss the sheet.
  ///
  /// Use [PrismSheetTopBar] inside the builder for a consistent top bar with
  /// close button, centered title, and optional trailing action.
  static Future<T?> showFullScreen<T>({
    required BuildContext context,
    required Widget Function(BuildContext context, ScrollController scrollController) builder,
    bool useRootNavigator = true,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      // Disable the modal's own drag-to-dismiss — we let the
      // DraggableScrollableSheet handle it to avoid two competing
      // gesture detectors.
      enableDrag: false,
      showDragHandle: false,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PrismTokens.radiusLarge),
        ),
      ),
      builder: (sheetContext) => _FullScreenSheetBody<T>(
        isDismissible: isDismissible,
        builder: builder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: PrismTokens.pageHorizontalPadding,
        right: PrismTokens.pageHorizontalPadding,
        top: 16,
        bottom: 16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          child,
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (int i = 0; i < actions!.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions![i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bridges [DraggableScrollableSheet] with the modal route so that dragging
/// below a threshold actually pops the route (and its scrim) instead of
/// leaving an invisible sheet with a lingering barrier.
class _FullScreenSheetBody<T> extends StatefulWidget {
  const _FullScreenSheetBody({
    required this.isDismissible,
    required this.builder,
  });

  final bool isDismissible;
  final Widget Function(BuildContext, ScrollController) builder;

  @override
  State<_FullScreenSheetBody<T>> createState() =>
      _FullScreenSheetBodyState<T>();
}

class _FullScreenSheetBodyState<T> extends State<_FullScreenSheetBody<T>> {
  final _controller = DraggableScrollableController();
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    if (widget.isDismissible) {
      _controller.addListener(_onSizeChanged);
    }
  }

  void _onSizeChanged() {
    // When the sheet is dragged below 40% height, dismiss the route.
    if (!_popping && _controller.size < 0.4) {
      _popping = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onSizeChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: 1.0,
      minChildSize: widget.isDismissible ? 0.0 : 1.0,
      maxChildSize: 1.0,
      expand: false,
      snap: true,
      snapSizes: const [1.0],
      builder: widget.builder,
    );
  }
}

/// Internal chrome wrapper that adds the drag handle above the sheet content.
class _SheetChrome extends StatelessWidget {
  const _SheetChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(child: child),
      ],
    );
  }
}

/// A top bar for full-screen sheets with close button, centered title, and
/// an optional trailing widget (typically a [PrismGlassIconButton]).
///
/// Matches [PrismTopBar] sizing: 44pt action slots, titleLarge at 22/w700.
class PrismSheetTopBar extends StatelessWidget {
  const PrismSheetTopBar({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;

  /// Optional trailing widget (e.g. a done/confirm button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: PrismTokens.topBarHeight,
      child: Padding(
        padding: PrismTokens.topBarPadding,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: PrismGlassIconButton(
                icon: AppIcons.close,
                size: PrismTokens.topBarActionSize,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (trailing != null)
              Align(
                alignment: Alignment.centerRight,
                child: trailing!,
              ),
          ],
        ),
      ),
    );
  }
}
