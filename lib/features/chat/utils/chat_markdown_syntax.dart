import 'package:markdown/markdown.dart' as md;

/// Matches @[uuid] mention tokens (strict 36-char UUID).
class MentionSyntax extends md.InlineSyntax {
  MentionSyntax()
      : super(
          r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]',
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.empty('mention');
    element.attributes['id'] = match.group(1)!;
    parser.addNode(element);
    return true;
  }
}

/// Escape leading `#` markers so they render as literal text.
/// Chat does not support headings; the block parser is otherwise CommonMark.
String escapeLeadingHeadings(String input) {
  return input.split('\n').map((line) {
    final m = RegExp(r'^(#{1,6})\s').firstMatch(line);
    return m != null ? '\\${m.group(0)}${line.substring(m.end)}' : line;
  }).join('\n');
}

/// Fast check: does the string contain any char that could trigger markdown
/// or a mention? Used by the widget's fast path to skip parsing entirely.
bool hasMarkdownChars(String input) {
  for (var i = 0; i < input.length; i++) {
    switch (input[i]) {
      case '*':
      case '_':
      case '`':
      case '[':
      case '@':
        return true;
    }
  }
  return false;
}
