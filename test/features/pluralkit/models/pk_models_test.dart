import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';

void main() {
  group('PKSwitch.fromJson', () {
    test('parses the GET /switches shape with string IDs', () {
      final json = <String, dynamic>{
        'id': 'switch-1',
        'timestamp': '2026-04-17T00:00:00Z',
        'members': <dynamic>['abcde', 'fghij'],
      };

      final sw = PKSwitch.fromJson(json);

      expect(sw.id, 'switch-1');
      expect(sw.members, ['abcde', 'fghij']);
      expect(sw.timestamp.toUtc().year, 2026);
    });

    test('parses the POST /switches / fronters shape with member objects', () {
      final json = <String, dynamic>{
        'id': 'switch-2',
        'timestamp': '2026-04-17T01:02:03Z',
        'members': <dynamic>[
          <String, dynamic>{
            'id': 'abcde',
            'uuid': '00000000-0000-0000-0000-000000000001',
            'name': 'Alice',
          },
          <String, dynamic>{
            'id': 'fghij',
            'uuid': '00000000-0000-0000-0000-000000000002',
            'name': 'Bob',
          },
        ],
      };

      final sw = PKSwitch.fromJson(json);

      expect(sw.id, 'switch-2');
      expect(sw.members, ['abcde', 'fghij']);
    });

    test('handles an empty members array (switch-out)', () {
      final json = <String, dynamic>{
        'id': 'switch-3',
        'timestamp': '2026-04-17T00:00:00Z',
        'members': <dynamic>[],
      };

      final sw = PKSwitch.fromJson(json);

      expect(sw.members, isEmpty);
    });

    test('tolerates mixed string and object entries', () {
      final json = <String, dynamic>{
        'id': 'switch-4',
        'timestamp': '2026-04-17T00:00:00Z',
        'members': <dynamic>[
          'abcde',
          <String, dynamic>{'id': 'fghij', 'name': 'Bob'},
        ],
      };

      final sw = PKSwitch.fromJson(json);

      expect(sw.members, ['abcde', 'fghij']);
    });
  });
}
