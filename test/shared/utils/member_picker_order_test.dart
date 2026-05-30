import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/utils/member_picker_order.dart';

Member _member(String id) =>
    Member(id: id, name: id, createdAt: DateTime(2024));

List<String> _ids(List<Member> members) => [for (final m in members) m.id];

void main() {
  group('partitionMembersForPicker', () {
    test('empty fronterIds → everyone in others, fronters empty', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final sections = partitionMembersForPicker(members, const {});
      expect(sections.fronters, isEmpty);
      expect(_ids(sections.others), ['a', 'b', 'c']);
      expect(sections.hasFronterSection, isFalse);
      // No copy when there are no fronters.
      expect(identical(sections.others, members), isTrue);
    });

    test('mixed → fronters first, each group keeps input order', () {
      final members = [
        _member('a'),
        _member('b'),
        _member('c'),
        _member('d'),
      ];
      final sections = partitionMembersForPicker(members, {'c', 'a'});
      expect(_ids(sections.fronters), ['a', 'c']); // display order, not set order
      expect(_ids(sections.others), ['b', 'd']);
      expect(sections.hasFronterSection, isTrue);
    });

    test('everyone fronting → no section boundary', () {
      final members = [_member('a'), _member('b')];
      final sections = partitionMembersForPicker(members, {'a', 'b'});
      expect(_ids(sections.fronters), ['a', 'b']);
      expect(sections.others, isEmpty);
      expect(sections.hasFronterSection, isFalse);
    });

    test('fronterId not present in members is ignored', () {
      final members = [_member('a'), _member('b')];
      final sections = partitionMembersForPicker(members, {'ghost', 'a'});
      expect(_ids(sections.fronters), ['a']);
      expect(_ids(sections.others), ['b']);
    });

    test('no duplication — a fronter appears once', () {
      final members = [_member('a'), _member('b'), _member('c')];
      final sections = partitionMembersForPicker(members, {'b'});
      final all = [...sections.fronters, ...sections.others];
      expect(_ids(all)..sort(), ['a', 'b', 'c']);
      expect(all.length, 3);
    });
  });

  group('orderMembersForPicker', () {
    test('no fronters → returns input unchanged', () {
      final members = [_member('a'), _member('b')];
      expect(identical(orderMembersForPicker(members, const {}), members),
          isTrue);
    });

    test('fronters float to top, rest follow in order', () {
      final members = [
        _member('a'),
        _member('b'),
        _member('c'),
        _member('d'),
      ];
      expect(_ids(orderMembersForPicker(members, {'d', 'b'})),
          ['b', 'd', 'a', 'c']);
    });
  });
}
