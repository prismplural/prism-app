/// Colon-triggered Unicode emoji name completion for the chat composer.
///
/// Scope is deliberately narrow: this turns `:prefix` typed at the caret into a
/// bounded list of matches from the emoji data the app already ships for the
/// picker ([prismEmojiSet]). It adds no data, no custom/uploaded emoji, no
/// network call and no per-system schema.
///
/// Token rules and ranking are pure Dart so they can be tested without a widget
/// tree; the code-context guard borrows the chat renderer's own Markdown
/// grammar rather than re-implementing it.
library;

import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_plurality/features/chat/utils/chat_markdown_syntax.dart';
import 'package:prism_plurality/shared/emoji/prism_emoji_set.dart';

/// Upper bound on rows shown for one query.
const int emojiCompletionMaxResults = 8;

/// Longest `:name` token body that may open the completion popup.
const int emojiCompletionMaxPrefixLength = 40;

/// Characters allowed in a token body (`:grinning_face`, `:upside-down`, ...).
final RegExp _nameBodyRegex = RegExp(r'^[a-z0-9_+\-]+$');

final RegExp _nameCharRegex = RegExp(r'^[A-Za-z0-9_+\-]$');

/// Characters that may directly precede the trigger `:`.
///
/// Start-of-draft, whitespace and opening delimiters only. This single rule
/// rejects URL schemes (a colon after a letter) and clock times (a colon after
/// a digit) without a URL or time parser.
const String _triggerPrecedingChars = ' \t\n\r([{<"\'';

/// Code points that must never be split by an insertion at the caret:
/// combining marks, ZWJ, the emoji variation selector, skin-tone modifiers and
/// regional indicators (flag halves).
final RegExp _clusterContinuingRegex = RegExp(
  r'^[\p{M}\u200D\uFE0F\u{1F3FB}-\u{1F3FF}\u{1F1E6}-\u{1F1FF}]$',
  unicode: true,
);

/// Anything that could possibly start a code construct: a backtick or tilde
/// fence, inline code, a blockquote, a tab-indented line, or an indented code
/// line. A draft without any of these cannot contain code, so it never needs a
/// parse - that keeps long plain text completing without an AST.
final RegExp _codeStarterRegex = RegExp(r'[`~>\t]|^ {4}', multiLine: true);

/// First of the 32 Unicode noncharacters used as analysis-only markers.
const int _firstMarkerCodeUnit = 0xFDD0;

/// Number of marker candidates (U+FDD0..U+FDEF).
const int _markerCandidateCount = 0x20;

/// A live `:name` token whose caret sits at the end of the token.
@immutable
class EmojiCompletionTrigger {
  const EmojiCompletionTrigger({
    required this.start,
    required this.end,
    required this.prefix,
  });

  /// Index of the trigger `:` in the draft.
  final int start;

  /// Caret offset; the token is replaced in `[start, end)`.
  final int end;

  /// Lowercased token body typed after the `:`.
  final String prefix;

  @override
  bool operator ==(Object other) =>
      other is EmojiCompletionTrigger &&
      other.start == start &&
      other.end == end &&
      other.prefix == prefix;

  @override
  int get hashCode => Object.hash(start, end, prefix);

  @override
  String toString() =>
      'EmojiCompletionTrigger(start: $start, end: $end, prefix: $prefix)';
}

/// Detect a `:name` completion token for [selection] in [text].
///
/// Returns null for anything that is not a single, unambiguous token ending at
/// a collapsed caret: ranges, half-typed names, URL schemes, clock times, code
/// spans and blocks, over-long tokens and grapheme-cluster interiors.
EmojiCompletionTrigger? detectEmojiCompletionTrigger(
  String text,
  TextSelection selection, {
  TextRange composing = TextRange.empty,
}) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  return detectEmojiCompletionTriggerAt(
    text,
    selection.baseOffset,
    composing: composing,
  );
}

