import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';

/// Standard action slot content for Prism top bars.
class PrismTopBarAction extends StatelessWidget {
  const PrismTopBarAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.tooltip,
    this.tint,
    this.size = PrismTokens.topBarActionSize,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final Color? tint;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: PrismGlassIconButton(
        icon: icon,
        onPressed: onPressed,
        onLongPress: onLongPress,
        tooltip: tooltip,
        size: size,
        iconSize: iconSize,
        tint: tint,
      ),
    );
  }
}
