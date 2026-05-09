import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/data/sync/field_diff.dart';

void main() {
  group('diffSyncFields', () {
    test('empty inputs return empty output', () {
      expect(diffSyncFields({}, {}), isEmpty);
    });

    test('all fields equal returns empty output', () {
      expect(
        diffSyncFields({'a': 1, 'b': 'hello'}, {'a': 1, 'b': 'hello'}),
        isEmpty,
      );
    });

    test('one field differs emits only the changed field', () {
      expect(
        diffSyncFields({'a': 1, 'b': 2}, {'a': 1, 'b': 3}),
        equals({'b': 3}),
      );
    });

    test('is_deleted false in next is never emitted', () {
      expect(
        diffSyncFields({}, {'is_deleted': false, 'name': 'Alice'}),
        equals({'name': 'Alice'}),
      );
    });

    test('is_deleted is stripped even when previous lacks the key', () {
      expect(
        diffSyncFields({'a': 1}, {'a': 1, 'is_deleted': false}),
        isEmpty,
      );
    });

    test('field present in previous but absent from next is not emitted', () {
      expect(
        diffSyncFields({'a': 1, 'b': 2}, {'a': 1}),
        isEmpty,
      );
    });

    test('JSON-encoded list values compared as strings', () {
      expect(
        diffSyncFields({'items': '[1,2,3]'}, {'items': '[4,5,6]'}),
        equals({'items': '[4,5,6]'}),
      );
    });

    test('identical JSON-encoded list values not emitted', () {
      expect(
        diffSyncFields({'items': '[1,2,3]'}, {'items': '[1,2,3]'}),
        isEmpty,
      );
    });
  });
}
