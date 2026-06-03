import 'package:flutter/widgets.dart';

/// Marks a subtree as presented inside a modal trailing side sheet.
///
/// Screens that normally render a route back button can check this marker to
/// present that route pop as a close action instead. Unlike
/// `EmbeddedPaneMarker`, a modal side sheet is still a real route; the marker is
/// purely visual/semantic.
class ModalSideSheetMarker extends InheritedWidget {
  const ModalSideSheetMarker({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModalSideSheetMarker>() !=
      null;

  @override
  bool updateShouldNotify(ModalSideSheetMarker oldWidget) => false;
}
