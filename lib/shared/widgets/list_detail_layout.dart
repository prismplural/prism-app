import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/widgets/embedded_pane_marker.dart';

/// A responsive two-pane list-detail layout (Material 3 "canonical" pattern).
///
/// On narrow windows the [list] fills the whole content area and selecting an
/// item is the caller's responsibility (typically pushing/going to a detail
/// route). On windows at least [breakpoint] wide, the list collapses to a
/// fixed-width pane on the leading edge and the [detail] for the currently
/// selected item renders inline alongside it. The list pane steps up to a
/// wider tier past [xWideBreakpoint] so the detail pane clearly dominates at
/// the entry breakpoint rather than the two columns looking evenly split.
///
/// The widget is stateless about *which* item is selected — pair it with
/// [ListDetailSelectionState] on the host screen, which owns the selection and
/// the wide/narrow tap routing so every paned screen behaves identically.
///
/// Width is measured with [LayoutBuilder] against the available content width,
/// not the whole window, so it composes correctly inside the desktop shell
/// (which has already subtracted the navigation sidebar).
///
/// The detail pane is automatically isolated with [PrimaryScrollController.none]
/// because embedded detail screens typically build their own scaffold +
/// `NestedScrollView`; without isolation that nests inside the list screen's
/// own `NestedScrollView` and the two scroll controllers recurse into a
/// `StackOverflowError`. Screens never have to remember this.
class ListDetailLayout extends StatelessWidget {
  const ListDetailLayout({
    super.key,
    required this.list,
    required this.detail,
    this.onClearSelection,
    this.listPaneWidth = PrismTokens.listPaneWidth,
    this.listPaneWidthXWide = PrismTokens.listPaneWidthXWide,
    this.breakpoint = PrismTokens.listDetailBreakpoint,
    this.xWideBreakpoint = PrismTokens.listDetailBreakpointXWide,
  });

  /// Builds the list pane. Receives whether the layout is currently in
  /// two-pane (wide) mode so the host can record the tier (typically via
  /// [ListDetailSelectionState.setListDetailWide]) and branch tap handlers.
  final Widget Function(BuildContext context, bool isWide) list;

  /// Builds the detail pane, shown only in wide mode. Return a placeholder
  /// (e.g. an empty state) when nothing is selected.
  final WidgetBuilder detail;

  /// Clears the current detail selection.
  final VoidCallback? onClearSelection;

  /// List pane width in the "wide" tier ([breakpoint] up to [xWideBreakpoint]).
  final double listPaneWidth;

  /// List pane width in the "extra wide" tier (at or past [xWideBreakpoint]).
  final double listPaneWidthXWide;

  /// Content width at which the layout switches from single-column to two-pane.
  final double breakpoint;

  /// Content width at which the list pane steps up to [listPaneWidthXWide].
  final double xWideBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isWide = width >= breakpoint;

        if (!isWide) {
          return list(context, false);
        }

        final paneWidth = width >= xWideBreakpoint
            ? listPaneWidthXWide
            : listPaneWidth;

        final theme = Theme.of(context);
        final dividerColor = theme.colorScheme.outlineVariant.withValues(
          alpha: 0.5,
        );

        final clearSelection = onClearSelection;

        // Opaque surface so the two-pane layout is a solid page even when the
        // detail pane shows a transparent placeholder (empty state). Without
        // this, a ListDetailLayout screen pushed as a route (e.g. opening
        // Members from Settings) shows the previous screen through the gaps.
        Widget content = ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: paneWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: clearSelection,
                  child: list(context, true),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: dividerColor),
              // Isolate the embedded detail from the list pane's NestedScrollView.
              // Selecting a different item is a *replacement*, not navigation, so
              // it cross-fades rather than slides. Relies on the detail builder
              // keying its content per item (e.g. ValueKey(id)). The
              // EmbeddedPaneMarker tells embedded screens to drop their route
              // back button (there's no route to pop in a pane).
              Expanded(
                child: PrimaryScrollController.none(
                  child: ListDetailPaneControls(
                    clearSelection: clearSelection,
                    child: EmbeddedPaneMarker(
                      child: AnimatedSwitcher(
                        duration: MediaQuery.of(context).disableAnimations
                            ? Duration.zero
                            : Anim.sm,
                        child: detail(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (clearSelection == null) return content;

        content = CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): clearSelection,
          },
          child: Focus(autofocus: true, child: content),
        );

        return content;
      },
    );
  }
}

