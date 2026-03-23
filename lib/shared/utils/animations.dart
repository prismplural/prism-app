// lib/shared/utils/animations.dart
import 'package:flutter/material.dart';

/// Shared animation durations and curves for consistent motion.
/// Based on Material 3 motion guidelines.
abstract final class Anim {
  // Durations
  static const fast = Duration(milliseconds: 100);
  static const normal = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 350);

  // Curves
  static const standard = Curves.easeInOut;
  static const enter = Curves.easeOut;
  static const exit = Curves.easeIn;
  static const spring = Curves.elasticOut;
}