/// [detectEmojiCompletionTrigger] for a raw caret offset.
EmojiCompletionTrigger? detectEmojiCompletionTriggerAt(
  String text,
  int caret, {
  TextRange composing = TextRange.empty,
}) {
  if (caret < 1 || caret > text.length) return null;

  // An active IME composition owns the text around the caret: completing it
  // would fight the input method and could split a composed character.
  if (composing.isValid && !composing.isCollapsed) return null;

  // The caret must not sit inside a grapheme cluster, and must sit at the end
  // of the token: a caret in the middle of `:smile` has no single meaning.
  if (caret < text.length) {
    if (_isClusterContinuingAt(text, caret)) return null;
    if (_isNameCharacterAt(text, caret)) return null;
  }

  final colonIndex = text.lastIndexOf(':', caret - 1);
  if (colonIndex < 0) return null;

  if (colonIndex > 0 &&
      !_triggerPrecedingChars.contains(text[colonIndex - 1])) {
    return null;
  }

  final body = text.substring(colonIndex + 1, caret);
  if (body.isEmpty || body.length > emojiCompletionMaxPrefixLength) {
    return null;
  }
  final prefix = body.toLowerCase();
  if (!_nameBodyRegex.hasMatch(prefix)) return null;

  // Markdown code context: a colon inside `code` or a fenced block is literal
  // text, not a completion trigger.
  if (isInsideCodeContext(text, colonIndex)) return null;

  return EmojiCompletionTrigger(start: colonIndex, end: caret, prefix: prefix);
}

/// Whether the `:` at [colon] in [draft] sits inside code the chat renderer
/// would parse as code.
///
/// [colon] must be the `:` of an already validated `:name` token; anything else
/// fails closed, because substituting a different character could change the
/// structure the probe relies on.
///
/// The full draft is parsed with the same grammar and preprocessing as the
/// message bubble ([chatExtensionSet], [escapeLeadingHeadings]) after a single
/// analysis-only noncharacter replaces the colon, so a closing backtick *after*
/// the caret is still seen. The draft itself is never modified, and the marker
/// never reaches the controller, the draft cache or a sent message.
///
/// Nothing is cached here: the work is bounded per call (token checks, then a
/// parse of at most [chatMarkdownParseLimit] characters) and no draft or AST is
/// retained afterwards, so a long draft cannot outlive the composer through this
/// check. The only cache in this library is the emoji search memo in
/// [EmojiNameIndex], which holds the normalized prefix and limit, never a draft.
bool isInsideCodeContext(String draft, int colon) {
  if (colon < 0 || colon >= draft.length) return false;
  if (draft.codeUnitAt(colon) != 0x3A) return true; // not a token colon

  // Cheap necessary condition first: a draft with no code starter cannot hold
  // code, so long plain text still completes without building an AST.
  if (!_codeStarterRegex.hasMatch(draft)) return false;

  return _classifyCodeContext(draft, colon);
}

bool _classifyCodeContext(String draft, int colon) {
  // Shared renderer budget: over it we do not parse, and only the optional
  // suggestions hide. Input, draft, selection and send are untouched.
  if (draft.length > chatMarkdownParseLimit) return true;

  final marker = _chooseMarker(draft);
  if (marker == null) return true; // every candidate occurs: fail closed

  final probe = escapeLeadingHeadings(
    draft.replaceRange(colon, colon + 1, marker),
  );
  if (probe.length > chatMarkdownParseLimit) return true;

  final List<md.Node> nodes;
  try {
    nodes = _parseChatMarkdown(probe);
  } catch (_) {
    return true; // fail closed rather than guess
  }

  final survived = nodes.any((node) => node.textContent.contains(marker));
  if (!survived) return true; // consumed by a destination, title, info string
  if (_markerInsideCode(nodes, marker)) return true;

  // Conservative editing intent: a span the user is still typing stays
  // suppressed even though the renderer shows literal text (see
  // `_opensUnfinishedSpanOnCaretLine`).
  return _opensUnfinishedSpanOnCaretLine(draft, colon);
}

/// The analysis probe for [draft] with the marker substituted at [colon].
///
/// Test-only: it supports the marker-invariance and collision assertions (the
/// probe must parse to the same tree as the draft, with the colon swapped for a
/// noncharacter). Production code goes through [isInsideCodeContext].
@visibleForTesting
String emojiCodeContextProbe(String draft, int colon) {
  final marker =
      _chooseMarker(draft) ?? String.fromCharCode(_firstMarkerCodeUnit);
  return escapeLeadingHeadings(draft.replaceRange(colon, colon + 1, marker));
}

