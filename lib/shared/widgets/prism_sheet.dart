import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/unsaved_changes_guard.dart';

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
      // Flutter's built-in modal drag moves the sheet before asking the route
      // whether it can pop. That leaves dirty PopScope-guarded sheets collapsed
      // behind an active barrier, so _SheetChrome owns drag-to-dismiss instead.
      enableDrag: false,
      // Intentionally omit backgroundColor so Flutter's _ModalBottomSheet
      // resolves it from Theme.of(context).bottomSheetTheme at every rebuild.
      // Passing an explicit color snapshots it at open time and leaves the
      // sheet stuck on the old theme when the system flips light↔dark while
      // a long-lived sheet (e.g. export) is open.
      // Suppress the stock M3 drag handle — _SheetChrome renders its own.
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
    required Widget Function(
      BuildContext context,
      ScrollController scrollController,
    )
    builder,
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
      builder: widget.builder,
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
class PrismSheetTopBar extends StatelessWidget {
  const PrismSheetTopBar({
    super.key,
    required this.title,
    this.trailing,
    this.titleWidget,
  });

  final String title;

  /// Optional trailing widget (e.g. a done/confirm button).
  final Widget? trailing;

  /// When set, replaces the text title. Automatically inset by
  /// [PrismTokens.topBarActionSize] on each side so it never overlaps the
  /// leading/trailing action buttons.
  final Widget? titleWidget;

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
              child: PrismGlassIconButton(
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
