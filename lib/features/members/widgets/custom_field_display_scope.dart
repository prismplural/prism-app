import 'package:flutter/widgets.dart';

/// Inherited marker that signals a custom-field display is being rendered
/// inside a group container.
///
/// The group renders its own header above each child (icon + bold field
/// name) so the children stay visually consistent regardless of type.
/// Renderers that normally bake in their own small "field.name" label
/// (e.g. scale, slider) read this scope and skip their internal label to
/// avoid double-labelling.
///
/// Compact and top-level card paths do NOT install this scope, so renderers
/// continue to provide their own labels outside groups.
class CustomFieldDisplayScope extends InheritedWidget {
  const CustomFieldDisplayScope({
    super.key,
    required this.isInGroup,
    required super.child,
  });

  /// True when this subtree is being rendered inside a group container.
  final bool isInGroup;

  /// Convenience accessor — returns false when no scope is installed.
  static bool isInGroupOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CustomFieldDisplayScope>();
    return scope?.isInGroup ?? false;
  }

  @override
  bool updateShouldNotify(CustomFieldDisplayScope oldWidget) =>
      isInGroup != oldWidget.isInGroup;
}
