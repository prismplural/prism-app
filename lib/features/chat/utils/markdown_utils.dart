/// Utilities for stripping markdown syntax to plain text.
///
/// Used for reply-quote previews where compact, readable text is required.
/// Regex-based (not parser-based) for performance in visible scroll rows.
library;

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/chat/utils/mention_utils.dart';

final _bold = RegExp(r'\*\*(.+?)\*\*');
final _italicStar = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
final _italicUnderscore = RegExp(r'(?<!_)_(?!_)(.+?)(?<!_)_(?!_)');
final _inlineCode = RegExp(r'`([^`]+)`');
final _link = RegExp(r'\[([^\]]+)\]\([^)]+\)');

/// Strip chat markdown syntax to plain text. Used for reply-quote previews.
///
/// Removes **bold**, *italic*, _italic_, `code`, and [link](url) markers,
/// leaving the visible text content. Also resolves `@[uuid]` mention tokens
/// to `@Name` via [authorMap], falling back to `@Unknown` for missing IDs.
String stripChatMarkdown(String raw, Map<String, Member>? authorMap) {
  var out = raw;
  out = out.replaceAllMapped(_bold, (m) => m.group(1)!);
  out = out.replaceAllMapped(_italicStar, (m) => m.group(1)!);
  out = out.replaceAllMapped(_italicUnderscore, (m) => m.group(1)!);
  out = out.replaceAllMapped(_inlineCode, (m) => m.group(1)!);
  out = out.replaceAllMapped(_link, (m) => m.group(1)!);
  final nameMap = <String, String>{
    if (authorMap != null)
      for (final e in authorMap.entries) e.key: e.value.name,
  };
  return replaceMentionsWithNames(out, nameMap);
}
