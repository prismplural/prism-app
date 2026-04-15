import 'package:flutter/material.dart';

/// Decorative backdrop for the floating bottom nav bar.
///
/// It intentionally absorbs pointer events so touches in the visual footer
/// strip do not hit interactive content underneath the nav bar gaps.
class FloatingNavBarBackdrop extends StatelessWidget {
  const FloatingNavBarBackdrop({
    super.key,
    required this.height,
    required this.color,
  });

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ExcludeSemantics(
        child: AbsorbPointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0),
                  color.withValues(alpha: 0.8),
                  color,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
