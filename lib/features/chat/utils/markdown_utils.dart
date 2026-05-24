/// Utilities for stripping markdown syntax to plain text.
///
/// Used for reply-quote previews where compact, readable text is required.
/// Regex-based (not parser-based) for performance in visible scroll rows.
library;

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

final _bold = RegExp(r'\*\*(.+?)\*\*');

// Approximated CommonMark flanking: `*` may not flank whitespace, `_` may
// not flank a Unicode letter/digit. Dart's `\w` is ASCII-only, hence the
// explicit `\p{L}\p{N}_` class for the underscore variant.
final _italicStar =
    RegExp(r'(?<!\*)\*(?![\s*])([^*]+?)(?<![\s*])\*(?!\*)');
final _italicUnderscore = RegExp(
  r'(?<![\p{L}\p{N}_])_(?![\s_])([^_]+?)(?<![\s_])_(?![\p{L}\p{N}_])',
  unicode: true,
);
final _inlineCode = RegExp(r'`([^`]+)`');
// `(?<!@)` skips `@[uuid](text)` so a mention followed by parenthetical
// text (e.g. pronouns) survives downstream mention resolution.
final _link = RegExp(r'(?<!@)\[([^\]]+)\]\([^)]+\)');
final _smallText = RegExp(r'(^|\n)-#\s+(.+)');

/// Strip markdown syntax markers, leaving the visible text content.
///
/// Removes **bold**, *italic*, _italic_, `code`, [link](url), and the
/// line-leading `-#` small-text marker. Mention tokens (`@[uuid]`) are
/// left untouched so callers can resolve them with their own name map
/// or render them as styled chips.
String stripMarkdownMarkers(String raw) {
  var out = raw;
  out = out.replaceAllMapped(_bold, (m) => m.group(1)!);
  out = out.replaceAllMapped(_italicStar, (m) => m.group(1)!);
  out = out.replaceAllMapped(_italicUnderscore, (m) => m.group(1)!);
  out = out.replaceAllMapped(_inlineCode, (m) => m.group(1)!);
  out = out.replaceAllMapped(_link, (m) => m.group(1)!);
  out = out.replaceAllMapped(_smallText, (m) => '${m.group(1)}${m.group(2)}');
  return out;
}

/// Strip chat markdown syntax to plain text. Used for reply-quote previews.
///
/// Removes **bold**, *italic*, _italic_, `code`, [link](url), and `-# small`
/// markers, leaving the visible text content. Also resolves `@[uuid]` mention
/// tokens to `@Name` via [authorMap], falling back to `@Unknown` for missing IDs.
String stripChatMarkdown(String raw, Map<String, Member>? authorMap) {
  final out = stripMarkdownMarkers(raw);
  final nameMap = <String, String>{
    if (authorMap != null)
      for (final e in authorMap.entries) e.key: e.value.name,
  };
  return replaceMentionsWithNames(out, nameMap);
}
