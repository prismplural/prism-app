import 'dart:math' as math;
import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/modal_insets.dart';

/// Direction the popup opens relative to the anchor.
enum BlurPopupDirection { up, down }

/// How the popup is triggered.
enum BlurPopupTrigger { tap, longPress, manual }

double _clampToRange(double value, double lower, double upper) {
  if (upper < lower) return lower;
  return value.clamp(lower, upper).toDouble();
}

/// A frosted-glass popup menu that opens above or below an anchor widget.
///
/// Automatically chooses direction based on available space, or you can force
/// a direction with [preferredDirection]. Animates open/closed with scale + fade.
///
/// Uses [Overlay] instead of [Navigator.push] so the soft keyboard stays open
/// when the popup appears — important for chat input scenarios.
///
/// Usage:
/// ```dart
/// BlurPopupAnchor(
///   itemCount: members.length,
///   itemBuilder: (context, index, close) => ...,
///   child: MyTriggerWidget(),
/// )
/// ```
///
/// Accessibility: callers are responsible for ensuring items built by
/// [itemBuilder] are semantically labelled (via [Semantics.label] or
/// [Tooltip.message]) so screen readers can announce popup actions.
/// The dim barrier is exposed as a localized close action and the overlay
/// blocks background semantics while open.
class BlurPopupAnchor extends StatefulWidget {
  const BlurPopupAnchor({
    super.key,
    required this.child,
    required this.itemCount,
    required this.itemBuilder,
    this.preferredDirection,
    this.trigger = BlurPopupTrigger.tap,
    this.maxHeight = 280,
    this.width = 220,
    this.borderRadius = 16,
    this.semanticLabel,
    this.onBeforeShow,
  });

  /// The trigger widget that opens the popup when tapped.
  final Widget child;

  /// Number of items in the popup.
  final int itemCount;

  /// Builder for each item. Call [close] to dismiss the popup.
  final Widget Function(BuildContext context, int index, VoidCallback close)
  itemBuilder;

  /// Force a direction, or null to auto-detect.
  final BlurPopupDirection? preferredDirection;

  /// How the popup is opened. [BlurPopupTrigger.manual] disables the built-in
  /// gesture — use [BlurPopupAnchor.show] via a GlobalKey instead.
  final BlurPopupTrigger trigger;

  /// Maximum height of the popup content area.
  final double maxHeight;

  /// Width of the popup.
  final double width;

  /// Corner radius.
  final double borderRadius;

  /// Accessibility label announced by screen readers when the trigger is
  /// interactive ([BlurPopupTrigger.tap] or [BlurPopupTrigger.longPress]).
  final String? semanticLabel;

  /// Called immediately before the popup is shown.
  ///
  /// Useful for callers that need to adjust focus before the overlay measures
  /// its anchor and visible bounds.
  final VoidCallback? onBeforeShow;

  @override
  State<BlurPopupAnchor> createState() => BlurPopupAnchorState();
}

