import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/detail_side_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/sheet_presentation.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

/// Adaptive Prism sheet wrapper.
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

  /// Show an adaptive Prism sheet.
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
  }) async {
    AdaptiveSheetLayout layout;
    if (supportsDesktopDetailLayout(context)) {
      layout = resolveAdaptiveSheetLayout(
        context,
        role: AdaptiveSheetRole.transientSheet,
      );
    } else {
      layout = AdaptiveSheetLayout.centeredSheet;
    }

    if (layout == AdaptiveSheetLayout.sideSheet) {
      return _showSideSheet<T>(
        context: context,
        builder: builder,
        title: title,
        subtitle: subtitle,
        actions: actions,
        useRootNavigator: useRootNavigator,
        isDismissible: isDismissible,
        minHeightFactor: minHeightFactor,
        maxHeightFactor: maxHeightFactor,
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      // _SheetChrome owns drag-to-dismiss so PopScope can veto cleanly.
      enableDrag: false,
      // Omit backgroundColor so long-lived sheets follow theme changes.
      // _SheetChrome renders the drag handle.
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            PrismShapes.of(context).radius(PrismTokens.radiusLarge),
          ),
        ),
      ),
      builder: (sheetContext) {
        final dismissController = UnsavedChangesDismissController();
        Widget content = builder(sheetContext);

        if (title != null || subtitle != null || actions != null) {
          content = PrismSheet(
            title: title,
            subtitle: subtitle,
            actions: actions,
            child: content,
          );
        }

        content = _SheetChrome(
          isDismissible: isDismissible,
          dismissController: dismissController,
          child: content,
        );

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

        return UnsavedChangesDismissScope(
          controller: dismissController,
          child: content,
        );
      },
    );
  }

  /// Show a full-height adaptive Prism sheet.
  static Future<T?> showFullScreen<T>({
    required BuildContext context,
    required Widget Function(
      BuildContext context,
      ScrollController scrollController,
    )
    builder,
    bool useRootNavigator = true,
    bool isDismissible = true,
  }) async {
    AdaptiveSheetLayout layout;
    if (supportsDesktopDetailLayout(context)) {
      layout = resolveAdaptiveSheetLayout(
        context,
        role: AdaptiveSheetRole.transientSheet,
      );
    } else {
      layout = AdaptiveSheetLayout.centeredSheet;
    }

    if (layout == AdaptiveSheetLayout.sideSheet) {
      return _showFullScreenSideSheet<T>(
        context: context,
        builder: builder,
        useRootNavigator: useRootNavigator,
        isDismissible: isDismissible,
      );
    }

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
      // Omit backgroundColor — see PrismSheet.show for the theme-transition
      // rationale.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            PrismShapes.of(context).radius(PrismTokens.radiusLarge),
          ),
        ),
      ),
      builder: (sheetContext) {
        final dismissController = UnsavedChangesDismissController();
        return UnsavedChangesDismissScope(
          controller: dismissController,
          child: _FullScreenSheetBody<T>(
            isDismissible: isDismissible,
            dismissController: dismissController,
            builder: builder,
          ),
        );
      },
    );
  }

  static Future<T?> _showSideSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    String? subtitle,
    List<Widget>? actions,
    required bool useRootNavigator,
    required bool isDismissible,
    double? minHeightFactor,
    double? maxHeightFactor,
  }) {
    final dismissController = UnsavedChangesDismissController();

    return showDetailSideSheet<T>(
      context,
      useRootNavigator: useRootNavigator,
      dismissible: isDismissible,
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

        return UnsavedChangesDismissScope(
          controller: dismissController,
          child: _SideSheetKeyboardInset(child: content),
        );
      },
    );
  }

  static Future<T?> _showFullScreenSideSheet<T>({
    required BuildContext context,
    required Widget Function(
      BuildContext context,
      ScrollController scrollController,
    )
    builder,
    required bool useRootNavigator,
    required bool isDismissible,
  }) {
    final dismissController = UnsavedChangesDismissController();

    return showDetailSideSheet<T>(
      context,
      useRootNavigator: useRootNavigator,
      dismissible: isDismissible,
      builder: (sheetContext) {
        return UnsavedChangesDismissScope(
          controller: dismissController,
          child: _SideSheetKeyboardInset(
            child: _FullScreenSideSheetBody(builder: builder),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = modalBottomInsetOf(context);

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

class _SideSheetKeyboardInset extends StatelessWidget {
  const _SideSheetKeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.decelerate,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }
}

class _FullScreenSideSheetBody extends StatefulWidget {
  const _FullScreenSideSheetBody({required this.builder});

  final Widget Function(BuildContext, ScrollController) builder;

  @override
  State<_FullScreenSideSheetBody> createState() =>
      _FullScreenSideSheetBodyState();
}

class _FullScreenSideSheetBodyState extends State<_FullScreenSideSheetBody> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: widget.builder(context, _scrollController));
  }
}

/// Bridges [DraggableScrollableSheet] with the modal route so that dragging
/// below a threshold actually pops the route (and its scrim) instead of
/// leaving an invisible sheet with a lingering barrier.
class _FullScreenSheetBody<T> extends StatefulWidget {
  const _FullScreenSheetBody({
    required this.isDismissible,
    required this.dismissController,
    required this.builder,
  });

  final bool isDismissible;
  final UnsavedChangesDismissController dismissController;
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
      _tryDismissFromDrag();
    }
  }

  Future<void> _tryDismissFromDrag() async {
    if (widget.dismissController.hasUnsavedChanges) {
      await _restoreSheet();
      if (!mounted) return;
      final shouldDiscard = await widget.dismissController
          .confirmDiscardIfNeeded();
      if (shouldDiscard && mounted) Navigator.of(context).pop();
      if (mounted) _popping = false;
      return;
    }

    Navigator.of(context).pop();
  }

  Future<void> _restoreSheet() async {
    if (_controller.isAttached) {
      await _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
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
      shouldCloseOnMinExtent: false,
      builder: (sheetContext, scrollController) {
        // showModalBottomSheet does not resize the route around the
        // keyboard, and DraggableScrollableSheet always claims the full
        // parent height — so without this padding, the sheet's viewport
        // extends behind the keyboard and Scrollable.ensureVisible (which
        // EditableText calls on focus) thinks fields hidden behind the
        // keyboard are already on-screen. Shrinking the viewport by
        // viewInsets.bottom lets the focused field auto-scroll above the
        // keyboard.
        return AnimatedPadding(
          duration: const Duration(milliseconds: 100),
          curve: Curves.decelerate,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: MediaQuery.removeViewInsets(
            context: sheetContext,
            removeBottom: true,
            child: widget.builder(sheetContext, scrollController),
          ),
        );
      },
    );
  }
}

