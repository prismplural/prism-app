import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';
import 'package:prism_plurality/shared/widgets/tinted_glass_surface.dart';

/// A glass numpad key with two-phase spring press feedback.
///
/// Uses [TintedGlassSurface.circle] for the frosted background. On press:
/// scales to [_scaleTarget] via easeIn (80ms) and brightens the fill with a
/// warm-white tint. On release: springs back via elasticOut (250ms) with a
/// natural overshoot.
///
/// Accessibility: [Semantics] wraps the button with [label] and button=true.
/// For icon-only buttons (backspace, biometric) provide [semanticLabel].
///
/// Reduced motion: when [VisualEffectsMode.accessible], skips scale and uses
/// [AnimatedOpacity] feedback instead.
class PinNumpadButton extends ConsumerStatefulWidget {
  const PinNumpadButton({
    super.key,
    this.label,
    this.icon,
    required this.onTap,
    this.size = 72,
    this.semanticLabel,
  }) : assert(label != null || icon != null, 'Provide label or icon');

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final double size;

  /// Semantic label for icon-only buttons (backspace → l10n.delete,
  /// biometric → l10n.pinLockBiometricTitle).
  final String? semanticLabel;

  @override
  ConsumerState<PinNumpadButton> createState() => _PinNumpadButtonState();
}

class _PinNumpadButtonState extends ConsumerState<PinNumpadButton> {
  bool _pressed = false;

  double get _scaleTarget => widget.size >= 70 ? 0.97 : 0.96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = VisualEffectsModeX.of(context, ref);
    final useAnim = mode.useAnimations;

    final Widget surface = TintedGlassSurface.circle(
      size: widget.size,
      tint: _pressed ? Colors.white.withValues(alpha: 0.08) : null,
      child: widget.label != null
          ? Text(
              widget.label!,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            )
          : Icon(
              widget.icon,
              size: widget.size * 0.33,
              color: theme.colorScheme.onSurface,
            ),
    );

    Widget animated;
    if (useAnim) {
      // Two-phase spring: easeIn on press, elasticOut on release.
      animated = TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _pressed ? _scaleTarget : 1.0),
        duration: _pressed
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 250),
        curve: _pressed ? Curves.easeIn : Curves.elasticOut,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: surface,
      );
    } else {
      animated = AnimatedOpacity(
        opacity: _pressed ? 0.7 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: surface,
      );
    }

    return Semantics(
      label: widget.semanticLabel ?? widget.label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: animated,
        ),
      ),
    );
  }
}
