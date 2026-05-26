import 'package:flutter/widgets.dart';

/// Coordinates staged edits across the per-field editors inside a member
/// edit sheet. Widgets keep their edits in local state and call [markDirty];
/// the host listens to this notifier so its own dirty/guard logic sees
/// custom-field state. [commit] flushes everything to the value notifier in
/// one sweep; without a commit, staged edits are dropped on dispose.
class CustomFieldsEditorController extends ChangeNotifier {
  // Notify only on aggregate transitions (clean ↔ any-dirty) so per-keystroke
  // marks don't rebuild the host sheet.
  final Map<PendingFieldEditState, bool> _dirty = {};
  int _dirtyCount = 0;

  bool get hasPendingChanges => _dirtyCount > 0;

  void register(PendingFieldEditState state) {
    _dirty.putIfAbsent(state, () => false);
  }

  void unregister(PendingFieldEditState state) {
    final wasDirty = _dirty.remove(state) ?? false;
    if (wasDirty) {
      _dirtyCount--;
      if (_dirtyCount == 0) notifyListeners();
    }
  }

  void markDirty(PendingFieldEditState state, bool dirty) {
    final prev = _dirty[state];
    if (prev == null || prev == dirty) return;
    _dirty[state] = dirty;
    if (dirty) {
      _dirtyCount++;
      if (_dirtyCount == 1) notifyListeners();
    } else {
      _dirtyCount--;
      if (_dirtyCount == 0) notifyListeners();
    }
  }

  Future<void> commit() async {
    for (final state in _dirty.keys.toList()) {
      await state.commitPendingValue();
    }
  }

  // No-op: staged edits are local state, so dropping the editor is enough.
  // Kept so hosts that wire `onDiscard:` stay compiling.
  void discard() {}
}

/// Implemented by per-field editor State classes so the controller can flush
/// their staged value on [commit].
abstract class PendingFieldEditState {
  Future<void> commitPendingValue();
}

class CustomFieldEditorScope extends InheritedWidget {
  const CustomFieldEditorScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final CustomFieldsEditorController controller;

  static CustomFieldsEditorController? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CustomFieldEditorScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(CustomFieldEditorScope old) =>
      controller != old.controller;
}
