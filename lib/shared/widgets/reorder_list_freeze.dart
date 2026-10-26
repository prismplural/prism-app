import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Receives the pointer-down that may start a reorder drag in a list.
abstract interface class ReorderPressListener {
  void onReorderPress(PointerDownEvent event);
}

/// Lets a reorder handle tell its list's [ReorderListFreeze] that a press
/// started, without threading a callback through every row widget.
class ReorderPressScope extends InheritedWidget {
  const ReorderPressScope({
    super.key,
    required this.listener,
    required super.child,
  });

  final ReorderPressListener listener;

  /// Looks up the nearest listener without registering a dependency; handles
  /// only need it at press time.
  static ReorderPressListener? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReorderPressScope>()?.listener;

  @override
  bool updateShouldNotify(ReorderPressScope oldWidget) =>
      listener != oldWidget.listener;
}

/// Keeps the items shown by a reorderable list steady while a reorder gesture
/// is in progress.
///
/// Flutter's reorderable lists address the dragged row by its index at drag
/// start, and the Material list moves the dragged row's globally keyed subtree
/// into an overlay copy for the duration of the drag. If the list's items
/// change underneath an active drag (for example a sync update from another
/// device), the drop indices no longer refer to the same items, and a change
/// in item count makes Flutter cancel the drag mid-build while the overlay copy
/// still holds the row's key, which trips a duplicate-GlobalKey assertion.
///
/// The hold starts when a handle is pressed (see [ReorderPressScope]) and ends
/// once every pressed pointer has lifted or been cancelled and the drag's
/// overlay copy is gone (see [wrapProxy]). The owner is then asked to rebuild
/// with the latest items one frame later, after Flutter has removed the copy.
/// Items that changed during the hold are not lost; they are simply shown
/// after it. Drop handlers must still map the drop onto the latest items by
/// identity, because the list the user dragged in may be out of date.
class ReorderListFreeze<T> implements ReorderPressListener {
  ReorderListFreeze({required VoidCallback onRelease}) : _onRelease = onRelease;

  final VoidCallback _onRelease;
  final Set<int> _pointers = <int>{};
  List<T>? _held;
  List<T>? _lastShown;
  int _liveProxies = 0;
  bool _releaseScheduled = false;
  bool _disposed = false;

  /// Whether the shown items are currently held.
  bool get isHolding => _held != null;

  /// Returns the items to show for this build: the held items during a
  /// reorder gesture, otherwise [latest]. Call once per build.
  List<T> shown(List<T> latest) {
    final items = _held ?? latest;
    _lastShown = items;
    return items;
  }

  @override
  void onReorderPress(PointerDownEvent event) {
    if (_disposed) return;
    _held ??= _lastShown;
    if (_pointers.add(event.pointer)) {
      // The pointer router reports the lift even if the pressed row scrolls
      // away or is rebuilt in the drag overlay.
      GestureBinding.instance.pointerRouter.addRoute(
        event.pointer,
        _handlePointerEvent,
      );
    }
  }

  /// Wraps the drag proxy built by a reorderable list's `proxyDecorator`, so
  /// the hold lasts until Flutter has removed the overlay copy, including the
  /// drop animation and cancelled drags.
  Widget wrapProxy(Widget proxy) =>
      _ReorderProxyLifetime(freeze: this, child: proxy);

  void dispose() {
    _disposed = true;
    for (final pointer in _pointers.toList()) {
      _stopTracking(pointer);
    }
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerRemovedEvent) {
      _stopTracking(event.pointer);
      _scheduleRelease();
    }
  }

  void _stopTracking(int pointer) {
    if (_pointers.remove(pointer)) {
      GestureBinding.instance.pointerRouter.removeRoute(
        pointer,
        _handlePointerEvent,
      );
    }
  }

  void _proxyMounted() {
    _liveProxies++;
    _held ??= _lastShown;
  }

  void _proxyUnmounted() {
    _liveProxies--;
    _scheduleRelease();
  }

  void _scheduleRelease() {
    if (_disposed || _releaseScheduled) return;
    _releaseScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _releaseScheduled = false;
      if (_disposed || _held == null) return;
      if (_pointers.isNotEmpty || _liveProxies > 0) return;
      _held = null;
      _onRelease();
    }, debugLabel: 'ReorderListFreeze.release');
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

class _ReorderProxyLifetime extends StatefulWidget {
  const _ReorderProxyLifetime({required this.freeze, required this.child});

  final ReorderListFreeze<Object?> freeze;
  final Widget child;

  @override
  State<_ReorderProxyLifetime> createState() => _ReorderProxyLifetimeState();
}

class _ReorderProxyLifetimeState extends State<_ReorderProxyLifetime> {
  late final ReorderListFreeze<Object?> _freeze;

  @override
  void initState() {
    super.initState();
    _freeze = widget.freeze;
    _freeze._proxyMounted();
  }

  @override
  void dispose() {
    _freeze._proxyUnmounted();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
