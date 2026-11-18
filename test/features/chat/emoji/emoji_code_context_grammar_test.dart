import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:prism_plurality/features/chat/emoji/emoji_name_completion.dart';
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';

/// One synthetic draft from the renderer-differential corpus.
///
/// Each case pins a block or inline construct where the composer's
/// `isInsideCodeContext` predicate and the chat renderer's own Markdown grammar
/// could disagree. The drafts are synthetic Markdown only: no user data, no
/// member or message content, and nothing is read from disk.
class _GrammarCase {
  const _GrammarCase(
    this.id,
    this.draft,
    this.colonIndex,
    this.caretOffset,
    this.rendererIsCode,
  );

  /// Stable case id from the corpus (blockquote, list, multiline, tab cases).
  final String id;

  /// The complete synthetic draft.
  final String draft;

  /// Offset of the `:` that introduces the `:sun` token.
  final int colonIndex;

  /// Caret offset the composer sees when completion would be offered.
  final int caretOffset;

  /// Whether the chat renderer places this token inside a code span or block.
  final bool rendererIsCode;
}

const List<_GrammarCase> _cases = <_GrammarCase>[
  // Blockquote containers: the `>` marker is stripped before the child lines
  // are parsed, so a fence or an indented block inside a quote is still code.
  _GrammarCase('BQ1', '> ```\n> :sun\n> ```', 8, 12, true),
  _GrammarCase('BQ2', '>     :sun', 6, 10, true),
  // Control: an indented line lazily continues the paragraph, so it is text.
  _GrammarCase('BQ3', '> hi\n>     :sun', 11, 15, false),
  // List containers: a four-space body under a list item is a paragraph, not
  // code, while a fence nested in the item is code.
  _GrammarCase('L1', '- item\n\n    :sun', 12, 16, false),
  _GrammarCase('L5', '  - item\n      ```\n      :sun', 25, 29, true),
  // Multiline inline spans: the span state carries across the line break.
  _GrammarCase('ML1', '`code\n:sun`', 6, 10, true),
  _GrammarCase('ML2', 'a `code\nmore` :sun', 14, 18, false),
  // Tab-indented blocks: a tab is an indent unit at container start and after
  // a container marker, but not a code block when continuing a paragraph.
  _GrammarCase('TB1', '\t:sun', 1, 5, true),
  _GrammarCase('TB2', '\tcode\n\t:sun', 7, 11, true),
  _GrammarCase('TB3', 'hi\n\t:sun', 4, 8, false),
];

/// Inserted at the token's colon so the parsed tree can be searched for it.
const String _marker = 'PrismGrammarProbeMarker';

/// Whether the chat renderer parses the token at [offset] as code.
///
/// This is the reference oracle, not the product predicate: it parses the draft
/// with the same extension set the message bubble uses and looks for the marker
/// inside a `code` or `pre` element.
bool _rendererTreatsAsCode(String draft, int offset) {
  expect(
    draft.contains(_marker),
    isFalse,
    reason: 'The synthetic marker must not already occur in the draft.',
  );
  final marked = draft.replaceRange(offset, offset, _marker);
  final nodes = md.Document(
    extensionSet: chatExtensionSet,
  ).parseLines(marked.split('\n'));
  expect(
    nodes.any((node) => node.textContent.contains(_marker)),
    isTrue,
    reason:
        'The renderer AST must retain the marker, or this reference '
        'answers a different question than the one being asked.',
  );

  bool insideCode(md.Node node) {
    if (node is! md.Element) return false;
    if ((node.tag == 'code' || node.tag == 'pre') &&
        node.textContent.contains(_marker)) {
      return true;
    }
    return (node.children ?? const <md.Node>[]).any(insideCode);
  }

  return nodes.any(insideCode);
}

void main() {
  group('code-context grammar differential', () {
    for (final grammarCase in _cases) {
      test(
        '${grammarCase.id}: composer suppression matches the chat renderer',
        () {
          final reference = _rendererTreatsAsCode(
            grammarCase.draft,
            grammarCase.colonIndex,
          );
          expect(
            reference,
            grammarCase.rendererIsCode,
            reason:
                '${grammarCase.id}: the recorded corpus expectation must '
                'still match the pinned Markdown grammar. If this fails the '
                'grammar changed, not the composer.',
          );
          expect(
            isInsideCodeContext(grammarCase.draft, grammarCase.colonIndex),
            reference,
            reason:
                '${grammarCase.id}: the composer predicate must agree with '
                'the renderer for the same draft instead of approximating it.',
          );
          expect(
            detectEmojiCompletionTriggerAt(
                  grammarCase.draft,
                  grammarCase.caretOffset,
                ) !=
                null,
            !reference,
            reason:
                '${grammarCase.id}: completion is offered only outside a '
                'code span or block.',
          );
        },
      );
    }
  });
}
