import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';

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

  @override
  State<BlurPopupAnchor> createState() => BlurPopupAnchorState();
}

class BlurPopupAnchorState extends State<BlurPopupAnchor>
    with SingleTickerProviderStateMixin {
  final _anchorKey = GlobalKey();
  OverlayEntry? _overlayEntry;
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

  bool _showPopup() {
    if (_overlayEntry != null) return false; // already showing

    final renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return false;

    final overlay = Overlay.of(context);
    final overlayRenderBox = overlay.context.findRenderObject() as RenderBox?;

    final anchorSize = renderBox.size;

    // Transform anchor position into overlay-relative coordinates.
    final Offset anchorOffset;
    if (overlayRenderBox != null) {
      anchorOffset = renderBox.localToGlobal(
        Offset.zero,
        ancestor: overlayRenderBox,
      );
    } else {
      anchorOffset = renderBox.localToGlobal(Offset.zero);
    }

    final overlaySize = overlayRenderBox?.size ?? MediaQuery.of(context).size;
    final view = View.of(context);
    final bottomInset = math.max(
      MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0,
      view.viewInsets.bottom / view.devicePixelRatio,
    );
    final visibleBottom = (overlaySize.height - bottomInset)
        .clamp(0.0, overlaySize.height)
        .toDouble();
    final visibleBounds = Rect.fromLTRB(0, 0, overlaySize.width, visibleBottom);

    // Decide direction: how much space above vs below the anchor.
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
          anchorOffset: anchorOffset,
          anchorSize: anchorSize,
          screenSize: overlaySize,
          visibleBounds: visibleBounds,
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
    _animController.forward(from: 0);
    return true;
  }

  void _handleLongPress() {
    final didOpen = _showPopup();
    if (didOpen) Haptics.selection();
  }

  void _handleTap() {
    _showPopup();
  }

  Future<void> _removeOverlay({required bool animate}) async {
    if (_overlayEntry == null) return;
    if (animate && mounted) {
      await _animController.reverse();
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    // TextFieldTapRegion prevents this tap from unfocusing a nearby TextField,
    // which would dismiss the soft keyboard.
    return Semantics(
      button: widget.trigger != BlurPopupTrigger.manual,
      label: widget.semanticLabel,
      child: TextFieldTapRegion(
        child: GestureDetector(
          key: _anchorKey,
          onTap: widget.trigger == BlurPopupTrigger.tap ? _handleTap : null,
          onLongPress: widget.trigger == BlurPopupTrigger.longPress
              ? _handleLongPress
              : null,
          behavior: widget.trigger == BlurPopupTrigger.manual
              ? null
              : HitTestBehavior.opaque,
          child: widget.child,
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
    required this.onDismiss,
  });

  final Animation<double> animation;
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
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
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
                      color: AppColors.warmBlack.withValues(alpha: 0.15),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOled = Theme.of(context).scaffoldBackgroundColor == Colors.black;

    const gap = 8.0;
    const edgePadding = 12.0;

    // Horizontal: center on anchor, clamped to screen edges.
    var left = anchorOffset.dx + (anchorSize.width / 2) - (width / 2);
    left = _clampToRange(
      left,
      visibleBounds.left + edgePadding,
      visibleBounds.right - width - edgePadding,
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
          width: width,
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
                    color: isDark
                        ? (isOled
                              ? AppColors.oledSurface1.withValues(alpha: 0.85)
                              : AppColors.warmWhite.withValues(alpha: 0.1))
                        : AppColors.warmWhite.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(
                      PrismShapes.of(context).radius(borderRadius),
                    ),
                    border: Border.all(
                      color: isDark
                          ? AppColors.warmWhite.withValues(alpha: 0.1)
                          : AppColors.warmBlack.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.warmBlack.withValues(
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
