import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';

void main() {
  group('PKGroup.fromJson', () {
    test('parses canonical fields', () {
      final g = PKGroup.fromJson({
        'id': 'abcde',
        'uuid': '00000000-0000-0000-0000-000000000001',
        'name': 'Core',
        'display_name': 'The Core',
        'description': 'A bunch of folks',
        'color': 'ff00aa',
        'icon': 'https://cdn.pluralkit.me/icon.png',
        'banner': 'https://cdn.pluralkit.me/banner.png',
      });

      expect(g.id, 'abcde');
      expect(g.uuid, '00000000-0000-0000-0000-000000000001');
      expect(g.name, 'Core');
      expect(g.displayName, 'The Core');
      expect(g.description, 'A bunch of folks');
      expect(g.color, 'ff00aa');
      expect(g.iconUrl, 'https://cdn.pluralkit.me/icon.png');
      expect(g.bannerUrl, 'https://cdn.pluralkit.me/banner.png');
      // No `members` key → unknown, NOT empty.
      expect(g.memberIds, isNull);
    });

    test('members absent → memberIds is null (unknown, see R2)', () {
      final g = PKGroup.fromJson({
        'id': 'aaaaa',
        'uuid': 'u1',
        'name': 'N',
      });
      expect(g.memberIds, isNull);
    });

    test('members present but empty → [] (legitimately empty)', () {
      final g = PKGroup.fromJson({
        'id': 'aaaaa',
        'uuid': 'u1',
        'name': 'N',
        'members': <dynamic>[],
      });
      expect(g.memberIds, isNotNull);
      expect(g.memberIds, isEmpty);
    });

    test('members as list of objects → uuid strings', () {
      final g = PKGroup.fromJson({
        'id': 'aaaaa',
        'uuid': 'u1',
        'name': 'N',
        'members': [
          {'uuid': 'mem-1', 'id': 'mm111'},
          {'uuid': 'mem-2', 'id': 'mm222'},
        ],
      });
      expect(g.memberIds, ['mem-1', 'mem-2']);
    });

    test('members as list of strings → passed through', () {
      final g = PKGroup.fromJson({
        'id': 'aaaaa',
        'uuid': 'u1',
        'name': 'N',
        'members': ['mem-1', 'mem-2'],
      });
      expect(g.memberIds, ['mem-1', 'mem-2']);
    });

    test('members: null → unknown (null), not empty', () {
      final g = PKGroup.fromJson({
        'id': 'aaaaa',
        'uuid': 'u1',
        'name': 'N',
        'members': null,
      });
      expect(g.memberIds, isNull);
    });
  });
}
