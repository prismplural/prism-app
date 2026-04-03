import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// Glass surface with real backdrop blur.
///
/// Prefer [TintedGlassSurface] for repeated/list-level content (avatars,
/// buttons, date pills, input bars). Use [GlassSurface] only for fixed
/// chrome surfaces that need real blur (nav bar, toasts, popups).
///
/// Automatically falls back to [TintedGlassSurface] when
/// [VisualEffectsMode] is [VisualEffectsMode.reduced] or
/// [VisualEffectsMode.accessible].
class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.shape = BoxShape.rectangle,
    this.borderRadius,
    this.width,
    this.height,
    this.tint,
    this.backgroundColor,
    this.borderColor,
    this.sigma = PrismTokens.glassBlurMedium,
    this.padding,
    this.borderWidth = PrismTokens.hairlineBorderWidth,
  });

  /// Convenience constructor for circular glass surfaces.
  const GlassSurface.circle({
    super.key,
    required this.child,
    required double size,
    this.tint,
    this.backgroundColor,
    this.borderColor,
    this.sigma = PrismTokens.glassBlurMedium,
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
  final Color? tint;
  final Color? backgroundColor;
  final Color? borderColor;
  final double sigma;
  final EdgeInsets? padding;
  final double borderWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = VisualEffectsModeX.of(context, ref);

    // Fall back to the cheap tinted surface when blur is not appropriate.
    if (!mode.useBlur) {
      if (shape == BoxShape.circle) {
        return TintedGlassSurface.circle(
          size: width ?? 40,
          tint: tint,
          padding: padding,
          borderWidth: borderWidth,
          child: child,
        );
      }
      return TintedGlassSurface(
        shape: shape,
        borderRadius: borderRadius,
        width: width,
        height: height,
        tint: tint,
        padding: padding,
        borderWidth: borderWidth,
        child: child,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveBorderRadius = shape == BoxShape.circle
        ? BorderRadius.circular((width ?? 40) / 2)
        : (borderRadius ?? BorderRadius.circular(PrismTokens.radiusMedium));

    final darkBase = AppColors.warmWhite.withValues(alpha: 0.08);
    final fillColor = tint != null
        ? Color.alphaBlend(
            tint!.withValues(alpha: 0.15),
            isDark ? darkBase : AppColors.warmWhite.withValues(alpha: 0.65),
          )
        : isDark
        ? darkBase
        : AppColors.warmWhite.withValues(alpha: 0.65);
    final effectiveFillColor = backgroundColor ?? fillColor;
    final effectiveBorderColor =
        borderColor ??
        (isDark
            ? AppColors.warmWhite.withValues(alpha: 0.1)
            : AppColors.warmBlack.withValues(alpha: 0.06));

    return ClipRRect(
      borderRadius: effectiveBorderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: effectiveFillColor,
            shape: shape,
            borderRadius: shape == BoxShape.circle ? null : borderRadius,
            border: Border.all(color: effectiveBorderColor, width: borderWidth),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
