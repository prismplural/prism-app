// lib/shared/utils/haptics.dart
import 'package:flutter/services.dart';

/// Centralized haptic feedback for consistent tactile feel.
/// Wraps HapticFeedback with semantic names matching interaction types.
abstract final class Haptics {
  /// Light tap — button press, selection change, toggle
  static void light() => HapticFeedback.lightImpact();

  /// Medium tap — completing an action, drag-and-drop
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy tap — destructive action confirmation
  static void heavy() => HapticFeedback.heavyImpact();

  /// Success — fronter switched, vote cast, message sent
  static void success() => HapticFeedback.mediumImpact();

  /// Selection tick — scrolling through picker, reorder
  static void selection() => HapticFeedback.selectionClick();
}
