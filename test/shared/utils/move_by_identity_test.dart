import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/shared/utils/optimistic_list_controller.dart';

List<String>? _move(List<String> dropped, String moved, List<String> latest) =>
    moveByIdentity<String, String>(
      dropped: dropped,
      movedKey: moved,
      latest: latest,
      keyOf: (item) => item,
    );

void main() {
  group('moveByIdentity', () {
    test('returns the dropped order when nothing changed', () {
      expect(_move(['a', 'c', 'b'], 'c', ['a', 'b', 'c']), ['a', 'c', 'b']);
    });

    test('keeps an item added during the drag where it was synced', () {
      expect(_move(['a', 'd', 'b', 'c'], 'd', ['n', 'a', 'b', 'c', 'd']), [
        'n',
        'a',
        'd',
        'b',
        'c',
      ]);
    });

    test('a move to the start or end stays at the start or end', () {
      expect(_move(['c', 'a', 'b'], 'c', ['n', 'a', 'b', 'c']), [
        'c',
        'n',
        'a',
        'b',
      ]);
      expect(_move(['b', 'c', 'a'], 'a', ['a', 'b', 'c', 'n']), [
        'b',
        'c',
        'n',
        'a',
      ]);
    });

    test('anchors after the nearest surviving item above the drop', () {
      // 'a' (directly above the drop) was deleted; 'x' above it survives.
      expect(_move(['x', 'a', 'd', 'b'], 'd', ['x', 'b', 'd']), [
        'x',
        'd',
        'b',
      ]);
    });

    test('falls back to the nearest surviving item below the drop', () {
      // 'a' above the drop was deleted, so the item goes right before 'b'.
      expect(_move(['a', 'd', 'b', 'c'], 'd', ['b', 'c', 'd']), [
        'd',
        'b',
        'c',
      ]);
      expect(_move(['a', 'd', 'b', 'c'], 'd', ['c', 'b', 'd']), [
        'c',
        'd',
        'b',
      ]);
    });

    test('follows other items to their latest positions', () {
      // Sync moved 'a' to the end; the dragged item stays right after it.
      expect(_move(['a', 'd', 'b', 'c'], 'd', ['b', 'c', 'a', 'd']), null);
      expect(_move(['a', 'd', 'b', 'c'], 'd', ['b', 'c', 'd', 'a']), [
        'b',
        'c',
        'a',
        'd',
      ]);
    });

    test('returns null when the moved item is gone', () {
      expect(_move(['b', 'a', 'c'], 'b', ['a', 'c']), null);
    });

    test('returns null when no neighbour from the drop survives', () {
      expect(_move(['a', 'd', 'b'], 'd', ['n', 'd']), null);
    });

    test('returns null when the result equals the latest order', () {
      expect(_move(['a', 'b', 'c'], 'b', ['a', 'b', 'c']), null);
    });

    test('only the moved item changes relative position', () {
      final latest = ['n1', 'a', 'b', 'n2', 'c', 'e'];
      final result = _move(['a', 'b', 'e', 'c'], 'e', latest)!;
      expect(result.where((id) => id != 'e'), [
        for (final id in latest)
          if (id != 'e') id,
      ]);
      expect(result.indexOf('e'), result.indexOf('b') + 1);
    });
  });

  group('orderLike', () {
    List<String> order(List<String> items, List<String> preferred) =>
        orderLike<String, String>(items, preferred, keyOf: (item) => item);

    test('applies the preferred order to the items it knows', () {
      expect(order(['a', 'b', 'c'], ['c', 'a', 'b']), ['c', 'a', 'b']);
    });

    test('items only in the current list keep their slots', () {
      expect(order(['n', 'a', 'b', 'm', 'c'], ['c', 'b', 'a']), [
        'n',
        'c',
        'b',
        'm',
        'a',
      ]);
    });

    test('items gone from the current list are dropped', () {
      expect(order(['a', 'c'], ['c', 'b', 'a']), ['c', 'a']);
    });
  });
}
