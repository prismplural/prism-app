import 'package:flutter/material.dart';

/// The Prism mark on the app icon's background, for in-app branding.
class PrismLogoTile extends StatelessWidget {
  const PrismLogoTile({
    super.key,
    required this.size,
    required this.logoSize,
    this.borderRadius = BorderRadius.zero,
    this.shape = BoxShape.rectangle,
  });

  final double size;
  final double logoSize;
  final BorderRadius borderRadius;
  final BoxShape shape;

  // The fill from assets/AppIcon.icon/icon.json, converted from Display P3.
  static const gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFB999C5), Color(0xFF51345D)],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: gradient,
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : borderRadius,
      ),
      alignment: Alignment.center,
      child: Image.asset(
        'assets/icon_layers/Prism-Logo-Foreground.png',
        width: logoSize,
        height: logoSize,
      ),
    );
  }
}
