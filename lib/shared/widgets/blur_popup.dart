import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// Direction the popup opens relative to the anchor.
enum BlurPopupDirection { up, down }

/// How the popup is triggered.
enum BlurPopupTrigger { tap, longPress, manual }

/// A frosted-glass popup menu that opens above or below an anchor widget.
///
/// Automatically chooses direction based on available space, or you can force
/// a direction with [preferredDirection]. Animates open/closed with scale + fade.
///
/// Usage:
/// ```dart
/// BlurPopupAnchor(
///   itemCount: members.length,
///   itemBuilder: (context, index, close) => ...,
///   child: MyTriggerWidget(),
/// )
/// ```
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

  @override
  State<BlurPopupAnchor> createState() => BlurPopupAnchorState();
}

class BlurPopupAnchorState extends State<BlurPopupAnchor> {
  final _anchorKey = GlobalKey();

  /// Programmatically show the popup. Useful with [BlurPopupTrigger.manual].
  void show() => _showPopup();

  void _showPopup() {
    final renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Find the overlay's RenderBox to transform coordinates into the
    // overlay's coordinate space. This is critical on macOS where the
    // window title bar offsets the overlay from the screen origin.
    final navigator = Navigator.of(context);
    final overlayRenderBox =
        navigator.overlay?.context.findRenderObject() as RenderBox?;

    final anchorSize = renderBox.size;

    // Transform anchor position into overlay-relative coordinates.
    final Offset anchorOffset;
    if (overlayRenderBox != null) {
      anchorOffset =
          renderBox.localToGlobal(Offset.zero, ancestor: overlayRenderBox);
    } else {
      anchorOffset = renderBox.localToGlobal(Offset.zero);
    }

    final overlaySize = overlayRenderBox?.size ?? MediaQuery.of(context).size;

    // Decide direction: how much space above vs below the anchor.
    final spaceAbove = anchorOffset.dy;
    final spaceBelow =
        overlaySize.height - anchorOffset.dy - anchorSize.height;

    final direction = widget.preferredDirection ??
        (spaceAbove > spaceBelow
            ? BlurPopupDirection.up
            : BlurPopupDirection.down);

    navigator.push(_BlurPopupRoute(
      anchorOffset: anchorOffset,
      anchorSize: anchorSize,
      screenSize: overlaySize,
      direction: direction,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
      maxHeight: widget.maxHeight,
      width: widget.width,
      borderRadius: widget.borderRadius,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _anchorKey,
      onTap: widget.trigger == BlurPopupTrigger.tap ? _showPopup : null,
      onLongPress:
          widget.trigger == BlurPopupTrigger.longPress ? _showPopup : null,
      behavior: widget.trigger == BlurPopupTrigger.manual
          ? null
          : HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// Route
// ---------------------------------------------------------------------------

class _BlurPopupRoute extends PopupRoute<void> {
  _BlurPopupRoute({
    required this.anchorOffset,
    required this.anchorSize,
    required this.screenSize,
    required this.direction,
    required this.itemCount,
    required this.itemBuilder,
    required this.maxHeight,
    required this.width,
    required this.borderRadius,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final Size screenSize;
  final BlurPopupDirection direction;
  final int itemCount;
  final Widget Function(BuildContext, int, VoidCallback) itemBuilder;
  final double maxHeight;
  final double width;
  final double borderRadius;

  CurvedAnimation? _cachedCurved;

  @override
  Color? get barrierColor => AppColors.warmBlack.withValues(alpha: 0.15);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  void dispose() {
    _cachedCurved?.dispose();
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    _cachedCurved ??= CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final curved = _cachedCurved!;

    // Scale origin: from the anchor edge.
    final alignment = direction == BlurPopupDirection.up
        ? Alignment.bottomCenter
        : Alignment.topCenter;

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
        alignment: alignment,
        child: child,
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _BlurPopupContent(
      anchorOffset: anchorOffset,
      anchorSize: anchorSize,
      screenSize: screenSize,
      direction: direction,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      maxHeight: maxHeight,
      width: width,
      borderRadius: borderRadius,
      close: () => Navigator.of(context).pop(),
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
  final BlurPopupDirection direction;
  final int itemCount;
  final Widget Function(BuildContext, int, VoidCallback) itemBuilder;
  final double maxHeight;
  final double width;
  final double borderRadius;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOled =
        Theme.of(context).scaffoldBackgroundColor == Colors.black;

    const gap = 8.0;

    // Horizontal: center on anchor, clamped to screen edges.
    var left = anchorOffset.dx + (anchorSize.width / 2) - (width / 2);
    left = left.clamp(12.0, screenSize.width - width - 12.0);

    // Vertical position — use bottom-anchored positioning for "up" so the
    // popup grows upward from the anchor based on actual content size,
    // rather than reserving the full maxHeight.
    final double? top;
    final double? bottom;
    if (direction == BlurPopupDirection.up) {
      top = null;
      bottom = (screenSize.height - anchorOffset.dy + gap)
          .clamp(12.0, screenSize.height - 12.0);
    } else {
      final rawTop = anchorOffset.dy + anchorSize.height + gap;
      // Clamp so the popup doesn't extend past the screen bottom.
      top = rawTop.clamp(12.0, screenSize.height - maxHeight - 12.0);
      bottom = null;
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: PrismTokens.glassBlurStrong,
                  sigmaY: PrismTokens.glassBlurStrong,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? (isOled
                            ? AppColors.oledSurface1
                                .withValues(alpha: 0.85)
                            : AppColors.warmWhite.withValues(alpha: 0.1))
                        : AppColors.warmWhite.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.1)
                          : AppColors.warmBlack.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.warmBlack
                            .withValues(alpha: isDark ? 0.4 : 0.12),
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
