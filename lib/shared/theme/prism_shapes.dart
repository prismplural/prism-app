import 'package:flutter/material.dart';

enum CornerStyle { rounded, angular }

@immutable
class PrismShapes extends ThemeExtension<PrismShapes> {
  final CornerStyle cornerStyle;
  const PrismShapes({required this.cornerStyle});

  static const PrismShapes rounded = PrismShapes(cornerStyle: CornerStyle.rounded);
  static const PrismShapes angular = PrismShapes(cornerStyle: CornerStyle.angular);

  /// Access from a BuildContext. Falls back to `rounded` if extension is missing.
  static PrismShapes of(BuildContext context) =>
      Theme.of(context).extension<PrismShapes>() ?? PrismShapes.rounded;

  /// Context-free default for const/static contexts. Always rounded.
  static const PrismShapes defaults = PrismShapes.rounded;

  /// Returns [value] when rounded, 0 when angular. Use for body radii.
  double radius(double value) => cornerStyle == CornerStyle.angular ? 0 : value;

  /// Returns [height] / 2 when rounded (pill), 0 when angular.
  double pill(double height) => cornerStyle == CornerStyle.angular ? 0 : height / 2;

  /// Shape for avatar-like surfaces.
  BoxShape avatarShape() =>
      cornerStyle == CornerStyle.angular ? BoxShape.rectangle : BoxShape.circle;

  /// BorderRadius for avatars in angular mode (null in rounded — circle doesn't use it).
  BorderRadius? avatarBorderRadius() =>
      cornerStyle == CornerStyle.angular ? BorderRadius.zero : null;

  /// CircleBorder in rounded, zero-radius RoundedRectangleBorder in angular.
  /// For FAB, circle icon buttons.
  ShapeBorder circleOrSquareBorder() => cornerStyle == CornerStyle.angular
      ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
      : const CircleBorder();

  @override
  PrismShapes copyWith({CornerStyle? cornerStyle}) =>
      PrismShapes(cornerStyle: cornerStyle ?? this.cornerStyle);

  /// No meaningful interpolation — shape is discrete. Snap at t >= 0.5.
  /// rounded↔angular is a deliberate aesthetic switch, not a continuous value.
  @override
  PrismShapes lerp(ThemeExtension<PrismShapes>? other, double t) {
    if (other is! PrismShapes) return this;
    return t < 0.5 ? this : other;
  }
}
