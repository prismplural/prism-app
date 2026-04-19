import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/proxy_tag_matcher.dart';

Member _member({
  required String id,
  String? name,
  String? proxyTagsJson,
  int displayOrder = 0,
  bool isActive = true,
  bool isDeleted = false,
}) =>
    Member(
      id: id,
      name: name ?? id,
      displayOrder: displayOrder,
      isActive: isActive,
      isDeleted: isDeleted,
      proxyTagsJson: proxyTagsJson,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('matchProxyTag', () {
    test('prefix-only match strips prefix', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"}]',
      );
      final match = matchProxyTag('A: hi there', [alex]);
      expect(match, isNotNull);
      expect(match!.memberId, 'alex');
      expect(match.strippedText, 'hi there');
      expect(match.matchedPrefix, 'A:');
      expect(match.matchedSuffix, '');
    });

    test('suffix-only match strips suffix and handles trailing whitespace', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"suffix":"-a"}]',
      );
      final match = matchProxyTag('text -a ', [alex]);
      expect(match, isNotNull);
      expect(match!.strippedText, 'text');
      expect(match.matchedPrefix, '');
      expect(match.matchedSuffix, '-a');
    });

    test('prefix+suffix match strips both', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"[","suffix":"]"}]',
      );
      final match = matchProxyTag('[hello]', [alex]);
      expect(match, isNotNull);
      expect(match!.strippedText, 'hello');
      expect(match.matchedPrefix, '[');
      expect(match.matchedSuffix, ']');
    });

    test('case mismatch returns null', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"}]',
      );
      expect(matchProxyTag('a: hi', [alex]), isNull);
    });

    test('longer prefix wins tie-break by score', () {
      final aa = _member(
        id: 'aa',
        proxyTagsJson: '[{"prefix":"AA:"}]',
        displayOrder: 5,
      );
      final a = _member(
        id: 'a',
        proxyTagsJson: '[{"prefix":"A:"}]',
        displayOrder: 1,
      );
      final match = matchProxyTag('AA: hi', [a, aa]);
      expect(match, isNotNull);
      expect(match!.memberId, 'aa');
      expect(match.strippedText, 'hi');
    });

    test('equal-length tie broken by displayOrder ascending', () {
      final a = _member(
        id: 'a',
        proxyTagsJson: '[{"prefix":"A:"}]',
        displayOrder: 2,
      );
      final b = _member(
        id: 'b',
        proxyTagsJson: '[{"prefix":"A:"}]',
        displayOrder: 1,
      );
      final match = matchProxyTag('A: hi', [a, b]);
      expect(match, isNotNull);
      expect(match!.memberId, 'b');
    });

    test('equal displayOrder tie broken by id lexicographic', () {
      final a = _member(
        id: 'zzz',
        proxyTagsJson: '[{"prefix":"A:"}]',
      );
      final b = _member(
        id: 'aaa',
        proxyTagsJson: '[{"prefix":"A:"}]',
      );
      final match = matchProxyTag('A: hi', [a, b]);
      expect(match, isNotNull);
      expect(match!.memberId, 'aaa');
    });

    test('stripped-empty still matches (banner preview)', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"}]',
      );
      // The matcher fires as soon as the tag is typed so the "Posting as"
      // banner can appear without waiting for content. Send-path guards
      // block the actual empty send.
      expect(matchProxyTag('A:', [alex])?.strippedText, '');
      expect(matchProxyTag('A:   ', [alex])?.strippedText, '');
    });

    test('overlapping prefix+suffix rejected by length guard', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"AAA","suffix":"BBB"}]',
      );
      expect(matchProxyTag('AAAB', [alex]), isNull);
    });

    test('inactive member skipped', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"}]',
        isActive: false,
      );
      expect(matchProxyTag('A: hi', [alex]), isNull);
    });

    test('deleted member skipped', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"}]',
        isDeleted: true,
      );
      expect(matchProxyTag('A: hi', [alex]), isNull);
    });

    test('null proxy_tags_json member skipped', () {
      final alex = _member(id: 'alex', proxyTagsJson: null);
      final bob = _member(
        id: 'bob',
        proxyTagsJson: '[{"prefix":"B:"}]',
      );
      final match = matchProxyTag('B: yo', [alex, bob]);
      expect(match, isNotNull);
      expect(match!.memberId, 'bob');
    });

    test('PK empty-string prefix does not match any draft', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":""}]',
      );
      expect(matchProxyTag('anything', [alex]), isNull);
      expect(matchProxyTag('', [alex]), isNull);
    });

    test('empty draft returns null', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"}]',
      );
      expect(matchProxyTag('', [alex]), isNull);
    });

    test('tag-index tie-break: lower index of same member wins', () {
      final alex = _member(
        id: 'alex',
        proxyTagsJson: '[{"prefix":"A:"},{"prefix":"A:"}]',
      );
      final match = matchProxyTag('A: hi', [alex]);
      expect(match, isNotNull);
      expect(match!.memberId, 'alex');
    });
  });
}
