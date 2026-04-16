import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/markdown_utils.dart';

void main() {
  const uuid = '11111111-2222-3333-4444-555555555555';

  Member makeMember(String name) => Member(
        id: uuid,
        name: name,
        createdAt: DateTime(2026, 4, 16),
      );

  group('stripChatMarkdown — markdown stripping', () {
    test('strips bold', () {
      expect(stripChatMarkdown('**bold**', null), 'bold');
    });

    test('strips italic (star)', () {
      expect(stripChatMarkdown('*italic*', null), 'italic');
    });

    test('strips italic (underscore)', () {
      expect(stripChatMarkdown('_italic_', null), 'italic');
    });

    test('strips inline code', () {
      expect(stripChatMarkdown('`code`', null), 'code');
    });

    test('strips link, keeps label', () {
      expect(stripChatMarkdown('[link text](https://x)', null), 'link text');
    });

    test('leaves unclosed bold as-is', () {
      expect(stripChatMarkdown('**un', null), '**un');
    });

    test('strips nested bold + italic', () {
      expect(
        stripChatMarkdown('**bold with _italic_ inside**', null),
        'bold with italic inside',
      );
    });

    test('empty string returns empty string', () {
      expect(stripChatMarkdown('', null), '');
    });
  });

  group('stripChatMarkdown — mention resolution', () {
    test('resolves mention from authorMap', () {
      final authorMap = {uuid: makeMember('Alice')};
      expect(
        stripChatMarkdown('hi @[$uuid]', authorMap),
        'hi @Alice',
      );
    });

    test('falls back to @Unknown for missing ID', () {
      expect(
        stripChatMarkdown('hi @[$uuid]', {}),
        'hi @Unknown',
      );
    });

    test('falls back to @Unknown when authorMap is null', () {
      expect(
        stripChatMarkdown('hi @[$uuid]', null),
        'hi @Unknown',
      );
    });

    test('complex: bold + mention + inline code', () {
      final authorMap = {uuid: makeMember('Alice')};
      expect(
        stripChatMarkdown('**Hey @[$uuid], check `this`**', authorMap),
        'Hey @Alice, check this',
      );
    });
  });
}
