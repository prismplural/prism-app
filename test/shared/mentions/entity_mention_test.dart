import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/mentions/entity_mention.dart';

void main() {
  group('entity mention parsing', () {
    test('extracts canonical targets and preserves legacy member targets', () {
      const legacy = '11111111-2222-3333-4444-555555555555';
      final mentions = extractEntityMentions(
        'hi @[member:m1] @[group:g1] @[note:n1] @[board:b1] '
        '@[conversation:c1] @[$legacy]',
      );

      expect(mentions.map((m) => m.target.type), [
        EntityMentionType.member,
        EntityMentionType.group,
        EntityMentionType.note,
        EntityMentionType.board,
        EntityMentionType.conversation,
        EntityMentionType.member,
      ]);
      expect(mentions.last.target.id, legacy);
      expect(mentions.last.target.isLegacyMember, isTrue);
    });

    test('ignores unknown types and invalid ids', () {
      expect(extractEntityMentions('@[habit:h1]'), isEmpty);
      expect(extractEntityMentions('@[member:]'), isEmpty);
      expect(extractEntityMentions('@[member: leading]'), isEmpty);
      expect(extractEntityMentions('@[member:trailing ]'), isEmpty);
      expect(extractEntityMentions('@[member:has\nbreak]'), isEmpty);
    });

    test('ignores mentions in inline code and fenced code', () {
      final mentions = extractEntityMentions(
        'ok @[member:m1] `@[group:g1]`\n'
        '```dart\n@[note:n1]\n```\n'
        'after @[board:b1]',
      );

      expect(mentions.map((m) => m.target.type), [
        EntityMentionType.member,
        EntityMentionType.board,
      ]);
      expect(mentions.map((m) => m.target.id), ['m1', 'b1']);
    });

    test('ignores mentions in markdown link destinations', () {
      final mentions = extractEntityMentions(
        '[visible](prism://@[note:secret]) @[note:visible]',
      );

      expect(mentions, hasLength(1));
      expect(mentions.single.target.id, 'visible');
    });

    test('serializes canonical tokens', () {
      expect(
        serializeEntityMention(EntityMentionType.conversation, 'abc'),
        '@[conversation:abc]',
      );
      expect(
        () => serializeEntityMention(EntityMentionType.note, ' bad'),
        throwsArgumentError,
      );
    });
  });

  group('detectEntityMentionTrigger', () {
    test('finds trigger at start or after whitespace', () {
      expect(detectEntityMentionTrigger('@al', 3)?.filter, 'al');
      expect(detectEntityMentionTrigger('hello @bo', 9)?.filter, 'bo');
      expect(detectEntityMentionTrigger('hello\n@', 7)?.filter, '');
    });

    test('rejects email-like and closed triggers', () {
      expect(detectEntityMentionTrigger('email@foo', 9), isNull);
      expect(detectEntityMentionTrigger('@hello world', 12), isNull);
      expect(detectEntityMentionTrigger('@[member:x]', 10), isNull);
    });
  });

  group('AtomicEntityMentionFormatter', () {
    const formatter = AtomicEntityMentionFormatter();

    test('cursor snaps out of canonical mentions', () {
      const text = 'hi @[note:n1] there';
      final insideMention = text.indexOf('@[') + 1;

      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: text),
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: insideMention),
        ),
      );

      expect(result.selection.baseOffset, text.indexOf('@['));
    });

    test('typing inside a legacy mention replaces the whole token', () {
      const id = '11111111-2222-3333-4444-555555555555';
      const oldText = 'hi @[$id] there';
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

      expect(result.text, 'hi x there');
      expect(result.selection.baseOffset, 'hi x'.length);
    });
  });
}
