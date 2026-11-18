import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:prism_plurality/features/chat/emoji/emoji_name_completion.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

/// Flatten a Markdown parse into tags, text and attributes so two parses can be
/// compared without depending on object identity.
String _flattenParse(String text) {
  final document = md.Document(
    extensionSet: chatExtensionSet,
    encodeHtml: false,
  );
  final nodes = document.parseLines(const LineSplitter().convert(text));
  final buffer = StringBuffer();

  void visit(md.Node node) {
    if (node is md.Text) {
      buffer.write('T(${node.text})');
      return;
    }
    if (node is! md.Element) return;
    final keys = node.attributes.keys.toList()..sort();
    buffer.write('E(${node.tag}');
    for (final key in keys) {
      buffer.write(',$key=${node.attributes[key]}');
    }
    buffer.write(')[');
    for (final child in node.children ?? const <md.Node>[]) {
      visit(child);
    }
    buffer.write(']');
  }

  for (final node in nodes) {
    visit(node);
  }
  return buffer.toString();
}

/// The single analysis marker inside a probe string, if any.
String _markerIn(String probe) {
  for (var i = 0; i < probe.length; i++) {
    final unit = probe.codeUnitAt(i);
    if (unit >= 0xFDD0 && unit <= 0xFDEF) return probe[i];
  }
  return '';
}

