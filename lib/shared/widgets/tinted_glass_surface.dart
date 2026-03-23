import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// A cheap faux-glass surface that achieves a glassy appearance through
/// translucent fill, directional highlight gradient, hairline border, and
/// drop shadow — with NO BackdropFilter.
///
/// Use this instead of [GlassSurface] for list-level widgets where repeated
/// backdrop blur would be too expensive. Visually "glassy enough" at lower
/// rendering cost.
///
/// Responds to [VisualEffectsMode.accessible]: raises fill opacity, strengthens
/// border, and removes the highlight gradient for better contrast.
class TintedGlassSurface extends ConsumerWidget {
  const TintedGlassSurface({
    super.key,
    required this.child,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.width,
    this.height,
    this.tint,
    this.padding,
    this.borderWidth = PrismTokens.hairlineBorderWidth,
  });

  /// Convenience constructor for circular tinted glass surfaces.
  const TintedGlassSurface.circle({
    super.key,
    required this.child,
    required double size,
    this.tint,
    this.padding,
    this.borderWidth = PrismTokens.hairlineBorderWidth,
  }) : shape = BoxShape.circle,
       borderRadius = null,
       width = size,
       height = size;

  final Widget child;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final double? width;
  final double? height;

  /// Optional tint color blended into the fill. Same pattern as [GlassSurface].
  final Color? tint;
  final EdgeInsets? padding;
  final double borderWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = VisualEffectsModeX.of(context, ref);
    final isAccessible = mode.highContrast;

    // --- Fill color ---
    // Base translucency differs by brightness; accessible mode raises opacity.
    final double baseFillAlpha = isDark
        ? PrismTokens.tintedFillAlphaDark + (isAccessible ? 0.15 : 0.0)
        : PrismTokens.tintedFillAlphaLight + (isAccessible ? 0.15 : 0.0);

    final Color baseColor = isDark
        ? Colors.white.withValues(alpha: baseFillAlpha)
        : Colors.white.withValues(alpha: baseFillAlpha);

    final Color fillColor = tint != null
        ? Color.alphaBlend(tint!.withValues(alpha: 0.15), baseColor)
        : baseColor;

    // --- Border color ---
    final double borderAlpha = isDark
        ? PrismTokens.tintedBorderAlphaDark + (isAccessible ? 0.10 : 0.0)
        : PrismTokens.tintedBorderAlphaLight + (isAccessible ? 0.10 : 0.0);

    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: borderAlpha)
        : Colors.black.withValues(alpha: borderAlpha);

    // --- Shadow ---
    final double shadowAlpha = isDark
        ? PrismTokens.tintedShadowAlphaDark
        : PrismTokens.tintedShadowAlphaLight;

    final List<BoxShadow> shadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: shadowAlpha),
        blurRadius: PrismTokens.tintedShadowBlur,
        offset: const Offset(0, 2),
      ),
    ];

    // --- Shape helpers ---
    final effectiveBorderRadius = shape == BoxShape.circle
        ? null
        : (borderRadius ?? BorderRadius.circular(PrismTokens.radiusMedium));

    // --- Highlight gradient (suppressed in accessible mode) ---
    final Decoration? highlightDecoration = isAccessible
        ? null
        : BoxDecoration(
            shape: shape,
            borderRadius: effectiveBorderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: PrismTokens.tintedHighlightAlpha),
                Colors.transparent,
              ],
            ),
          );

    // --- Noise texture (suppressed in accessible mode) ---
    final DecorationImage? noiseImage = isAccessible
        ? null
        : DecorationImage(
            image: const AssetImage('assets/textures/noise_64x64.png'),
            repeat: ImageRepeat.repeat,
            opacity: isDark
                ? PrismTokens.tintedNoiseOpacityDark
                : PrismTokens.tintedNoiseOpacityLight,
          );

    return Container(
      width: width,
      height: height,
      padding: padding,
      foregroundDecoration: highlightDecoration,
      decoration: BoxDecoration(
        color: fillColor,
        shape: shape,
        borderRadius: effectiveBorderRadius,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadow,
        image: noiseImage,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
