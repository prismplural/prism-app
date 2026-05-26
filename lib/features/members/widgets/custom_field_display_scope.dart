import 'package:flutter/widgets.dart';

/// Marker installed by group containers so child renderers (scale, slider)
/// can skip their own labels and let the group provide one.
class CustomFieldDisplayScope extends InheritedWidget {
  const CustomFieldDisplayScope({
    super.key,
    required this.isInGroup,
    required super.child,
  });

  final bool isInGroup;

  static bool isInGroupOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CustomFieldDisplayScope>();
    return scope?.isInGroup ?? false;
  }

  @override
  bool updateShouldNotify(CustomFieldDisplayScope oldWidget) =>
      isInGroup != oldWidget.isInGroup;
}
