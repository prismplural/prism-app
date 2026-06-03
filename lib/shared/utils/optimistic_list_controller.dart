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
