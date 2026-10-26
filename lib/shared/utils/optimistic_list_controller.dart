typedef ItemKey<T, K> = K Function(T item);
typedef ProviderItemsMatch<T> =
    bool Function(List<T> providerItems, List<T> optimisticItems);

/// Holds a temporary list order while async persistence catches up.
///
/// Use this for reorderable lists whose source of truth arrives through a
/// provider or stream. Flutter calls reorder callbacks when the user drops an
/// item, so the UI should keep showing the dropped order instead of rendering
/// a stale provider frame while the write is still in flight.
class OptimisticListController<T, K> {
  OptimisticListController({
    required this.keyOf,
    ProviderItemsMatch<T>? providerItemsMatch,
  }) : _providerItemsMatch = providerItemsMatch;

  final ItemKey<T, K> keyOf;
  final ProviderItemsMatch<T>? _providerItemsMatch;

  List<T>? _items;

  List<T>? get items => _items;

  List<T> displayItems(List<T> providerItems) => _items ?? providerItems;

  void set(List<T> items) {
    _items = List<T>.of(items);
  }

  void clear() {
    _items = null;
  }

  bool isCurrent(List<T> items) => identical(_items, items);

  bool hasCurrentOrder(List<T> items) {
    final current = _items;
    return current != null && sameItemOrder(current, items, keyOf: keyOf);
  }

  bool shouldClearFor(List<T> providerItems) {
    final optimisticItems = _items;
    if (optimisticItems == null) return false;

    final providerMatches =
        _providerItemsMatch?.call(providerItems, optimisticItems) ??
        sameItemOrder(providerItems, optimisticItems, keyOf: keyOf);
    if (providerMatches) return true;

    return !sameItemSet(providerItems, optimisticItems, keyOf: keyOf);
  }
}

List<T>? reorderedItems<T>(
  List<T> items,
  int oldIndex,
  int newIndex, {
  bool adjustNewIndexForRemoval = true,
}) {
  if (oldIndex < 0 || oldIndex >= items.length) return null;
  var insertionIndex = newIndex;
  if (adjustNewIndexForRemoval && insertionIndex > oldIndex) {
    insertionIndex -= 1;
  }
  if (oldIndex == insertionIndex) return null;

  final reordered = List<T>.from(items);
  final item = reordered.removeAt(oldIndex);
  insertionIndex = insertionIndex.clamp(0, reordered.length).toInt();
  reordered.insert(insertionIndex, item);
  return reordered;
}

/// Re-applies a drag-and-drop move to the latest items, by identity.
///
/// [dropped] is the order the user produced by dragging the item keyed
/// [movedKey] within the items they could see. Because the source list may
/// have changed during the drag (for example a sync update), the result is
/// built from [latest]: every other item keeps its latest relative order,
/// items the user never saw stay where they are, and the moved item is placed
/// at the start or end if it was dropped there, otherwise right after the
/// nearest item it was dropped below (or before the nearest item it was
/// dropped above) that still exists.
///
/// Returns null when the moved item is no longer in [latest], when no
/// neighbour from the drop still exists to anchor it, or when the result
/// equals [latest] (nothing to write).
List<T>? moveByIdentity<T, K>({
  required List<T> dropped,
  required K movedKey,
  required List<T> latest,
  required ItemKey<T, K> keyOf,
}) {
  final droppedIndex = dropped.indexWhere((item) => keyOf(item) == movedKey);
  final latestIndex = latest.indexWhere((item) => keyOf(item) == movedKey);
  if (droppedIndex == -1 || latestIndex == -1) return null;

  final moved = latest[latestIndex];
  final others = List<T>.from(latest)..removeAt(latestIndex);
  final indexInOthers = <K, int>{
    for (var i = 0; i < others.length; i++) keyOf(others[i]): i,
  };

  int? insertAt;
  if (droppedIndex == 0) {
    insertAt = 0;
  } else if (droppedIndex == dropped.length - 1) {
    insertAt = others.length;
  } else {
    for (var i = droppedIndex - 1; i >= 0 && insertAt == null; i--) {
      final index = indexInOthers[keyOf(dropped[i])];
      if (index != null) insertAt = index + 1;
    }
    for (
      var i = droppedIndex + 1;
      i < dropped.length && insertAt == null;
      i++
    ) {
      insertAt = indexInOthers[keyOf(dropped[i])];
    }
  }
  if (insertAt == null) return null;

  final result = others..insert(insertAt, moved);
  if (sameItemOrder(result, latest, keyOf: keyOf)) return null;
  return result;
}

/// Returns [items] with the ones that also appear in [preferred] rearranged
/// into [preferred]'s relative order, each taking one of the slots those
/// items already occupied; every other item keeps its slot.
///
/// Use it to apply a pending optimistic order to fresh provider items: the
/// provider decides which items exist (and their other fields), the
/// optimistic list only decides the order of the items it knows.
List<T> orderLike<T, K>(
  List<T> items,
  List<T> preferred, {
  required ItemKey<T, K> keyOf,
}) {
  final byKey = <K, T>{for (final item in items) keyOf(item): item};
  final reordered = <T>[for (final item in preferred) ?byKey[keyOf(item)]];
  final reorderedKeys = {for (final item in reordered) keyOf(item)};
  var next = 0;
  return [
    for (final item in items)
      if (reorderedKeys.contains(keyOf(item))) reordered[next++] else item,
  ];
}

bool sameItemOrder<T, K>(
  List<T> left,
  List<T> right, {
  required ItemKey<T, K> keyOf,
}) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (keyOf(left[i]) != keyOf(right[i])) return false;
  }
  return true;
}

bool sameItemSet<T, K>(
  List<T> left,
  List<T> right, {
  required ItemKey<T, K> keyOf,
}) {
  if (left.length != right.length) return false;
  final keys = <K>{};
  for (final item in left) {
    if (!keys.add(keyOf(item))) return false;
  }
  for (final item in right) {
    if (!keys.remove(keyOf(item))) return false;
  }
  return keys.isEmpty;
}
