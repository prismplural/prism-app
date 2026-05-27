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
    // No notifyListeners(): unregister runs from State.dispose() chains
    // where a listener-side setState() asserts "widget tree was locked".
    // The host re-reads hasPendingChanges on its next rebuild.
    final wasDirty = _dirty.remove(state) ?? false;
    if (wasDirty) _dirtyCount--;
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

  /// Looks up the display name for [fieldId] among currently-registered
  /// editors. Returns `null` if no editor for the field is registered
  /// (e.g. the user dismissed the custom-fields detail view before [commit]
  /// resolved); callers should fall back to a provider lookup.
  String? displayNameFor(String fieldId) {
    for (final state in _dirty.keys) {
      if (state.fieldId == fieldId) return state.fieldDisplayName;
    }
    return null;
  }

  /// Best-effort flush. Iterates every staged field and writes it through the
  /// value notifier. A failure on one field does NOT short-circuit the rest;
  /// instead, the caught exception is collected into the returned map (keyed
  /// by `state.fieldId`). On success the editor clears its own dirty flag via
  /// [markDirty]; on failure dirty remains set so a re-touch + retry re-stages
  /// and re-saves cleanly.
  ///
  /// Callers MUST surface the returned map — silently dropping failures here
  /// would let the member-row save succeed while custom-field writes for
  /// fields 2..N never landed, producing a partial state that's invisible to
  /// the user and divergent from peers.
  Future<Map<String, Object>> commit() async {
    final failures = <String, Object>{};
    for (final state in _dirty.keys.toList()) {
      try {
        await state.commitPendingValue();
      } catch (e) {
        failures[state.fieldId] = e;
      }
    }
    return failures;
  }

  // No-op: staged edits are local state, so dropping the editor is enough.
  // Kept so hosts that wire `onDiscard:` stay compiling.
  void discard() {}
}

/// Implemented by per-field editor State classes so the controller can flush
/// their staged value on [commit].
abstract class PendingFieldEditState {
  /// Stable identifier for the underlying [CustomField]. Used by [
  /// CustomFieldsEditorController.commit] to key the failures map and by the
  /// host to look up a display name for a partial-failure toast.
  String get fieldId;

  /// User-visible name for the underlying field. The host shows this in the
  /// `"Saved, but couldn't save <field>"` toast when a single field failed;
  /// for multiple failures the host falls back to a count. Implementations
  /// should return `widget.field.name`.
  String get fieldDisplayName;

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
