import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/shared/markdown/member_mention_syntax.dart';

void main() {
  const aliceId = '11111111-2222-3333-4444-555555555555';
  const bobId = 'abcdef12-3456-7890-abcd-ef1234567890';

  group('MemberMentionSyntax', () {
    test('parses strict UUID mention tokens', () {
      final nodes = md.Document(
        inlineSyntaxes: [MemberMentionSyntax()],
      ).parseInline('hi @[$aliceId]');

      final mentions = nodes.whereType<md.Element>().where(
        (element) => element.tag == memberMentionTag,
      );

      expect(mentions, hasLength(1));
      expect(mentions.single.attributes['id'], aliceId);
    });

    test('ignores malformed mention tokens', () {
      final nodes = md.Document(
        inlineSyntaxes: [MemberMentionSyntax()],
      ).parseInline('@[not-a-uuid]');

      final mentions = nodes.whereType<md.Element>().where(
        (element) => element.tag == memberMentionTag,
      );

      expect(mentions, isEmpty);
    });
  });

  group('detectMemberMentionTrigger', () {
    test('detects @ at start, after space, and after newline', () {
      expect(detectMemberMentionTrigger('@ali', 4)?.filter, 'ali');
      expect(detectMemberMentionTrigger('hi @bo', 6)?.filter, 'bo');
      expect(detectMemberMentionTrigger('hi\n@', 4)?.filter, '');
    });

    test('ignores email-like and closed triggers', () {
      expect(detectMemberMentionTrigger('email@foo', 9), isNull);
      expect(detectMemberMentionTrigger('@hello world', 12), isNull);
      expect(detectMemberMentionTrigger('@hello\nworld', 12), isNull);
    });
  });

  group('replaceMemberMentionsWithNames', () {
    test('replaces known IDs and uses Unknown for missing IDs', () {
      expect(
        replaceMemberMentionsWithNames('@[$aliceId] and @[$bobId]', {
          aliceId: 'Alice',
        }),
        '@Alice and @Unknown',
      );
    });
  });

  group('AtomicMemberMentionFormatter', () {
    const formatter = AtomicMemberMentionFormatter();

    test('cursor snaps out of the middle of a mention', () {
      const text = 'Hi @[$aliceId] there';
      final insideMention = text.indexOf('@[') + 5;

      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: text),
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: insideMention),
        ),
      );

      expect(result.selection.baseOffset, text.indexOf('@['));
    });

    test('typing inside a mention replaces the whole token', () {
      const oldText = 'Hi @[$aliceId] there';
      final insideMention = oldText.indexOf('@[') + 5;
      final newText = oldText.replaceRange(insideMention, insideMention, 'x');

      final result = formatter.formatEditUpdate(
        TextEditingValue(
          text: oldText,
          selection: TextSelection.collapsed(offset: insideMention),
        ),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: insideMention + 1),
        ),
      );

      expect(result.text, 'Hi x there');
    });
  });
}
