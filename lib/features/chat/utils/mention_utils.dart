/// Mention token format: @[uuid]
/// Used to embed member references in chat message content.
library;

import 'package:flutter/services.dart';
import 'package:prism_plurality/domain/models/chat_message.dart';

final mentionRegex = RegExp(
  r'@\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]',
);

/// Extract all member IDs mentioned in [content].
List<String> extractMentionIds(String content) {
  return mentionRegex.allMatches(content).map((m) => m.group(1)!).toList();
}

/// Collect all member IDs referenced by a batch of chat messages.
///
/// This includes:
/// - message authors
/// - reply quote authors
/// - inline mentions in the message body
/// - inline mentions in the reply quote preview content
Set<String> collectReferencedMemberIds(Iterable<ChatMessage> messages) {
  return {
    ...messages.map((m) => m.authorId).whereType<String>(),
    ...messages.map((m) => m.replyToAuthorId).whereType<String>(),
    ...messages.expand((m) => extractMentionIds(m.content)),
    ...messages.expand((m) => extractMentionIds(m.replyToContent ?? '')),
  };
}

/// Whether [content] contains a mention of [memberId].
bool containsMention(String content, String memberId) {
  return content.contains('@[$memberId]');
}

/// Replace mention tokens with display names.
///
/// Unknown IDs are rendered as `@Unknown`.
String replaceMentionsWithNames(String content, Map<String, String> nameMap) {
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
  if (atIndex > 0 &&
      before[atIndex - 1] != ' ' &&
      before[atIndex - 1] != '\n') {
    return null;
  }

  final partial = before.substring(atIndex + 1);
  // If there's a space in the partial, the mention is "closed".
  if (partial.contains(' ') || partial.contains('\n')) {
    return null;
  }

  return MentionTrigger(atIndex: atIndex, filter: partial);
}

/// Keeps `@[uuid]` mentions atomic while editing.
///
/// - Moving the caret inside a mention snaps it to the nearest edge.
/// - Partial edits inside a mention delete or replace the whole mention token
///   instead of exposing broken raw token text.
class AtomicMentionFormatter extends TextInputFormatter {
  const AtomicMentionFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) {
      return _snapSelectionOutOfMention(oldValue.text, newValue);
    }

    final diff = _computeDiff(oldValue.text, newValue.text);
    if (diff == null) {
      return _snapSelectionOutOfMention(newValue.text, newValue);
    }

    final affectedMentions =
        _mentionsOverlapping(oldValue.text, diff.oldStart, diff.oldEnd)
            .where(
              (range) => !_rangeFullyCovered(range, diff.oldStart, diff.oldEnd),
            )
            .toList();

    if (affectedMentions.isEmpty) {
      return _snapSelectionOutOfMention(newValue.text, newValue);
    }

    final expandedStart = affectedMentions
        .map((range) => range.start)
        .fold(diff.oldStart, (a, b) => a < b ? a : b);
    final expandedEnd = affectedMentions
        .map((range) => range.end)
        .fold(diff.oldEnd, (a, b) => a > b ? a : b);
    final insertedText = newValue.text.substring(diff.newStart, diff.newEnd);
    final repairedText =
        oldValue.text.substring(0, expandedStart) +
        insertedText +
        oldValue.text.substring(expandedEnd);
    final cursorOffset = expandedStart + insertedText.length;

    return TextEditingValue(
      text: repairedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  TextEditingValue _snapSelectionOutOfMention(
    String text,
    TextEditingValue value,
  ) {
    final selection = value.selection;
    if (!selection.isValid) return value;

    final baseRange = _mentionContaining(text, selection.baseOffset);
    final extentRange = _mentionContaining(text, selection.extentOffset);
    if (baseRange == null && extentRange == null) return value;

    final snappedBase = _snapOffset(baseRange, selection.baseOffset);
    final snappedExtent = _snapOffset(extentRange, selection.extentOffset);
    return value.copyWith(
      selection: TextSelection(
        baseOffset: snappedBase,
        extentOffset: snappedExtent,
      ),
      composing: TextRange.empty,
    );
  }

  int _snapOffset(_MentionRange? range, int offset) {
    if (range == null) return offset;
    final leftDistance = offset - range.start;
    final rightDistance = range.end - offset;
    return leftDistance < rightDistance ? range.start : range.end;
  }

  _MentionRange? _mentionContaining(String text, int offset) {
    if (offset < 0 || offset > text.length) return null;
    for (final match in mentionRegex.allMatches(text)) {
      if (match.start < offset && offset < match.end) {
        return _MentionRange(match.start, match.end);
      }
    }
    return null;
  }

  List<_MentionRange> _mentionsOverlapping(String text, int start, int end) {
    final ranges = <_MentionRange>[];
    for (final match in mentionRegex.allMatches(text)) {
      if (start < match.end && end > match.start) {
        ranges.add(_MentionRange(match.start, match.end));
      }
    }
    return ranges;
  }

  bool _rangeFullyCovered(_MentionRange range, int start, int end) {
    return start <= range.start && end >= range.end;
  }

  _DiffRange? _computeDiff(String oldText, String newText) {
    if (oldText == newText) return null;

    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < newText.length &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var oldSuffix = oldText.length;
    var newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }

    return _DiffRange(
      oldStart: prefix,
      oldEnd: oldSuffix,
      newStart: prefix,
      newEnd: newSuffix,
    );
  }
}

class _MentionRange {
  const _MentionRange(this.start, this.end);

  final int start;
  final int end;
}

class _DiffRange {
  const _DiffRange({
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
  });

  final int oldStart;
  final int oldEnd;
  final int newStart;
  final int newEnd;
}
