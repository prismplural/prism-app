import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/utils/proxy_tag.dart';

void main() {
  group('parseProxyTags', () {
    test('returns empty list for null', () {
      expect(parseProxyTags(null), isEmpty);
    });

    test('returns empty list for empty string', () {
      expect(parseProxyTags(''), isEmpty);
    });

    test('returns empty list for malformed JSON', () {
      expect(parseProxyTags('not-json'), isEmpty);
    });

    test('returns empty list for non-list JSON', () {
      expect(parseProxyTags('{"prefix":"A:"}'), isEmpty);
    });

    test('parses prefix-only tag', () {
      final tags = parseProxyTags('[{"prefix":"A:","suffix":null}]');
      expect(tags, hasLength(1));
      expect(tags.first.prefix, 'A:');
      expect(tags.first.suffix, isNull);
    });

    test('parses suffix-only tag', () {
      final tags = parseProxyTags('[{"prefix":null,"suffix":"-a"}]');
      expect(tags, hasLength(1));
      expect(tags.first.prefix, isNull);
      expect(tags.first.suffix, '-a');
    });

    test('parses both-sided tag', () {
      final tags = parseProxyTags('[{"prefix":"[","suffix":"]"}]');
      expect(tags, hasLength(1));
      expect(tags.first.prefix, '[');
      expect(tags.first.suffix, ']');
    });

    test('skips entry with empty-string prefix and null suffix', () {
      final tags = parseProxyTags('[{"prefix":"","suffix":null}]');
      expect(tags, isEmpty);
    });

    test('skips entry with both empty-string sides', () {
      final tags = parseProxyTags('[{"prefix":"","suffix":""}]');
      expect(tags, isEmpty);
    });

    test('skips entry with both null sides', () {
      final tags = parseProxyTags('[{"prefix":null,"suffix":null}]');
      expect(tags, isEmpty);
    });

    test('skips non-object entries but keeps valid ones', () {
      final tags = parseProxyTags(
          '["not-an-object",{"prefix":"A:","suffix":null},42]');
      expect(tags, hasLength(1));
      expect(tags.first.prefix, 'A:');
    });

    test('mixed valid + invalid entries preserved in order', () {
      final tags = parseProxyTags(
          '[{"prefix":"A:"},{"prefix":""},{"suffix":"-b"}]');
      expect(tags, hasLength(2));
      expect(tags[0].prefix, 'A:');
      expect(tags[1].suffix, '-b');
    });
  });

  group('ProxyTag.isEmpty', () {
    test('both null is empty', () {
      expect(const ProxyTag().isEmpty, isTrue);
    });

    test('both empty strings is empty', () {
      expect(const ProxyTag(prefix: '', suffix: '').isEmpty, isTrue);
    });

    test('non-empty prefix is not empty', () {
      expect(const ProxyTag(prefix: 'A:').isEmpty, isFalse);
    });

    test('non-empty suffix is not empty', () {
      expect(const ProxyTag(suffix: '-a').isEmpty, isFalse);
    });
  });
}
