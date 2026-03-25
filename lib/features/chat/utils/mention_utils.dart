/// Mention token format: @[uuid]
/// Used to embed member references in chat message content.
library;

final mentionRegex = RegExp(
  r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]',
);

/// Extract all member IDs mentioned in [content].
List<String> extractMentionIds(String content) {
  return mentionRegex.allMatches(content).map((m) => m.group(1)!).toList();
}

/// Whether [content] contains a mention of [memberId].
bool containsMention(String content, String memberId) {
  return content.contains('@[$memberId]');
}

/// Replace mention tokens with display names.
///
/// Unknown IDs are rendered as `@Unknown`.
String replaceMentionsWithNames(
  String content,
  Map<String, String> nameMap,
) {
  return content.replaceAllMapped(mentionRegex, (match) {
    final id = match.group(1)!;
    final name = nameMap[id] ?? 'Unknown';
    return '@$name';
  });
}

/// Result of detecting a mention trigger in text at a cursor position.
class MentionTrigger {
  const MentionTrigger({required this.atIndex, required this.filter});

  /// Index of the `@` character in the text.
  final int atIndex;

  /// Partial name typed after `@` (may be empty).
  final String filter;
}

/// Detect whether the cursor is inside a mention trigger (`@partial`).
///
/// Returns a [MentionTrigger] if `@` is found preceded by whitespace or
/// start-of-string, with no spaces in the partial. Returns null otherwise.
MentionTrigger? detectMentionTrigger(String text, int cursorPos) {
  if (cursorPos < 0 || cursorPos > text.length) return null;

  final before = text.substring(0, cursorPos);
  final atIndex = before.lastIndexOf('@');
  if (atIndex < 0) return null;

  // `@` must be at start or preceded by whitespace.
  if (atIndex > 0 && before[atIndex - 1] != ' ' && before[atIndex - 1] != '\n') {
    return null;
  }

  final partial = before.substring(atIndex + 1);
  // If there's a space in the partial, the mention is "closed".
  if (partial.contains(' ') || partial.contains('\n')) {
    return null;
  }

  return MentionTrigger(atIndex: atIndex, filter: partial);
}
