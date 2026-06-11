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
      expect(sw.memberDetails, isEmpty);
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
            'display_name': 'Al',
            'avatar_url': 'https://example.test/al.png',
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
      expect(sw.memberDetails, hasLength(2));
      expect(sw.memberDetails.first.id, 'abcde');
      expect(
        sw.memberDetails.first.uuid,
        '00000000-0000-0000-0000-000000000001',
      );
      expect(sw.memberDetails.first.name, 'Alice');
      expect(sw.memberDetails.first.displayName, 'Al');
      expect(sw.memberDetails.first.avatarUrl, 'https://example.test/al.png');
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
      expect(sw.memberDetails.map((m) => m.id), ['fghij']);
    });
  });

  group('PKMember.fromJson', () {
    test('parses birthday and proxy_tags', () {
      final json = <String, dynamic>{
        'id': 'abcde',
        'uuid': '00000000-0000-0000-0000-000000000001',
        'name': 'Alice',
        'birthday': '2020-01-15',
        'proxy_tags': <dynamic>[
          {'prefix': 'A:', 'suffix': null},
          {'prefix': null, 'suffix': '-a'},
        ],
      };

      final m = PKMember.fromJson(json);

      expect(m.birthday, '2020-01-15');
      expect(m.proxyTagsJson, isNotNull);
      expect(m.proxyTagsJson, contains('"prefix":"A:"'));
      expect(m.proxyTagsJson, contains('"suffix":"-a"'));
    });

    test('handles missing birthday and proxy_tags (null)', () {
      final json = <String, dynamic>{
        'id': 'abcde',
        'uuid': '00000000-0000-0000-0000-000000000001',
        'name': 'Alice',
      };

      final m = PKMember.fromJson(json);

      expect(m.birthday, isNull);
      expect(m.proxyTagsJson, isNull);
    });

    test('encodes empty proxy_tags array as "[]"', () {
      final json = <String, dynamic>{
        'id': 'abcde',
        'uuid': '00000000-0000-0000-0000-000000000001',
        'name': 'Alice',
        'proxy_tags': <dynamic>[],
      };

      final m = PKMember.fromJson(json);

      expect(m.proxyTagsJson, '[]');
    });

    test('preserves year-0004 birthday sentinel', () {
      final json = <String, dynamic>{
        'id': 'abcde',
        'uuid': '00000000-0000-0000-0000-000000000001',
        'name': 'Alice',
        'birthday': '0004-03-21',
      };

      final m = PKMember.fromJson(json);

      expect(m.birthday, '0004-03-21');
    });
  });

  group('PKSystem.fromJson', () {
    // 2026-06 PK audit H8: the system uuid is the stable identity key for the
    // file-import system check (short ids become user-changeable with PK
    // Premium). Both the API response and the pk;export root carry it.
    test('parses uuid alongside the short id', () {
      final json = <String, dynamic>{
        'id': 'abcde',
        'uuid': '11111111-2222-3333-4444-555555555555',
        'name': 'My System',
        'tag': '| sys',
        'avatar_url': 'https://example.test/sys.png',
      };

      final s = PKSystem.fromJson(json);

      expect(s.id, 'abcde');
      expect(s.uuid, '11111111-2222-3333-4444-555555555555');
      expect(s.name, 'My System');
      expect(s.tag, '| sys');
      expect(s.avatarUrl, 'https://example.test/sys.png');
    });

    test('tolerates a missing uuid (legacy/partial payloads)', () {
      final json = <String, dynamic>{'id': 'abcde', 'name': 'My System'};

      final s = PKSystem.fromJson(json);

      expect(s.id, 'abcde');
      expect(
        s.uuid,
        isNull,
        reason:
            'uuid is optional — identity checks fall back to the short id '
            'when either side lacks one',
      );
    });
  });
}
