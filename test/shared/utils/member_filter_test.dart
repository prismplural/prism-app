import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/shared/utils/member_filter.dart';

Member _member({
  required String id,
  required String name,
  String? pronouns,
  String? displayName,
}) => Member(
  id: id,
  name: name,
  pronouns: pronouns,
  displayName: displayName,
  createdAt: DateTime(2024),
);

void main() {
  group('filterMembers', () {
    test('empty query returns all members', () {
      final members = [
        _member(id: '1', name: 'Alice'),
        _member(id: '2', name: 'Bob'),
      ];
      expect(filterMembers(members, ''), equals(members));
    });

    test('case-insensitive name match', () {
      final members = [
        _member(id: '1', name: 'Alice'),
        _member(id: '2', name: 'Bob'),
      ];
      final result = filterMembers(members, 'ALICE');
      expect(result, hasLength(1));
      expect(result.first.id, equals('1'));
    });

    test('pronoun match', () {
      final members = [
        _member(id: '1', name: 'Alice', pronouns: 'she/her'),
        _member(id: '2', name: 'Bob'),
      ];
      final result = filterMembers(members, 'she');
      expect(result, hasLength(1));
      expect(result.first.id, equals('1'));
    });

    test('full name match', () {
      final members = [
        _member(id: '1', name: 'Reverie', displayName: 'Reverie Loaf'),
        _member(id: '2', name: 'Bob'),
      ];
      final result = filterMembers(members, 'loaf');
      expect(result, hasLength(1));
      expect(result.first.id, equals('1'));
    });

    test('no match returns empty list', () {
      final members = [
        _member(id: '1', name: 'Alice'),
        _member(id: '2', name: 'Bob'),
      ];
      expect(filterMembers(members, 'xyz'), isEmpty);
    });

    test('NFKC + lowercase normalizes decorative Unicode variants', () {
      // Ａｌｉｃｅ are fullwidth Latin letters that NFKC maps to ASCII equivalents
      final members = [_member(id: '1', name: 'Ａｌｉｃｅ')];
      expect(filterMembers(members, 'alice'), hasLength(1));
    });

    test('MemberSearchIndex preserves order and filters cached keys', () {
      final members = [
        _member(id: '1', name: 'Alice', pronouns: 'she/her'),
        _member(id: '2', name: 'Bob', pronouns: 'they/them'),
        _member(id: '3', name: 'Carol'),
      ];
      final index = MemberSearchIndex(members);

      expect(index.filter('').map((member) => member.id), ['1', '2', '3']);
      expect(index.filter('THEY').map((member) => member.id), ['2']);
    });

    test(
      'MemberSearchIndex matches additional terms without duplicate rows',
      () {
        final members = [
          _member(id: '3', name: 'Carol'),
          _member(id: '1', name: 'Alice'),
          _member(id: '2', name: 'Bob'),
        ];
        final index = MemberSearchIndex(
          members,
          additionalSearchTermsByMemberId: const {
            '1': ['Front Team'],
            '2': ['Front Team', 'Planning'],
            '3': ['Planning'],
          },
        );

        expect(index.filter('front').map((member) => member.id), ['1', '2']);
        expect(index.filter('planning').map((member) => member.id), ['3', '2']);
      },
    );
  });
}
