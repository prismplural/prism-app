import 'package:flutter/widgets.dart';

/// Marks a subtree as embedded inside a persistent detail pane (the trailing
/// side of a [ListDetailLayout]).
///
/// Screens that would normally render a route back button check this and
/// suppress it: there is no route to pop in a pane — the host swaps the pane in
/// place via its selection state. `ListDetailLayout` wraps its detail pane in
/// this marker automatically, so any screen embedded there (e.g. a settings
/// sub-screen) hides its back button without needing a per-screen flag.
///
/// Note: this does NOT apply to the modal side sheet (`showDetailSideSheet`),
/// which is a real route. Modal side sheets use a separate marker so route
/// pops can be styled as close actions instead of hidden.
class EmbeddedPaneMarker extends InheritedWidget {
  const EmbeddedPaneMarker({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EmbeddedPaneMarker>() != null;

  @override
  bool updateShouldNotify(EmbeddedPaneMarker oldWidget) => false;
}
