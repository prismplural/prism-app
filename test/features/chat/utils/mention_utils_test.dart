import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/data/mappers/system_settings_mapper.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

void main() {
  const id1 = '00000000-0000-0000-0000-000000000001';
  const id2 = 'abcdef12-3456-7890-abcd-ef1234567890';

  group('extractMentionIds', () {
    test('extracts single mention', () {
      expect(extractMentionIds('Hello @[$id1]!'), [id1]);
    });

    test('extracts multiple mentions', () {
      expect(
        extractMentionIds('@[$id1] and @[$id2]'),
        [id1, id2],
      );
    });

    test('returns empty for no mentions', () {
      expect(extractMentionIds('Hello world!'), isEmpty);
    });

    test('ignores malformed tokens', () {
      expect(extractMentionIds('@[not-a-uuid]'), isEmpty);
      expect(extractMentionIds('@[1234]'), isEmpty);
      expect(extractMentionIds('@[]'), isEmpty);
    });
  });

  group('containsMention', () {
    test('returns true when member is mentioned', () {
      expect(containsMention('Hey @[$id1] check this', id1), isTrue);
    });

    test('returns false when member is not mentioned', () {
      expect(containsMention('Hey @[$id1] check this', id2), isFalse);
    });

    test('returns false for empty content', () {
      expect(containsMention('', id1), isFalse);
    });
  });

  group('replaceMentionsWithNames', () {
    test('replaces mention with name', () {
      final nameMap = {id1: 'Alice'};
      expect(
        replaceMentionsWithNames('Hi @[$id1]!', nameMap),
        'Hi @Alice!',
      );
    });

    test('replaces multiple mentions', () {
      final nameMap = {id1: 'Alice', id2: 'Bob'};
      expect(
        replaceMentionsWithNames('@[$id1] and @[$id2]', nameMap),
        '@Alice and @Bob',
      );
    });

    test('uses Unknown for missing names', () {
      expect(
        replaceMentionsWithNames('Hi @[$id1]!', {}),
        'Hi @Unknown!',
      );
    });

    test('returns unchanged content with no mentions', () {
      expect(
        replaceMentionsWithNames('Hello world!', {}),
        'Hello world!',
      );
    });
  });

  group('detectMentionTrigger', () {
    test('detects @ at start of text', () {
      final trigger = detectMentionTrigger('@ali', 4);
      expect(trigger, isNotNull);
      expect(trigger!.atIndex, 0);
      expect(trigger.filter, 'ali');
    });

    test('detects @ after space', () {
      final trigger = detectMentionTrigger('hello @bo', 9);
      expect(trigger, isNotNull);
      expect(trigger!.atIndex, 6);
      expect(trigger.filter, 'bo');
    });

    test('detects @ after newline', () {
      final trigger = detectMentionTrigger('hello\n@', 7);
      expect(trigger, isNotNull);
      expect(trigger!.atIndex, 6);
      expect(trigger.filter, '');
    });

    test('returns null for @ mid-word (email-like)', () {
      expect(detectMentionTrigger('email@foo', 9), isNull);
    });

    test('returns null when partial contains space', () {
      expect(detectMentionTrigger('@hello world', 12), isNull);
    });

    test('returns null when partial contains newline', () {
      expect(detectMentionTrigger('@hello\nworld', 12), isNull);
    });

    test('returns null when no @', () {
      expect(detectMentionTrigger('hello world', 5), isNull);
    });

    test('returns null for cursor before @', () {
      expect(detectMentionTrigger('hello @bob', 3), isNull);
    });

    test('returns empty filter for bare @', () {
      final trigger = detectMentionTrigger('@', 1);
      expect(trigger, isNotNull);
      expect(trigger!.filter, '');
    });

    test('handles cursor at 0', () {
      expect(detectMentionTrigger('@bob', 0), isNull);
    });
  });

  group('decodeBadgePrefs / encodeBadgePrefs', () {
    test('round-trip preserves data', () {
      final prefs = {'member-1': 'mentions_only', 'member-2': 'all'};
      final encoded = SystemSettingsMapper.encodeBadgePrefs(prefs);
      final decoded = SystemSettingsMapper.decodeBadgePrefs(encoded);
      expect(decoded, prefs);
    });

    test('decode empty string returns empty map', () {
      expect(SystemSettingsMapper.decodeBadgePrefs(''), const <String, String>{});
    });

    test('decode {} returns empty map', () {
      expect(SystemSettingsMapper.decodeBadgePrefs('{}'), const <String, String>{});
    });

    test('decode malformed JSON returns empty map', () {
      expect(SystemSettingsMapper.decodeBadgePrefs('{broken'), const <String, String>{});
    });

    test('encode empty map returns {}', () {
      expect(SystemSettingsMapper.encodeBadgePrefs({}), '{}');
    });
  });
}