/// Pick the first noncharacter (U+FDD0..U+FDEF) that the draft does not already
/// contain, so the analysis marker is unambiguous.
String? _chooseMarker(String draft) {
  for (var i = 0; i < _markerCandidateCount; i++) {
    final candidate = String.fromCharCode(_firstMarkerCodeUnit + i);
    if (!draft.contains(candidate)) return candidate;
  }
  return null;
}

List<md.Node> _parseChatMarkdown(String text) {
  final document = md.Document(
    extensionSet: chatExtensionSet,
    encodeHtml: false,
  );
  return document.parseLines(const LineSplitter().convert(text));
}

bool _markerInsideCode(List<md.Node> nodes, String marker) {
  var inside = false;
  void visit(md.Node node) {
    if (inside || node is! md.Element) return;
    if ((node.tag == 'code' || node.tag == 'pre') &&
        node.textContent.contains(marker)) {
      inside = true;
      return;
    }
    for (final child in node.children ?? const <md.Node>[]) {
      visit(child);
    }
  }

  for (final node in nodes) {
    visit(node);
  }
  return inside;
}

/// Whether the colon sits after an unescaped backtick run on its own line that
/// no equal-length run closes later in the draft.
///
/// This is the one deliberate deviation from final-render parity: while a span is
/// still being typed, completion stays suppressed. Restricting it to the colon's
/// line keeps an escaped backtick, a closed multiline span, and stray runs from
/// an earlier line from suppressing ordinary text.
bool _opensUnfinishedSpanOnCaretLine(String draft, int colon) {
  final lineStart = draft.lastIndexOf('\n', colon - 1) + 1;
  final openRuns = <({int length, int start})>[];
  var index = 0;
  while (index < draft.length) {
    if (draft.codeUnitAt(index) != 0x60) {
      index++;
      continue;
    }
    var runLength = 1;
    while (index + runLength < draft.length &&
        draft.codeUnitAt(index + runLength) == 0x60) {
      runLength++;
    }
    if (!_isEscapedAt(draft, index)) {
      final matching = openRuns.lastIndexWhere(
        (run) => run.length == runLength,
      );
      if (matching >= 0) {
        openRuns.removeAt(matching);
      } else {
        openRuns.add((length: runLength, start: index));
      }
    }
    index += runLength;
  }
  return openRuns.any((run) => run.start >= lineStart && run.start < colon);
}

bool _isEscapedAt(String text, int index) {
  var backslashes = 0;
  var cursor = index - 1;
  while (cursor >= 0 && text.codeUnitAt(cursor) == 0x5C) {
    backslashes++;
    cursor--;
  }
  return backslashes.isOdd;
}

bool _isNameCharacterAt(String text, int index) {
  final codePoint = _codePointAt(text, index);
  return _nameCharRegex.hasMatch(String.fromCharCode(codePoint));
}

bool _isClusterContinuingAt(String text, int index) {
  final codePoint = _codePointAt(text, index);
  return _clusterContinuingRegex.hasMatch(String.fromCharCode(codePoint));
}

int _codePointAt(String text, int index) {
  final unit = text.codeUnitAt(index);
  final isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF;
  if (!isHighSurrogate || index + 1 >= text.length) return unit;
  final next = text.codeUnitAt(index + 1);
  if (next < 0xDC00 || next > 0xDFFF) return unit;
  return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
}

/// Pre-built, lowercased index over one emoji catalog.
///
/// The index is built once per catalog and reused; queries keep a single-entry
/// memo (last prefix to results), so there is no unbounded prefix cache.
class EmojiNameIndex {
  EmojiNameIndex._(this._entries);

  /// Index over the shipped picker catalog.
  static final EmojiNameIndex catalog = EmojiNameIndex.fromCategories(
    prismEmojiSet,
  );