class BlurPopupAnchorState extends State<BlurPopupAnchor>
    with SingleTickerProviderStateMixin {
  final _anchorKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  LocalHistoryEntry? _historyEntry;
  bool _removingHistoryEntry = false;
  bool _positionedAtCursor = false;
  GoRouter? _routeDismissRouter;
  Uri? _routeUriWhenShown;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _removeOverlay(animate: false);
    _animController.dispose();
    super.dispose();
  }

  /// Programmatically show the popup. Useful with [BlurPopupTrigger.manual].
  void show() {
    _showPopup();
  }

  bool _showPopup({Offset? atPosition}) {
    if (_overlayEntry != null) return false; // already showing
    widget.onBeforeShow?.call();

    final overlay = Overlay.of(context);
    final overlayRenderBox = overlay.context.findRenderObject() as RenderBox?;

    final Size anchorSize;
    final Offset anchorOffset;

    if (atPosition != null) {
      // Cursor-positioned: use cursor point as anchor.
      _positionedAtCursor = true;
      anchorSize = Size.zero;
      if (overlayRenderBox != null) {
        anchorOffset = overlayRenderBox.globalToLocal(atPosition);
      } else {
        anchorOffset = atPosition;
      }
    } else {
      _positionedAtCursor = false;
      final renderBox =
          _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return false;
      anchorSize = renderBox.size;
      if (overlayRenderBox != null) {
        anchorOffset = renderBox.localToGlobal(
          Offset.zero,
          ancestor: overlayRenderBox,
        );
      } else {
        anchorOffset = renderBox.localToGlobal(Offset.zero);
      }
    }

    final overlaySize = overlayRenderBox?.size ?? MediaQuery.of(context).size;
    final view = View.of(context);
    final viewBottomInset =
        math.max(view.viewInsets.bottom, view.viewPadding.bottom) /
        view.devicePixelRatio;
    final bottomInset = math.max(modalBottomInsetOf(context), viewBottomInset);
    final visibleBottom = (overlaySize.height - bottomInset)
        .clamp(0.0, overlaySize.height)
        .toDouble();
    final visibleBounds = Rect.fromLTRB(0, 0, overlaySize.width, visibleBottom);

    // Decide direction: how much space above vs below the anchor. Fixed at
    // show time so the popup does not flip if insets change later.
    final spaceAbove = anchorOffset.dy - visibleBounds.top;
    final spaceBelow =
        visibleBounds.bottom - anchorOffset.dy - anchorSize.height;

    final direction =
        widget.preferredDirection ??
        (spaceAbove > spaceBelow
            ? BlurPopupDirection.up
            : BlurPopupDirection.down);

    final curved = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _BlurPopupOverlay(
          animation: curved,
          anchorKey: _anchorKey,
          fallbackAnchorOffset: anchorOffset,
          fallbackAnchorSize: anchorSize,
          fallbackScreenSize: overlaySize,
          positionedAtCursor: _positionedAtCursor,
          direction: direction,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
          maxHeight: widget.maxHeight,
          width: widget.width,
          borderRadius: widget.borderRadius,
          onDismiss: () => _removeOverlay(animate: true),
        );
      },
    );

    overlay.insert(_overlayEntry!);
    _startRouteDismissListener();
    final route = ModalRoute.of(context);
    if (route != null) {
      final historyEntry = LocalHistoryEntry(
        onRemove: () {
          if (_removingHistoryEntry) return;
          _historyEntry = null;
          unawaited(_removeOverlay(animate: true, removeHistoryEntry: false));
        },
      );
      route.addLocalHistoryEntry(historyEntry);
      _historyEntry = historyEntry;
    }
    _animController.forward(from: 0);
    return true;
  }

  void _startRouteDismissListener() {
    _stopRouteDismissListener();
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    _routeDismissRouter = router;
    _routeUriWhenShown = router.routeInformationProvider.value.uri;
    router.routeInformationProvider.addListener(_handleRouteChanged);
  }

  void _stopRouteDismissListener() {
    _routeDismissRouter?.routeInformationProvider.removeListener(
      _handleRouteChanged,
    );
    _routeDismissRouter = null;
    _routeUriWhenShown = null;
  }

  void _handleRouteChanged() {
    final router = _routeDismissRouter;
    final shownUri = _routeUriWhenShown;
    if (router == null || shownUri == null) return;
    if (router.routeInformationProvider.value.uri == shownUri) return;
    unawaited(_removeOverlay(animate: true));
  }

  void _handleLongPress() {
    final didOpen = _showPopup();
    if (didOpen) Haptics.selection();
  }

  void _handleTap() {
    _showPopup();
  }

  void _handleSecondaryTapDown(TapDownDetails details) {
    final didOpen = _showPopup(atPosition: details.globalPosition);
    if (didOpen) Haptics.selection();
  }

  Future<void> _removeOverlay({
    required bool animate,
    bool removeHistoryEntry = true,
  }) async {
    final overlayEntry = _overlayEntry;
    if (overlayEntry == null) return;
    _stopRouteDismissListener();

    final historyEntry = _historyEntry;
    if (removeHistoryEntry && historyEntry != null) {
      _removingHistoryEntry = true;
      historyEntry.remove();
      _removingHistoryEntry = false;
      _historyEntry = null;
    } else if (!removeHistoryEntry) {
      _historyEntry = null;
    }

    if (animate && mounted) {
      try {
        await _animController.reverse().orCancel;
      } catch (_) {
        // The anchor can be disposed while a popup is closing, for example
        // when navigation replaces the current screen. In that case dispose()
        // performs the immediate overlay removal below.
      }
    }
    final shouldRemoveOverlay = _overlayEntry == overlayEntry;
    if (shouldRemoveOverlay) {
      _overlayEntry = null;
      overlayEntry.remove();
    }
    _positionedAtCursor = false;
  }

  @override
  Widget build(BuildContext context) {
    // TextFieldTapRegion prevents this tap from unfocusing a nearby TextField,
    // which would dismiss the soft keyboard.
    return Semantics(
      button: widget.trigger != BlurPopupTrigger.manual,
      label: widget.semanticLabel,
      child: TextFieldTapRegion(
        child: MouseRegion(
          cursor: widget.trigger != BlurPopupTrigger.manual
              ? SystemMouseCursors.contextMenu
              : SystemMouseCursors.basic,
          child: GestureDetector(
            key: _anchorKey,
            onTap: widget.trigger == BlurPopupTrigger.tap ? _handleTap : null,
            onLongPress: widget.trigger == BlurPopupTrigger.longPress
                ? _handleLongPress
                : null,
            onSecondaryTapDown: widget.trigger != BlurPopupTrigger.manual
                ? _handleSecondaryTapDown
                : null,
            behavior: widget.trigger == BlurPopupTrigger.manual
                ? null
                : HitTestBehavior.opaque,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay wrapper (barrier + animated content)
// ---------------------------------------------------------------------------

class _BlurPopupOverlay extends StatelessWidget {
  const _BlurPopupOverlay({
    required this.animation,
    required this.anchorKey,
    required this.fallbackAnchorOffset,
    required this.fallbackAnchorSize,
    required this.fallbackScreenSize,
    required this.positionedAtCursor,
    required this.direction,
    required this.itemCount,
    required this.itemBuilder,
    required this.maxHeight,
    required this.width,
    required this.borderRadius,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final GlobalKey anchorKey;
  // Fallbacks used only if the anchor RenderBox can't be re-measured.
  final Offset fallbackAnchorOffset;
  final Size fallbackAnchorSize;
  final Size fallbackScreenSize;
  final bool positionedAtCursor;
  final BlurPopupDirection direction;
  final int itemCount;
  final Widget Function(BuildContext, int, VoidCallback) itemBuilder;
  final double maxHeight;
  final double width;
  final double borderRadius;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // Reading MediaQuery here registers an inset dependency so this overlay
    // rebuilds when the soft keyboard shows/hides. Without it the popup
    // would stay anchored at the old bar position and slip behind the keyboard
    // when the keyboard rises after the popup opens.
    final mediaQuery = MediaQuery.of(context);
    final overlayRenderBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchorRenderBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;

    final Size screenSize;
    final Offset anchorOffset;
    final Size anchorSize;
    if (!positionedAtCursor &&
        anchorRenderBox != null &&
        anchorRenderBox.attached &&
        anchorRenderBox.hasSize) {
      anchorSize = anchorRenderBox.size;
      anchorOffset = overlayRenderBox != null
          ? anchorRenderBox.localToGlobal(
              Offset.zero,
              ancestor: overlayRenderBox,
            )
          : anchorRenderBox.localToGlobal(Offset.zero);
      screenSize = overlayRenderBox?.size ?? fallbackScreenSize;
    } else {
      anchorOffset = fallbackAnchorOffset;
      anchorSize = fallbackAnchorSize;
      screenSize = fallbackScreenSize;
    }

    final bottomInset = math.max(
      mediaQuery.viewInsets.bottom,
      mediaQuery.viewPadding.bottom,
    );
    final visibleBottom = (screenSize.height - bottomInset)
        .clamp(0.0, screenSize.height)
        .toDouble();
    final visibleBounds = Rect.fromLTRB(0, 0, screenSize.width, visibleBottom);

    // Scale origin: from the anchor edge.
    final alignment = direction == BlurPopupDirection.up
        ? Alignment.bottomCenter
        : Alignment.topCenter;

    return TextFieldTapRegion(
      child: BlockSemantics(
        child: Stack(
          // Clip.none so the ScaleTransition on the popup content does not clip
          // the anchor chip during the open/close animation. The popup list itself
          // is clipped by ClipRRect inside _BlurPopupContent.
          clipBehavior: Clip.none,
          children: [
            // Barrier — dismisses on tap, tinted overlay.
            Positioned.fill(
              child: Semantics(
                button: true,
                label: context.l10n.close,
                onTap: onDismiss,
                child: GestureDetector(
                  onTap: onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: FadeTransition(
                    opacity: animation,
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
            ),
            // Popup content
            Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                  alignment: alignment,
                  child: _BlurPopupContent(
                    anchorOffset: anchorOffset,
                    anchorSize: anchorSize,
                    screenSize: screenSize,
                    visibleBounds: visibleBounds,
                    direction: direction,
                    itemCount: itemCount,
                    itemBuilder: itemBuilder,
                    maxHeight: maxHeight,
                    width: width,
                    borderRadius: borderRadius,
                    close: onDismiss,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

class _BlurPopupContent extends StatelessWidget {
  const _BlurPopupContent({
    required this.anchorOffset,
    required this.anchorSize,
    required this.screenSize,
    required this.visibleBounds,
    required this.direction,
    required this.itemCount,
    required this.itemBuilder,
    required this.maxHeight,
    required this.width,
    required this.borderRadius,
    required this.close,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final Size screenSize;
  final Rect visibleBounds;
  final BlurPopupDirection direction;
  final int itemCount;
  final Widget Function(BuildContext, int, VoidCallback) itemBuilder;
  final double maxHeight;
  final double width;
  final double borderRadius;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isOled = theme.scaffoldBackgroundColor == Colors.black;

    const gap = 8.0;
    const edgePadding = 12.0;
    final availableWidth = math.max(0.0, visibleBounds.width - edgePadding * 2);
    final effectiveWidth = math.min(width, availableWidth);

    // Horizontal: center on anchor, clamped to screen edges.
    var left = anchorOffset.dx + (anchorSize.width / 2) - (effectiveWidth / 2);
    left = _clampToRange(
      left,
      visibleBounds.left + edgePadding,
      visibleBounds.right - effectiveWidth - edgePadding,
    );

    // Vertical position — use bottom-anchored positioning for "up" so the
    // popup grows upward from the anchor based on actual content size,
    // rather than reserving the full maxHeight.
    final double? top;
    final double? bottom;
    final double effectiveMaxHeight;
    final visibleTop = visibleBounds.top + edgePadding;
    final visibleBottom = visibleBounds.bottom - edgePadding;
    final visibleHeight = math.max(0.0, visibleBottom - visibleTop);
    final minVisibleHeight = math.min(44.0, visibleHeight);
    if (direction == BlurPopupDirection.up) {
      top = null;
      bottom = _clampToRange(
        screenSize.height - anchorOffset.dy + gap,
        screenSize.height - visibleBottom,
        screenSize.height - visibleTop - minVisibleHeight,
      );
      final popupBottomY = screenSize.height - bottom;
      effectiveMaxHeight = _clampToRange(
        popupBottomY - visibleTop,
        0,
        maxHeight,
      );
    } else {
      final rawTop = anchorOffset.dy + anchorSize.height + gap;
      top = _clampToRange(rawTop, visibleTop, visibleBottom - minVisibleHeight);
      bottom = null;
      effectiveMaxHeight = _clampToRange(visibleBottom - top, 0, maxHeight);
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: effectiveWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                PrismShapes.of(context).radius(borderRadius),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: PrismTokens.glassBlurStrong,
                  sigmaY: PrismTokens.glassBlurStrong,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        (isDark
                                ? (isOled
                                      ? colors.surfaceContainerLow
                                      : colors.surfaceContainerHigh)
                                : colors.surfaceContainerLow)
                            .withValues(alpha: isDark ? 0.86 : 0.78),
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(borderRadius),
                    ),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(
                        alpha: isDark ? 0.42 : 0.44,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(
                          alpha: isDark ? 0.4 : 0.12,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: itemCount,
                      itemBuilder: (ctx, i) {
                        // When opening upward, reverse item order so the
                        // first item (e.g. quick reactions) appears closest
                        // to the anchor / the user's finger.
                        final mapped = direction == BlurPopupDirection.up
                            ? itemCount - 1 - i
                            : i;
                        return itemBuilder(ctx, mapped, close);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
