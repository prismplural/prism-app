import 'package:flutter/painting.dart';

/// Applies Prism's font-size preference after the system's accessibility scaler.
/// Delegating each size preserves nonlinear scaling on supported platforms.
class PrismTextScaler extends TextScaler {
  const PrismTextScaler(this.systemScaler, this.factor)
    : assert(factor > 0 && factor < double.infinity);

  final TextScaler systemScaler;
  final double factor;

  @override
  double scale(double fontSize) => systemScaler.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => systemScaler.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is PrismTextScaler &&
      other.systemScaler == systemScaler &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(systemScaler, factor);
}