  /// Build an index from an arbitrary catalog, e.g. a fixture in tests.
  factory EmojiNameIndex.fromCategories(List<CategoryEmoji> categories) {
    final seen = <String>{};
    final entries = <_IndexedEmoji>[];
    for (final category in categories) {
      for (final emoji in category.emoji) {
        if (!seen.add(emoji.emoji)) continue;
        final keywords = emoji.keywords
            .where((keyword) => keyword.isNotEmpty)
            .toList(growable: false);
        if (keywords.isEmpty) continue;
        // The first keyword segment is the CLDR annotation
        // (`grinning face | grinning | face | ...`).
        entries.add(
          _IndexedEmoji(
            emoji: emoji,
            label: keywords.first,
            primary: keywords.first.toLowerCase(),
            keywords: keywords
                .map((keyword) => keyword.toLowerCase())
                .toList(growable: false),
          ),
        );
      }
    }
    return EmojiNameIndex._(List<_IndexedEmoji>.unmodifiable(entries));
  }

  final List<_IndexedEmoji> _entries;
  String? _memoPrefix;
  int? _memoLimit;
  List<Emoji> _memoResults = const <Emoji>[];

  /// Matches for [prefix], best first, at most [limit] rows.
  ///
  /// The single cache entry is keyed by the normalized prefix **and** the
  /// effective limit, so changing either recomputes (a longer list must never
  /// be served for a smaller request). Empty input and non-positive limits
  /// return an empty list without touching the entry.
  List<Emoji> search(String prefix, {int limit = emojiCompletionMaxResults}) {
    final query = prefix.trim().toLowerCase();
    if (query.isEmpty || limit <= 0) return const <Emoji>[];
    // Callers cannot raise the popup's row cap.
    final effectiveLimit = limit > emojiCompletionMaxResults
        ? emojiCompletionMaxResults
        : limit;
    if (_memoPrefix == query && _memoLimit == effectiveLimit) {
      return _memoResults;
    }

    final scored = <(int, _IndexedEmoji)>[];
    for (final entry in _entries) {
      final tier = entry.tierFor(query);
      if (tier != null) scored.add((tier, entry));
    }

    scored.sort((a, b) {
      final byTier = a.$1.compareTo(b.$1);
      if (byTier != 0) return byTier;
      final byLabelLength = a.$2.label.length.compareTo(b.$2.label.length);
      if (byLabelLength != 0) return byLabelLength;
      return a.$2.emoji.emoji.compareTo(b.$2.emoji.emoji);
    });

    final results = List<Emoji>.unmodifiable(
      scored.take(effectiveLimit).map((scoredEntry) => scoredEntry.$2.emoji),
    );
    _memoPrefix = query;
    _memoLimit = effectiveLimit;
    _memoResults = results;
    return results;
  }
}

/// Convenience wrapper over [EmojiNameIndex.catalog].
List<Emoji> searchEmojiNames(
  String prefix, {
  int limit = emojiCompletionMaxResults,
  EmojiNameIndex? index,
}) {
  return (index ?? EmojiNameIndex.catalog).search(prefix, limit: limit);
}

class _IndexedEmoji {
  const _IndexedEmoji({
    required this.emoji,
    required this.label,
    required this.primary,
    required this.keywords,
  });

  final Emoji emoji;

  /// Annotation in its shipped casing, used for display and accessibility.
  final String label;

  /// Lowercased annotation.
  final String primary;

  /// Lowercased keyword segments, including the annotation itself.
  final List<String> keywords;

  /// Rank of this emoji for [query], or null when it does not match.
  ///
  /// 0 exact annotation, 1 annotation prefix, 2 exact keyword, 3 keyword
  /// prefix, 4 annotation word-boundary substring, 5 keyword substring.
  int? tierFor(String query) {
    if (primary == query) return 0;
    if (primary.startsWith(query)) return 1;

    var exactKeyword = false;
    var prefixKeyword = false;
    var containsKeyword = false;
    for (final keyword in keywords) {
      if (keyword == query) {
        exactKeyword = true;
        break;
      }
      if (keyword.startsWith(query)) prefixKeyword = true;
      if (!containsKeyword && keyword.contains(query)) containsKeyword = true;
    }
    if (exactKeyword) return 2;
    if (prefixKeyword) return 3;
    if (primary.contains(' $query')) return 4;
    if (containsKeyword) return 5;
    return null;
  }
}