/// Drives a [ListDetailLayout] from the host list screen's [State].
///
/// Centralizes the three things every paned screen needs so they stay
/// consistent: the current tier, the selected item, and the tap routing that
/// branches between "select in-pane" (wide) and "navigate" (narrow). Mix it
/// into a `State`/`ConsumerState` and:
///
/// * call [setListDetailWide] from the `list` builder,
/// * route row taps through [onSelectDetail],
/// * highlight rows with [isDetailSelected],
/// * read [selectedDetailId] when building the detail pane.
mixin ListDetailSelectionState<T extends StatefulWidget> on State<T> {
  /// Id of the item shown in the detail pane, or null for the placeholder.
  String? selectedDetailId;

  /// Whether the layout is currently in two-pane (wide) mode.
  bool isDetailPaneVisible = false;

  /// Record the current tier. Call from the `list` builder; it is a plain
  /// assignment (no setState) because the builder already runs during layout.
  void setListDetailWide(bool isWide) => isDetailPaneVisible = isWide;

  /// Select [id] in-pane when wide; otherwise run [navigate].
  void onSelectDetail(String id, {required VoidCallback navigate}) {
    if (isDetailPaneVisible) {
      setState(() {
        selectedDetailId = selectedDetailId == id ? null : id;
      });
    } else {
      navigate();
    }
  }

  /// Clear the wide-pane detail selection.
  void clearDetailSelection() {
    if (selectedDetailId == null) return;
    setState(() => selectedDetailId = null);
  }

  /// True when [id] is the active selection shown in the detail pane.
  bool isDetailSelected(String id) =>
      isDetailPaneVisible && selectedDetailId == id;
}

/// Controls exposed to embedded detail-pane content.
class ListDetailPaneControls extends InheritedWidget {
  const ListDetailPaneControls({
    super.key,
    required this.clearSelection,
    required super.child,
  });

  final VoidCallback? clearSelection;

  static ListDetailPaneControls? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListDetailPaneControls>();

  @override
  bool updateShouldNotify(ListDetailPaneControls oldWidget) =>
      oldWidget.clearSelection != clearSelection;
}

/// Closes a detail surface without popping the app shell from embedded panes.
bool closeDetailSurface(BuildContext context, {bool routeBacked = true}) {
  if (!context.mounted) return false;

  final clearSelection = ListDetailPaneControls.maybeOf(
    context,
  )?.clearSelection;
  if (clearSelection != null) {
    clearSelection();
    return true;
  }

  final paneScope = ListDetailPaneScope.maybeOf(context);
  if (paneScope?.canPopPane ?? false) {
    paneScope!.popPane();
    return true;
  }

  if (!routeBacked) return false;
  unawaited(Navigator.of(context).maybePop());
  return true;
}

/// Controls exposed to embedded list-pane content.
class ListDetailPaneScope extends InheritedWidget {
  const ListDetailPaneScope({
    super.key,
    required this.selectDetail,
    required this.openInPane,
    required this.popPane,
    required this.canPopPane,
    required this.selectedDetailId,
    required super.child,
  });

  /// Id currently shown in the detail pane, so embedded list-pane screens can
  /// highlight the active row.
  final String? selectedDetailId;

  /// Open [id] in the shared detail pane (trailing side).
  final void Function(String id) selectDetail;

  /// Drill the list pane (leading side) into a sub-view keyed by [id].
  final void Function(String id) openInPane;

  /// Pop the list pane back one level.
  final VoidCallback popPane;

  /// Whether the list pane currently has a level to pop back to.
  final bool canPopPane;

  static ListDetailPaneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListDetailPaneScope>();

  @override
  bool updateShouldNotify(ListDetailPaneScope oldWidget) =>
      oldWidget.canPopPane != canPopPane ||
      oldWidget.selectedDetailId != selectedDetailId;
}

/// Animates drill-down navigation within a list pane as a shared-axis
/// horizontal slide + fade: drilling deeper ([depth] increases) slides the new
/// level in from the trailing edge while the old level exits toward the
/// leading edge; going back reverses it. Same-depth swaps keep the last
/// direction. [child] must carry a [Key] that changes per level so the
/// switcher can tell levels apart. Honors the platform reduced-motion setting.
class PaneNavigationSwitcher extends StatefulWidget {
  const PaneNavigationSwitcher({
    super.key,
    required this.depth,
    required this.child,
    this.duration = Anim.md,
  });

  /// Current drill depth; higher means deeper in the hierarchy.
  final int depth;
  final Widget child;
  final Duration duration;

  @override
  State<PaneNavigationSwitcher> createState() => _PaneNavigationSwitcherState();
}

class _PaneNavigationSwitcherState extends State<PaneNavigationSwitcher> {
  bool _forward = true;

  @override
  void didUpdateWidget(PaneNavigationSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.depth != oldWidget.depth) {
      _forward = widget.depth > oldWidget.depth;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;

    return AnimatedSwitcher(
      duration: widget.duration,
      switchInCurve: Anim.enter,
      switchOutCurve: Anim.exit,
      transitionBuilder: (child, animation) {
        final incoming = child.key == widget.child.key;
        // Short shared-axis motion, reversed when drilling back.
        final dx = _forward
            ? (incoming ? 0.18 : -0.18)
            : (incoming ? -0.18 : 0.18);
        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(dx, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