void main() {
  EmojiCompletionTrigger? detect(String text, int caret) =>
      detectEmojiCompletionTriggerAt(text, caret);

  group('detectEmojiCompletionTrigger', () {
    test('finds a token at the start of the draft', () {
      final trigger = detect(':sun', 4);

      expect(trigger, isNotNull);
      expect(trigger!.start, 0);
      expect(trigger.end, 4);
      expect(trigger.prefix, 'sun');
    });

    test('finds a token later in the draft and lowercases the prefix', () {
      final trigger = detect('hello :Sunflower', 16);

      expect(trigger, isNotNull);
      expect(trigger!.start, 6);
      expect(trigger.end, 16);
      expect(trigger.prefix, 'sunflower');
    });

    test('accepts a token after a newline and after an opening delimiter', () {
      expect(detect('hi\n:sun', 7)?.start, 3);
      expect(detect('(:sun', 5)?.start, 1);
      expect(detect('":sun', 5)?.start, 1);
    });

    test('accepts underscores, digits, plus and hyphen in the prefix', () {
      expect(detect(':grinning_face', 14)?.prefix, 'grinning_face');
      expect(detect(':upside-down', 12)?.prefix, 'upside-down');
      expect(detect(':1st_place', 10)?.prefix, '1st_place');
    });

    test('a bare colon does not open', () {
      expect(detect(':', 1), isNull);
      expect(detect('note:', 5), isNull);
    });

    test('a space in the token body does not open', () {
      expect(detect(': sun', 5), isNull);
      expect(detect(':sun flower', 11), isNull);
    });

    test('does not trigger on URL schemes', () {
      const url = 'see https://example.com/sun';
      expect(detect(url, url.length), isNull);
      // A colon-triggered token after the URL still works.
      expect(detect('$url :sun', url.length + 5)?.start, url.length + 1);
    });

    test('does not trigger on clock times', () {
      expect(detect('meet at 12:30', 13), isNull);
      expect(detect('10:30', 5), isNull);
    });

    test('does not trigger on a colon after a letter or another colon', () {
      expect(detect('a:sun', 5), isNull);
      expect(detect('::sun', 5), isNull);
    });

    test('does not trigger inside an inline code span', () {
      expect(detect('`:sun', 5), isNull);
      expect(detect('x `:sun`', 7), isNull);
      expect(detect('x ``:sun``', 8), isNull);
    });

    test('does not trigger inside a fenced code block', () {
      const block = '```\n:sun';
      expect(detect(block, block.length), isNull);
      const dartBlock = '```dart\ncode\n:sun';
      expect(detect(dartBlock, dartBlock.length), isNull);
    });

    test('triggers again after a fenced code block closes', () {
      final trigger = detect('```\nx\n```\n:sun', 14);

      expect(trigger, isNotNull);
      expect(trigger!.prefix, 'sun');
    });

    test('code spans and fences only look at the draft, not other text', () {
      // A closed span earlier in the line does not block a later token.
      final trigger = detect('use `code` then :sun', 20);

      expect(trigger, isNotNull);
      expect(trigger!.prefix, 'sun');
    });

    test('does not trigger when the caret is inside the token', () {
      expect(detect('a :sun b', 5), isNull);
      expect(detect(':sun', 2), isNull);
    });

    test('does not trigger with a non-collapsed selection', () {
      const selection = TextSelection(baseOffset: 0, extentOffset: 4);

      expect(detectEmojiCompletionTrigger(':sun', selection), isNull);

      const collapsed = TextSelection.collapsed(offset: 4);
      expect(detectEmojiCompletionTrigger(':sun', collapsed), isNotNull);
    });

    test('does not trigger for an over-long token', () {
      final longToken = ':${'a' * (emojiCompletionMaxPrefixLength + 1)}';

      expect(detect(longToken, longToken.length), isNull);

      final atLimit = ':${'a' * emojiCompletionMaxPrefixLength}';
      expect(detect(atLimit, atLimit.length), isNotNull);
    });

    test('does not split a grapheme cluster at the caret', () {
      // Caret sits directly before the emoji variation selector.
      expect(detect(':sun\uFE0F', 4), isNull);
      // Caret sits directly before a combining mark.
      expect(detect(':sun\u0301', 4), isNull);
      // Caret sits inside a ZWJ sequence.
      expect(detect(':sun\u200D\u{1F525}', 4), isNull);
    });

    test(
      'insertion point after an unrelated emoji is not part of a cluster',
      () {
        // `sun` ends the token and the next code point starts a new cluster.
        final trigger = detect(':sun😊', 4);

        expect(trigger, isNotNull);
        expect(trigger!.end, 4);
      },
    );

    test('equality is value based for the composer diff check', () {
      expect(detect(':sun', 4), detect(':sun', 4));
      expect(detect(':sun', 4), isNot(detect('hi :sun', 7)));
      expect(detect(':sun', 4)!.hashCode, detect(':sun', 4)!.hashCode);
    });
  });

  group('isInsideCodeContext', () {
    test('reports code spans and fences around an offset', () {
      expect(isInsideCodeContext('`:sun', 1), isTrue);
      expect(isInsideCodeContext('```\n:sun', 4), isTrue);
      expect(isInsideCodeContext('plain :sun', 6), isFalse);
    });
  });

  group('searchEmojiNames', () {
    test('finds an exact annotation from the shipped catalog', () {
      final results = searchEmojiNames('sunflower');

      expect(results, isNotEmpty);
      expect(results.first.emoji, '🌻');
      expect(results.first.keywords.first, 'sunflower');
    });

    test('finds keywords and ranks the exact keyword first', () {
      final results = searchEmojiNames('rocket');

      expect(results.first.emoji, '🚀');
      expect(results.length, lessThanOrEqualTo(emojiCompletionMaxResults));
    });

    test('matches hyphenated annotations', () {
      expect(searchEmojiNames('upside-down').first.emoji, '🙃');
    });

    test('is case insensitive and trims the query', () {
      final lower = searchEmojiNames('sunflower');
      final upper = searchEmojiNames('  SUNFLOWER  ');

      expect(
        upper.map((emoji) => emoji.emoji).toList(),
        lower.map((emoji) => emoji.emoji).toList(),
      );
    });

    test('is bounded even for a broad prefix', () {
      final results = searchEmojiNames('sun');

      expect(results.length, emojiCompletionMaxResults);
      expect(results.first.emoji, '☀️');
      expect(searchEmojiNames('sun', limit: 3).length, 3);
    });

    test('returns nothing for empty or unmatched prefixes', () {
      expect(searchEmojiNames(''), isEmpty);
      expect(searchEmojiNames('   '), isEmpty);
      expect(searchEmojiNames('zzzznotanemoji'), isEmpty);
    });

    test('is deterministic across calls', () {
      final first = searchEmojiNames('heart').map((e) => e.emoji).toList();
      final second = searchEmojiNames('heart').map((e) => e.emoji).toList();

      expect(second, first);
    });

    test('ranks annotation and keyword matches in a documented order', () {
      final index = EmojiNameIndex.fromCategories(const [
        CategoryEmoji(Category.SMILEYS, [
          Emoji('🥇', 'alpha thing | alpha | first'),
          Emoji('🥈', 'beta alpha | beta | second'),
          Emoji('🥉', 'gamma | contains alpha inside'),
        ]),
      ]);

      expect(index.search('alpha thing').first.emoji, '🥇');
      expect(index.search('alpha').first.emoji, '🥇');
      expect(index.search('beta').first.emoji, '🥈');
      expect(index.search('beta').length, 1);
      expect(index.search('alpha', limit: 1).length, 1);
      expect(index.search('alpha').length, 3);
    });

    test('drops duplicate glyphs from a catalog', () {
      final index = EmojiNameIndex.fromCategories(const [
        CategoryEmoji(Category.SMILEYS, [Emoji('🌻', 'sunflower | flower')]),
        CategoryEmoji(Category.ANIMALS, [
          Emoji('🌻', 'sunflower duplicate | flower'),
        ]),
      ]);

      expect(index.search('sunflower').length, 1);
    });
  });

  // These pin the completion trigger to what the chat renderer actually treats
  // as code, so issue #20's "do not trigger in code" is measured against the
  // renderer rather than against a hand-written fence rule.
  //
  // Renderer boundary, read from the pinned packages:
  // - markdown 7.3.1 `FencedCodeBlockSyntax` (`codeFencePattern` in
  //   `lib/src/patterns.dart`): a fence is a run of 3+ backticks or 3+ tildes
  //   indented at most 3 spaces. Its `parseChildLines` only closes on a line
  //   whose marker `startsWith(openingMarker)` and that has no info string, so
  //   a 3-backtick line cannot close a 4-backtick fence.
  // - markdown 7.3.1 `CodeBlockSyntax` (`indentPattern` = 4 spaces or a tab):
  //   a 4+ space indented line at block start is an indented code block, and a
  //   fence indented 4+ spaces never matches `codeFencePattern`, so it is not a
  //   fence.
  // - flutter_markdown_plus 1.0.7 builds `md.Document(...)` without
  //   `withDefaultBlockSyntaxes: false`, so those default syntaxes stay enabled
  //   next to `chatExtensionSet` (`lib/features/chat/utils/chat_markdown_syntax.dart`).
  group('code fences follow the renderer boundary', () {
    test('a tilde fence opens a code block', () {
      const draft = '~~~\n:sun\n~~~';

      // Caret at the end of `:sun`, inside the tilde-fenced block.
      expect(detect(draft, 8), isNull);
    });

    test('a token after a closed tilde fence completes normally', () {
      const draft = '~~~\nx\n~~~\n:sun';

      expect(detect(draft, draft.length), isNotNull);
    });

    test('a 3-backtick line inside a 4-backtick fence does not close it', () {
      // The opening marker is four backticks, so a three-backtick line is
      // content and the block is still open at `:sun` — nothing closes it here.
      const draft = '````\n```\n:sun';

      expect(detect(draft, draft.length), isNull);
    });

    test('a matching 4-backtick fence closes and reopens completion', () {
      const inside = '````\n:sun\n````';
      expect(detect(inside, 9), isNull);

      const afterClose = '````\nx\n````\n:sun';
      expect(detect(afterClose, afterClose.length), isNotNull);
    });

    test('a fence indented three spaces still opens a code block', () {
      const draft = '   ```\n:sun';

      expect(detect(draft, draft.length), isNull);
    });

    test('a fence indented four spaces is not a fence', () {
      // Four spaces then a fence line is an indented code block, so the
      // unindented `:sun` after it starts a paragraph and completion opens.
      const draft = '    ```\n:sun';

      expect(detect(draft, draft.length), isNotNull);
    });

    test('a four-space indented code block suppresses completion', () {
      // Indented code is code: `:sun` inside it must not open a popup, even
      // though there is no fence character on the line.
      const draft = '    :sun';

      expect(detect(draft, draft.length), isNull);
    });

    test('indented code continues on a following indented line', () {
      const draft = '    a\n    :sun';

      expect(detect(draft, draft.length), isNull);
    });

    test('an indented line after a paragraph is not indented code', () {
      // CommonMark lazy continuation: the indented line continues the
      // paragraph, so `:sun` is text and completion opens.
      const draft = 'hi\n    :sun';

      expect(detect(draft, draft.length), isNotNull);
    });

    test('a backtick fence with a backtick in its info is not a fence', () {
      // The renderer's backtick info string is `[^`]*`, so this line is text.
      const draft = '```x`y\n:sun';

      expect(detect(draft, draft.length), isNotNull);
    });
  });

  group('result limit contract', () {
    /// Three `alpha` matches, ranked 🥇 (prefix) then 🥉/🥈 (substring).
    EmojiNameIndex alphaIndex() => EmojiNameIndex.fromCategories(const [
      CategoryEmoji(Category.SMILEYS, [
        Emoji('🥇', 'alpha thing | alpha | first'),
        Emoji('🥈', 'beta alpha | beta | second'),
        Emoji('🥉', 'gamma | contains alpha inside'),
      ]),
    ]);

    test('a smaller limit after a larger one recomputes', () {
      final index = alphaIndex();

      expect(index.search('alpha').length, 3);
      expect(index.search('alpha', limit: 1).length, 1);
      expect(index.search('alpha', limit: 2).length, 2);
      expect(index.search('alpha').length, 3);
    });

    test('a larger limit after a smaller one recomputes', () {
      final index = alphaIndex();

      expect(index.search('alpha', limit: 1).length, 1);
      expect(index.search('alpha').length, 3);
    });

    test('the real catalog also recomputes when the limit changes', () {
      expect(searchEmojiNames('sun').length, emojiCompletionMaxResults);
      expect(searchEmojiNames('sun', limit: 3).length, 3);
      expect(searchEmojiNames('sun').length, emojiCompletionMaxResults);
    });

    test(
      'a non-positive limit returns nothing and leaves the cache intact',
      () {
        expect(searchEmojiNames('sun').length, emojiCompletionMaxResults);

        expect(searchEmojiNames('sun', limit: 0), isEmpty);
        expect(searchEmojiNames('sun', limit: -5), isEmpty);

        // The previous entry is still valid for the same request.
        expect(searchEmojiNames('sun').length, emojiCompletionMaxResults);
      },
    );

    test('a limit above the cap is clamped to the popup maximum', () {
      final capped = searchEmojiNames('sun', limit: 1000);

      expect(capped.length, emojiCompletionMaxResults);
      expect(
        capped.map((emoji) => emoji.emoji).toList(),
        searchEmojiNames('sun').map((emoji) => emoji.emoji).toList(),
      );
    });
  });

  // Measured against `md.Document(extensionSet: chatExtensionSet)` by the parent
  // probe (verification/emoji-corpus-probe). These expectations are the
  // renderer's; the checker now borrows that grammar instead of guessing.
  group('renderer corpus (measured)', () {
    final cases = <({String id, String draft, bool isCode})>[
      (
        id: 'BQ1 fence inside a blockquote',
        draft: '> ```\n> :sun\n> ```',
        isCode: true,
      ),
      (
        id: 'BQ2 indented code in a blockquote',
        draft: '>     :sun',
        isCode: true,
      ),
      (
        id: 'BQ3 lazy continuation in a blockquote',
        draft: '> hi\n>     :sun',
        isCode: false,
      ),
      (
        id: 'L1 four-space continuation in a list item',
        draft: '- item\n\n    :sun',
        isCode: false,
      ),
      (
        id: 'L5 fence inside an indented list item',
        draft: '  - item\n      ```\n      :sun',
        isCode: true,
      ),
      (
        id: 'ML1 span closing after the caret',
        draft: '`code\n:sun`',
        isCode: true,
      ),
      (
        id: 'ML2 span closed before the token',
        draft: 'a `code\nmore` :sun',
        isCode: false,
      ),
      (id: 'TB1 tab-indented code', draft: '\t:sun', isCode: true),
      (
        id: 'TB2 tab-indented code continuation',
        draft: '\tcode\n\t:sun',
        isCode: true,
      ),
      (
        id: 'TB3 tab line after a paragraph',
        draft: 'hi\n\t:sun',
        isCode: false,
      ),
    ];

    for (final testCase in cases) {
      test('${testCase.id} is ${testCase.isCode ? 'code' : 'not code'}', () {
        final colon = testCase.draft.indexOf(':');

        expect(
          isInsideCodeContext(testCase.draft, colon),
          testCase.isCode,
          reason: testCase.draft,
        );
      });
    }

    test('the analysis marker does not change the parsed tree', () {
      for (final testCase in cases) {
        final colon = testCase.draft.indexOf(':');
        final probe = emojiCodeContextProbe(testCase.draft, colon);
        final marker = _markerIn(probe);

        expect(probe, isNot(testCase.draft), reason: testCase.id);
        expect(marker, isNotEmpty, reason: testCase.id);
        expect(
          _flattenParse(probe).replaceAll(marker, ':'),
          _flattenParse(escapeLeadingHeadings(testCase.draft)),
          reason: testCase.id,
        );
      }
    });
  });

  group('analysis marker safety', () {
    test('a noncharacter already in the draft is skipped', () {
      // `_markerIn` would find the source's own U+FDD0 first, so assert the
      // substituted code unit at the colon instead: the next candidate is used
      // and the source noncharacter survives untouched.
      const draft = '\uFDD0 :sun';
      final probe = emojiCodeContextProbe(draft, 2);

      expect(probe.codeUnitAt(2), 0xFDD1);
      expect(probe.codeUnitAt(0), 0xFDD0);
      // No code starter, so the cheap no-code path answers here.
      expect(isInsideCodeContext(draft, 2), isFalse);
    });

    test('an existing noncharacter is skipped inside the parsed path too', () {
      // A closed span elsewhere keeps this draft on the parsing path while the
      // source still contains U+FDD0.
      const draft = '\uFDD0 `x` :sun';
      final colon = draft.lastIndexOf(':');
      final probe = emojiCodeContextProbe(draft, colon);

      expect(probe.codeUnitAt(colon), 0xFDD1);
      expect(probe.codeUnitAt(0), 0xFDD0);
      expect(isInsideCodeContext(draft, colon), isFalse);
    });

    test('using up all 32 candidates fails closed', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 0x20; i++) {
        buffer.write(String.fromCharCode(0xFDD0 + i));
      }
      // A backtick keeps the draft in the "could contain code" path.
      final draft = '`$buffer :sun';

      expect(isInsideCodeContext(draft, draft.lastIndexOf(':')), isTrue);
    });

    test('a marker lost to a link title fails closed', () {
      // A closed span earlier keeps the draft on the parsing path; the marker is
      // then consumed by the link title, which is an attribute, not text.
      const parsed = '`x` [y](/u ":sun")';
      expect(isInsideCodeContext(parsed, parsed.lastIndexOf(':')), isTrue);

      // Without any code starter the cheap bypass answers instead, and the
      // draft is ordinary text.
      const plain = '[x](/u ":sun")';
      expect(isInsideCodeContext(plain, plain.indexOf(':')), isFalse);
    });

    test('a marker lost to a fence info string fails closed', () {
      const draft = '``` :sun';

      expect(isInsideCodeContext(draft, 4), isTrue);
    });

    test('an offset that is not a colon fails closed', () {
      // The checker only marks validated token colons; substituting any other
      // character could change the structure the probe relies on.
      expect(isInsideCodeContext('a:b', 0), isTrue);
      expect(isInsideCodeContext('abc', 1), isTrue);
    });
  });

  group('unfinished span guard', () {
    test('an unclosed span on the caret line suppresses', () {
      expect(isInsideCodeContext('`:sun', 1), isTrue);
      expect(isInsideCodeContext('x `:sun', 3), isTrue);
    });

    test('an escaped backtick does not suppress', () {
      // Directly after the tick the colon is not a valid token colon (a backtick
      // is not a trigger-preceding character), so it is text either way.
      const adjacent = 'x \\`:sun';
      expect(isInsideCodeContext(adjacent, adjacent.indexOf(':')), isFalse);
      expect(detect(adjacent, adjacent.length), isNull);

      // Spaced out the token is valid and completes: the escaped tick is text,
      // not an open code span.
      const spaced = 'x \\` :sun';
      expect(isInsideCodeContext(spaced, spaced.indexOf(':')), isFalse);
      expect(detect(spaced, spaced.length), isNotNull);
    });

    test('a span after an earlier closed fence still suppresses', () {
      const draft = '```\nx\n```\n`:sun';

      expect(isInsideCodeContext(draft, draft.indexOf(':')), isTrue);
    });

    test('stray runs on an earlier line do not suppress', () {
      // The control from the fence work: this line is a paragraph, so the
      // opener on line 1 must not make the token "code".
      const draft = '```x`y\n:sun';

      expect(isInsideCodeContext(draft, draft.indexOf(':')), isFalse);
    });
  });

  group('renderer budget', () {
    test('a long plain draft still completes without a parse', () {
      final draft = '${'a' * 3000} :sun';

      expect(isInsideCodeContext(draft, draft.indexOf(':')), isFalse);
      expect(detect(draft, draft.length), isNotNull);
    });

    test('an over-budget draft that could contain code hides suggestions', () {
      final draft = '`x\n${'a' * 3000} :sun';

      expect(isInsideCodeContext(draft, draft.indexOf(':')), isTrue);
    });

    test('exactly at the budget the draft is still parsed', () {
      final padding = 'a' * (chatMarkdownParseLimit - ' :sun'.length);
      final draft = '$padding :sun';

      expect(draft.length, chatMarkdownParseLimit);
      expect(isInsideCodeContext(draft, draft.length - 4), isFalse);
    });
  });
}