/// Internal chrome wrapper that adds the drag handle above the sheet content.
class _SheetChrome extends StatefulWidget {
  const _SheetChrome({
    required this.isDismissible,
    required this.dismissController,
    required this.child,
  });

  final bool isDismissible;
  final UnsavedChangesDismissController dismissController;
  final Widget child;

  @override
  State<_SheetChrome> createState() => _SheetChromeState();
}

class _SheetChromeState extends State<_SheetChrome> {
  double _dragOffset = 0;
  bool _resettingDrag = false;
  bool _dismissAttemptInFlight = false;

  bool get _canDrag => widget.isDismissible && !_dismissAttemptInFlight;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_canDrag) return;

    final delta = details.primaryDelta ?? 0;
    final nextOffset = _dragOffset + delta;
    setState(() {
      _resettingDrag = false;
      _dragOffset = nextOffset < 0 ? 0 : nextOffset;
    });
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    if (!_canDrag) return;

    final velocity = details.velocity.pixelsPerSecond.dy;
    final shouldDismiss = _dragOffset > 96 || velocity > 700;
    if (!shouldDismiss) {
      _resetDrag();
      return;
    }

    _dismissAttemptInFlight = true;
    if (widget.dismissController.hasUnsavedChanges) {
      _resetDrag();
      if (!mounted) return;
      final shouldDiscard = await widget.dismissController
          .confirmDiscardIfNeeded();
      if (shouldDiscard && mounted) Navigator.of(context).pop();
    } else {
      Navigator.of(context).pop();
    }

    if (!mounted) return;
    _dismissAttemptInFlight = false;
  }

  void _resetDrag() {
    if (!mounted) return;
    setState(() {
      _resettingDrag = true;
      _dragOffset = 0;
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _resettingDrag = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = AnimatedContainer(
      duration: _resettingDrag
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _dragOffset, 0),
      child: Column(
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
          Flexible(child: widget.child),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: widget.isDismissible ? _handleDragUpdate : null,
      onVerticalDragEnd: widget.isDismissible ? _handleDragEnd : null,
      onVerticalDragCancel: widget.isDismissible ? _resetDrag : null,
      child: content,
    );
  }
}

/// A top bar for full-screen sheets with close button, centered title, and
/// an optional trailing widget (typically a [PrismGlassIconButton]).
///
/// Matches [PrismTopBar] sizing: 44pt action slots, titleLarge at 22/w700.
///
/// When [titleWidget] is provided it replaces the text title in the center
/// area, automatically inset by [PrismTokens.topBarActionSize] on each side.
///
class PrismSheetTopBar extends StatelessWidget {
  const PrismSheetTopBar({
    super.key,
    required this.title,
    this.trailing,
    this.titleWidget,
    this.leading,
  });

  final String title;

  /// Optional trailing widget (e.g. a done/confirm button).
  final Widget? trailing;

  /// When set, replaces the text title. Automatically inset by
  /// [PrismTokens.topBarActionSize] on each side so it never overlaps the
  /// leading/trailing action buttons.
  final Widget? titleWidget;

  /// Replaces the default close button. Size to [PrismTokens.topBarActionSize].
  final Widget? leading;

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
            if (titleWidget != null)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: titleWidget,
                ),
              )
            else
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  leading ??
                  PrismGlassIconButton(
                    icon: AppIcons.close,
                    size: PrismTokens.topBarActionSize,
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: context.l10n.close,
                    semanticLabel: context.l10n.close,
                  ),
            ),
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing!),
          ],
        ),
      ),
    );
  }
}
