// lib/shared/utils/animations.dart
import 'package:flutter/material.dart';

/// Shared animation durations and curves for consistent motion.
/// Based on Material 3 motion guidelines.
abstract final class Anim {
  // Durations (t-shirt sizing: xs → lg)
  static const xs = Duration(milliseconds: 100);
  static const sm = Duration(milliseconds: 150);
  static const md = Duration(milliseconds: 200);
  static const lg = Duration(milliseconds: 350);

  // Curves
  static const standard = Curves.easeInOut;
  static const enter = Curves.easeOut;
  static const exit = Curves.easeIn;
  static const spring = Curves.elasticOut;
}
