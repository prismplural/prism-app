import 'package:flutter/widgets.dart';

/// Marker installed by containers (groups, compact-row layouts, value cards)
/// that already render a field's name themselves, so child renderers like
/// slider and scale can skip their own internal label and avoid duplication.
class CustomFieldDisplayScope extends InheritedWidget {
  const CustomFieldDisplayScope({
    super.key,
    required this.labelHandled,
    required super.child,
  });

  final bool labelHandled;

  static bool labelHandledFor(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CustomFieldDisplayScope>();
    return scope?.labelHandled ?? false;
  }

  @override
  bool updateShouldNotify(CustomFieldDisplayScope oldWidget) =>
      labelHandled != oldWidget.labelHandled;
}
